#!/usr/bin/env bash
set -euo pipefail

# Installer script for Antigravity skills
# Installs skills into ~/.gemini/antigravity-cli/skills/{skill_name}/SKILL.md by default,
# or into a custom target directory passed as an argument.

DEFAULT_TARGET_DIR="${HOME}/.gemini/antigravity-cli/skills"
TARGET_DIR="${1:-$DEFAULT_TARGET_DIR}"

# Expand tilde if passed as literal string
TARGET_DIR="${TARGET_DIR/#\~/$HOME}"

# If target ends with .agents or .agent, route to the skills subdirectory
if [[ "$(basename "$TARGET_DIR")" =~ ^\.?agents?$ ]]; then
  AGENT_DIR="${TARGET_DIR}/agents"
  TARGET_DIR="${TARGET_DIR}/skills"
else
  AGENT_DIR=""
fi

# Locate repository root (supports local run or curl | bash piping)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-}")" 2>/dev/null && pwd || echo "")"
CLEANUP_TMP=""

if [ -n "$SCRIPT_DIR" ] && [ -d "${SCRIPT_DIR}/skills" ]; then
  REPO_ROOT="${SCRIPT_DIR}"
elif [ -n "$SCRIPT_DIR" ] && [ -d "${SCRIPT_DIR}/../skills" ]; then
  REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
else
  # Running via curl | bash
  echo "==> Fetching delegate-worker-opencode from GitHub..."
  CLEANUP_TMP=$(mktemp -d)
  git clone --depth 1 https://github.com/TonyRice/delegate-worker-opencode.git "$CLEANUP_TMP" >/dev/null 2>&1
  REPO_ROOT="$CLEANUP_TMP"
fi

cleanup() {
  if [ -n "$CLEANUP_TMP" ] && [ -d "$CLEANUP_TMP" ]; then
    rm -rf "$CLEANUP_TMP"
  fi
}
trap cleanup EXIT

SKILLS_SRC="${REPO_ROOT}/skills"
SKILL_FILTER="${2:-}"

echo "==> Target skills directory: ${TARGET_DIR}"

installed_count=0

for skill_path in "${SKILLS_SRC}"/*; do
  [ -d "$skill_path" ] || continue
  skill_name="$(basename "$skill_path")"

  if [ -n "$SKILL_FILTER" ] && [ "$skill_name" != "$SKILL_FILTER" ]; then
    continue
  fi

  dest_skill_dir="${TARGET_DIR}/${skill_name}"
  echo "==> Installing skill '${skill_name}' into: ${dest_skill_dir}..."

  mkdir -p "${dest_skill_dir}"
  cp -R "${skill_path}/." "${dest_skill_dir}/"

  # Ensure scripts are executable if present
  if [ -d "${dest_skill_dir}/scripts" ]; then
    chmod +x "${dest_skill_dir}/scripts/"*
  fi

  echo "    - Skill:   ${dest_skill_dir}/SKILL.md"
  if [ -d "${dest_skill_dir}/scripts" ]; then
    echo "    - Scripts: ${dest_skill_dir}/scripts/"
  fi

  # Optionally install agent definition if project-local .agents layout is targeted
  if [ -n "${AGENT_DIR}" ] && [ -d "${REPO_ROOT}/agents/${skill_name}" ]; then
    mkdir -p "${AGENT_DIR}/${skill_name}"
    cp -R "${REPO_ROOT}/agents/${skill_name}/." "${AGENT_DIR}/${skill_name}/"
    echo "    - Agent:   ${AGENT_DIR}/${skill_name}/agent.md"
  fi

  installed_count=$((installed_count + 1))
done

if [ "$installed_count" -eq 0 ]; then
  echo "Warning: No skills found or matched filter '${SKILL_FILTER}'." >&2
  exit 1
fi

# Install delegate-worker CLI tool to ~/.local/bin
if [ -f "${REPO_ROOT}/bin/delegate-worker" ]; then
  mkdir -p "${HOME}/.local/bin"
  cp "${REPO_ROOT}/bin/delegate-worker" "${HOME}/.local/bin/delegate-worker"
  chmod +x "${HOME}/.local/bin/delegate-worker"
  echo "    - CLI:     ${HOME}/.local/bin/delegate-worker"
fi

# Configure ~/.bashrc with automated timestamped backup
BASHRC="${HOME}/.bashrc"
if [ -f "$BASHRC" ]; then
  if ! grep -q "delegate-worker-opencode" "$BASHRC"; then
    BACKUP="${HOME}/.bashrc.bak_$(date +%Y%m%d_%H%M%S)"
    cp "$BASHRC" "$BACKUP"
    echo "==> Backed up ~/.bashrc to: ${BACKUP}"
    cat << 'EOF' >> "$BASHRC"

# delegate-worker-opencode CLI
export PATH="$HOME/.local/bin:$PATH"
alias delegate-worker="$HOME/.local/bin/delegate-worker"
EOF
    echo "==> Configured ~/.bashrc for delegate-worker"
  fi
fi

echo "==> Successfully installed ${installed_count} skill(s) and CLI!"
