#!/usr/bin/env bash
set -eu

usage() {
  cat << 'EOF'
Usage: install-gemini-cmux-hook.sh [-h|--help]

Convenience launcher for native Antigravity hook setup:
  cmux hooks setup antigravity --yes
EOF
}

if [ "$#" -gt 0 ]; then
  case "$1" in
    -h|--help)
      if [ "$#" -eq 1 ]; then
        usage
        exit 0
      fi
      ;;
  esac
  echo "Error: Unexpected arguments: $*" >&2
  usage >&2
  exit 1
fi

command -v cmux >/dev/null 2>&1 || { echo "cmux binary not found on PATH" >&2; exit 127; }
exec cmux hooks setup antigravity --yes
