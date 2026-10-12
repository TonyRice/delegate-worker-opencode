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

# 2. Argument validation & subcommands
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

INPUT="${2:-}"
MODEL="${3:-opencode-go/deepseek-v4.1-flash}"

if [ -z "$MODE" ] || [ -z "$INPUT" ]; then
  echo "Usage: $0 <discover|build|continue|init> <\"prompt\"|path/to/workorder.md|session_id> [model|prompt]" >&2
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

case "$MODE" in
  discover|explore|plan)
    SESSION_ID="$(gen_session_id)"
    if [ -f "$INPUT" ]; then
      TASK_PAYLOAD=$(cat "$INPUT")
    else
      TASK_PAYLOAD="$INPUT"
    fi

    echo "==> Spawning OpenCode Discovery Subagent ($MODEL) [Session: $SESSION_ID]..."
    if ! opencode run --agent plan --auto --session "$SESSION_ID" "$TASK_PAYLOAD" --model "$MODEL"; then
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

    echo "==> Spawning OpenCode Builder Subagent ($MODEL) [Session: $SESSION_ID]..."
    BUILD_EXIT_CODE=0
    if ! opencode run --agent build --auto --session "$SESSION_ID" "$TASK_PAYLOAD" --model "$MODEL"; then
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
    echo "==> Subagent finished. Working tree diff:"
    git diff --stat
    ;;

  continue)
    SESSION_ID="$INPUT"
    FOLLOWUP_PROMPT="${3:-}"
    if [ -z "$FOLLOWUP_PROMPT" ]; then
      echo "Usage: $0 continue <session_id> \"<follow-up instruction>\" [model]" >&2
      exit 1
    fi
    TARGET_MODEL="${4:-opencode-go/deepseek-v4.1-flash}"

    echo "==> Continuing OpenCode Session: $SESSION_ID ($TARGET_MODEL)..."
    if ! opencode run --auto --session "$SESSION_ID" "$FOLLOWUP_PROMPT" --model "$TARGET_MODEL"; then
      echo "Error: Follow-up command failed in session $SESSION_ID." >&2
      archive_session "$SESSION_ID" "continue"
      exit 1
    fi
    archive_session "$SESSION_ID" "continue"
    ;;

  *)
    echo "Error: Unknown mode '$MODE'. Use 'discover', 'build', 'continue', or 'init'." >&2
    exit 1
    ;;
esac
