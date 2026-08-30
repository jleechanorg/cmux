#!/usr/bin/env bash
# install-gemini-cmux-hook.sh
#
# Compatibility launcher for native cmux Antigravity hook setup.
#
# Antigravity hook configuration is stored natively in ~/.gemini/config/hooks.json
# and managed directly by the cmux CLI (`cmux hooks setup antigravity --yes`).
#
# Gemini CLI settings.json is separate and not modified by this launcher.

set -euo pipefail

show_help() {
  cat << 'HELP'
Usage: install-gemini-cmux-hook.sh [options]

Compatibility launcher for native cmux Antigravity hook setup.

Options:
  -u, --uninstall    Run `cmux hooks uninstall antigravity --yes`
  -h, --help         Show this help message

Description:
  This script is a lightweight convenience wrapper around native cmux Antigravity
  hook management (`cmux hooks setup antigravity --yes`).

  - Antigravity hook config is located at ~/.gemini/config/hooks.json.
  - Setup:     cmux hooks setup antigravity --yes
  - Uninstall: cmux hooks uninstall antigravity --yes

  Note: Gemini CLI settings.json is separate and is not modified by this script.
HELP
}

ACTION="setup"

while [ "$#" -gt 0 ]; do
  case "$1" in
    -u|--uninstall|uninstall)
      ACTION="uninstall"
      shift
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    *)
      echo "Error: Unknown argument '$1'" >&2
      show_help >&2
      exit 1
      ;;
  esac
done

if ! command -v cmux >/dev/null 2>&1; then
  echo "Error: cmux binary not found on PATH. Please ensure cmux is installed and available in PATH." >&2
  exit 1
fi

if [ "$ACTION" = "uninstall" ]; then
  exec cmux hooks uninstall antigravity --yes
else
  exec cmux hooks setup antigravity --yes
fi
