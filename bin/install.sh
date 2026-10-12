#!/usr/bin/env bash
set -euo pipefail

# Installer script for delegate-worker-opencode
# Installs into current project's .agents directory or global ~/.gemini/config

TARGET_DIR="${1:-.agents}"

echo "==> Installing delegate-worker-opencode into: ${TARGET_DIR}..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

mkdir -p "${TARGET_DIR}/skills/delegate-worker/scripts"
mkdir -p "${TARGET_DIR}/agents/delegate-worker"

cp "${SCRIPT_DIR}/skills/delegate-worker/SKILL.md" "${TARGET_DIR}/skills/delegate-worker/"
cp "${SCRIPT_DIR}/skills/delegate-worker/scripts/"* "${TARGET_DIR}/skills/delegate-worker/scripts/"
chmod +x "${TARGET_DIR}/skills/delegate-worker/scripts/"*

cp "${SCRIPT_DIR}/agents/delegate-worker/agent.md" "${TARGET_DIR}/agents/delegate-worker/"

echo "==> Installed successfully!"
echo "    - Skill: ${TARGET_DIR}/skills/delegate-worker/SKILL.md"
echo "    - Scripts: ${TARGET_DIR}/skills/delegate-worker/scripts/"
echo "    - Agent: ${TARGET_DIR}/agents/delegate-worker/agent.md"
