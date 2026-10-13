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

# Locate repository root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -d "${SCRIPT_DIR}/skills" ]; then
  REPO_ROOT="${SCRIPT_DIR}"
elif [ -d "${SCRIPT_DIR}/../skills" ]; then
  REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
else
  echo "Error: Could not locate skills directory." >&2
  exit 1
fi

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

echo "==> Successfully installed ${installed_count} skill(s)!"
