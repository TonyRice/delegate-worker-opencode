#!/usr/bin/env bash
set -euo pipefail

# Universal installer entrypoint for delegate-worker-opencode
# Works both locally (./install.sh) and via remote curl pipe:
# curl -fsSL https://raw.githubusercontent.com/TonyRice/delegate-worker-opencode/main/install.sh | bash

if [ "${#BASH_SOURCE[@]}" -gt 0 ]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || echo "")"
else
  SCRIPT_DIR=""
fi

if [ -n "$SCRIPT_DIR" ] && [ -f "${SCRIPT_DIR}/bin/install.sh" ]; then
  exec "${SCRIPT_DIR}/bin/install.sh" "$@"
else
  exec bash -c "$(curl -fsSL https://raw.githubusercontent.com/TonyRice/delegate-worker-opencode/main/bin/install.sh)" -- "$@"
fi
