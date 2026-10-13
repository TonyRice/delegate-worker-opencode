#!/usr/bin/env bash
set -euo pipefail

# 1. Pre-flight check & auto-resolve PATH for opencode
if ! command -v opencode >/dev/null 2>&1; then
  # Check standard install locations
  if [ -x "${HOME}/.opencode/bin/opencode" ]; then
    export PATH="${HOME}/.opencode/bin:${PATH}"
  elif [ -x "/usr/local/bin/opencode" ]; then
    export PATH="/usr/local/bin:${PATH}"
  fi
fi

if ! command -v opencode >/dev/null 2>&1; then
  echo "Error: 'opencode' binary not found in PATH or standard install paths (~/.opencode/bin)." >&2
  echo "Please verify OpenCode is installed and accessible." >&2
  exit 127
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Resolve repository root dynamically (supports git repo root or fallback to script directory ancestry)
if git rev-parse --show-toplevel >/dev/null 2>&1; then
  REPO_ROOT="$(git rev-parse --show-toplevel)"
else
  # Fallback: check standard .agents directory ancestry
  REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
fi

VERSION="0.2.0"
GITHUB_REPO="TonyRice/delegate-worker-opencode"
VERSION_URL="https://raw.githubusercontent.com/${GITHUB_REPO}/main/VERSION"
UPDATE_INTERVAL_SECS="${DELEGATE_WORKER_UPDATE_INTERVAL:-86400}" # 24 hours

# Helper: compare semantic versions (returns 0 if $1 < $2)
version_is_older() {
  local current="$1"
  local remote="$2"
  [ "$current" != "$remote" ] && [ "$(printf '%s\n%s' "$current" "$remote" | sort -V | head -n1)" = "$current" ]
}

# Helper: check for updates from GitHub (non-blocking, cached, stderr only)
check_github_update() {
  local force="${1:-0}"
  if [ "${DELEGATE_WORKER_NO_UPDATE:-0}" = "1" ] && [ "$force" -ne 1 ]; then
    return 0
  fi

  local cache_dir="${HOME}/.cache/delegate-worker"
  local cache_file="${cache_dir}/last_update_check"
  local latest_file="${cache_dir}/latest_version"
  mkdir -p "$cache_dir"

  local now
  now=$(date +%s)

  # Check cache expiry if not forced
  if [ "$force" -ne 1 ] && [ -f "$cache_file" ]; then
    local last_check
    last_check=$(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file" 2>/dev/null || echo 0)
    if [ $((now - last_check)) -lt "$UPDATE_INTERVAL_SECS" ]; then
      if [ -f "$latest_file" ]; then
        local cached_remote
        cached_remote=$(cat "$latest_file" 2>/dev/null | tr -d '[:space:]')
        if [ -n "$cached_remote" ] && version_is_older "$VERSION" "$cached_remote"; then
          echo "[delegate-worker] Update available: v${VERSION} -> v${cached_remote} (https://github.com/${GITHUB_REPO})" >&2
        fi
      fi
      return 0
    fi
  fi

  # Update timestamp
  touch "$cache_file"

  # Non-blocking fetch with short timeout (max 2 seconds)
  local remote_version
  remote_version=$(curl -fsSL --max-time 2 "$VERSION_URL" 2>/dev/null | tr -d '[:space:]' || true)

  if [ -n "$remote_version" ]; then
    echo "$remote_version" > "$latest_file"
    if version_is_older "$VERSION" "$remote_version"; then
      echo "[delegate-worker] Update available: v${VERSION} -> v${remote_version} (https://github.com/${GITHUB_REPO})" >&2
    elif [ "$force" -eq 1 ]; then
      echo "[delegate-worker] Up to date (v${VERSION})." >&2
    fi
  elif [ "$force" -eq 1 ]; then
    echo "[delegate-worker] Warning: Could not check updates (GitHub unreachable or timed out)." >&2
  fi
}

# 2. Argument validation & subcommands
PROGRESS_FLAG=""
VERBOSE="${VERBOSE:-0}"
MAX_CHARS="${SUBAGENT_MAX_CHARS:-5000}"

# Parse optional leading flags
while [[ "${1:-}" =~ ^- ]]; do
  case "$1" in
    --progress)
      PROGRESS_FLAG="--progress"
      shift
      ;;
    --verbose|-v)
      VERBOSE=1
      shift
      ;;
    --max-chars)
      MAX_CHARS="${2:-5000}"
      shift 2
      ;;
    -V|--version)
      echo "delegate-worker v${VERSION}"
      exit 0
      ;;
    --check-update)
      check_github_update 1
      exit 0
      ;;
    --no-update-check)
      DELEGATE_WORKER_NO_UPDATE=1
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [--progress] [--verbose] [--max-chars N] [--no-update-check] <discover|build|continue|init|check-update|version> <input> [model|prompt]"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

if [ "${PROGRESS:-0}" = "1" ]; then
  PROGRESS_FLAG="--progress"
fi

# Run background update check (cached 24h, non-blocking)
check_github_update 0

MODE="${1:-}"

if [ "$MODE" = "init" ]; then
  TASK_NAME="${2:-}"
  if [ -z "$TASK_NAME" ]; then
    echo "Usage: $0 init <task-name-slug>" >&2
    exit 1
  fi
  TARGET_PATH="${REPO_ROOT}/.agents/workorders/${TASK_NAME}.md"
  mkdir -p "${REPO_ROOT}/.agents/workorders"
  if [ -f "$TARGET_PATH" ]; then
    echo "Error: Work order already exists at ${TARGET_PATH}" >&2
    exit 1
  fi
  cat << 'EOF' > "$TARGET_PATH"
# Work Order: TASK_NAME_PLACEHOLDER

## 1. Objective
<One to two sentences stating the exact functional requirement.>

## 2. Target Files
- Modify: `path/to/target-file.ext`
- Create: `path/to/test-file.ext`

## 3. Implementation Contract
- **Classes / Functions:** <Exact names, parameters, return types, and throws clauses>
- **Behavioral Invariants:** <Critical edge cases, nullability, validation rules>
- **Error Handling:** <Specific exception types to throw or catch>

## 4. Verification Command
`<exact shell command to verify: e.g. npm test or ./mvnw test -Dtest=MyTest>`
EOF
  sed -i "s/TASK_NAME_PLACEHOLDER/${TASK_NAME}/g" "$TARGET_PATH"
  echo "==> Created work order template at .agents/workorders/${TASK_NAME}.md"
  exit 0
fi

if [ "$MODE" = "version" ]; then
  echo "delegate-worker v${VERSION}"
  exit 0
fi

if [ "$MODE" = "check-update" ]; then
  check_github_update 1
  exit 0
fi

INPUT="${2:-}"
MODEL="${3:-opencode-go/deepseek-v4.1-flash}"

if [ -z "$MODE" ] || [ -z "$INPUT" ]; then
  echo "Usage: $0 [--progress] [--verbose] [--no-update-check] <discover|build|continue|init|check-update|version> <input> [model|prompt]" >&2
  exit 1
fi

# Generate opencode-compliant session ID starting with "ses_"
gen_session_id() {
  echo "ses_$(date +%s)_$(head -c 6 /dev/urandom | xxd -p)"
}

# Helper: archive session
archive_session() {
  local ses_id="$1"
  local tmode="$2"
  if [ -x "${SCRIPT_DIR}/archive-subagent-session.py" ]; then
    "${SCRIPT_DIR}/archive-subagent-session.py" "$ses_id" "$tmode" || true
  fi
}

# Helper: execute OpenCode via filter wrapper
execute_subagent() {
  local agent_name="$1"
  local session_id="$2"
  local payload="$3"
  local model="$4"
  local tmode="$5"

  local archive_dir="${REPO_ROOT}/.agents/opencode/sessions"
  mkdir -p "$archive_dir"

  local agent_arg=()
  if [ -n "$agent_name" ]; then
    agent_arg=(--agent "$agent_name")
  fi

  if [ "$VERBOSE" = "1" ]; then
    echo "==> Spawning OpenCode Subagent ($model) [Session: $session_id] (VERBOSE)..."
    opencode run "${agent_arg[@]}" --auto --session "$session_id" "$payload" --model "$model"
  else
    local filter_args=(
      --session "$session_id"
      --mode "$tmode"
      --model "$model"
      --max-chars "$MAX_CHARS"
      --archive-dir "$archive_dir"
    )
    if [ -n "$PROGRESS_FLAG" ]; then
      filter_args+=("$PROGRESS_FLAG")
    fi

    echo "==> Spawning OpenCode Subagent ($model) [Session: $session_id]..." >&2
    opencode run "${agent_arg[@]}" --auto --session "$session_id" "$payload" --model "$model" --format json \
      | python3 "${SCRIPT_DIR}/filter-subagent-stream.py" "${filter_args[@]}"
  fi
}

case "$MODE" in
  discover|explore|plan)
    SESSION_ID="$(gen_session_id)"
    if [ -f "$INPUT" ]; then
      TASK_PAYLOAD=$(cat "$INPUT")
    else
      TASK_PAYLOAD="$INPUT"
    fi

    if ! execute_subagent "plan" "$SESSION_ID" "$TASK_PAYLOAD" "$MODEL" "discover"; then
      echo "Error: OpenCode discovery subagent failed." >&2
      archive_session "$SESSION_ID" "discover"
      exit 1
    fi
    archive_session "$SESSION_ID" "discover"
    ;;

  build|implement)
    SESSION_ID="$(gen_session_id)"
    if [ -f "$INPUT" ]; then
      WORKORDER_FILE="$INPUT"
      TASK_PAYLOAD=$(cat "$INPUT")
    else
      WORKORDER_FILE=""
      TASK_PAYLOAD="$INPUT"
    fi

    # Snapshot working tree state for scope guard validation
    PRE_STATUS_FILE=$(mktemp)
    git status --porcelain > "$PRE_STATUS_FILE"

    BUILD_EXIT_CODE=0
    if ! execute_subagent "build" "$SESSION_ID" "$TASK_PAYLOAD" "$MODEL" "build"; then
      BUILD_EXIT_CODE=$?
      echo "Error: OpenCode builder subagent failed with code $BUILD_EXIT_CODE." >&2
    fi

    archive_session "$SESSION_ID" "build"

    # Run Scope Guard if a work order file was provided
    if [ -n "$WORKORDER_FILE" ] && [ -x "${SCRIPT_DIR}/validate-workorder-scope.py" ]; then
      "${SCRIPT_DIR}/validate-workorder-scope.py" "$WORKORDER_FILE" "$PRE_STATUS_FILE" || true
    fi
    rm -f "$PRE_STATUS_FILE"

    if [ "$BUILD_EXIT_CODE" -ne 0 ]; then
      exit "$BUILD_EXIT_CODE"
    fi

    echo ""
    echo "==> Working tree diff:"
    git diff --stat
    ;;

  continue)
    SESSION_ID="$INPUT"
    FOLLOWUP_PROMPT="${3:-}"
    if [ -z "$FOLLOWUP_PROMPT" ]; then
      echo "Usage: $0 [--progress] [--verbose] continue <session_id> \"<follow-up instruction>\" [model]" >&2
      exit 1
    fi
    TARGET_MODEL="${4:-opencode-go/deepseek-v4.1-flash}"

    if ! execute_subagent "" "$SESSION_ID" "$FOLLOWUP_PROMPT" "$TARGET_MODEL" "continue"; then
      echo "Error: Follow-up command failed in session $SESSION_ID." >&2
      archive_session "$SESSION_ID" "continue"
      exit 1
    fi
    archive_session "$SESSION_ID" "continue"
    ;;

  version)
    echo "delegate-worker v${VERSION}"
    exit 0
    ;;

  check-update)
    check_github_update 1
    exit 0
    ;;

  *)
    echo "Error: Unknown mode '$MODE'. Use 'discover', 'build', 'continue', 'init', 'check-update', or 'version'." >&2
    exit 1
    ;;
esac
