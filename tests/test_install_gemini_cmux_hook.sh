#!/usr/bin/env bash
# Behavioral test for scripts/install-gemini-cmux-hook.sh in bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/install-gemini-cmux-hook.sh"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

TEST_HOME="$TMP_DIR/home"
BIN_DIR="$TEST_HOME/bin"
LOG_FILE="$TEST_HOME/cmux.log"
mkdir -p "$BIN_DIR"
export LOG_FILE

cat << MOCK > "$BIN_DIR/cmux"
#!/usr/bin/env bash
set -euo pipefail
printf 'cmux args: %s\n' "\$*" >> "$LOG_FILE"
if [ "\${MOCK_FAIL:-0}" = "1" ]; then
  echo "mock error: cmux setup failed" >&2
  exit 42
fi
echo "mock stdout: hooks setup finished"
MOCK
chmod +x "$BIN_DIR/cmux"

export HOME="$TEST_HOME"
export PATH="$BIN_DIR:$PATH"
export LOG_FILE

echo "=== Test 1: Missing cmux failure ==="
# PATH with no cmux
set +e
MISSING_OUT="$(PATH="/usr/bin:/bin" "$SCRIPT" 2>&1)"
MISSING_STATUS="$?"
set -e
if [ "$MISSING_STATUS" -eq 0 ]; then
  echo "FAIL: script should fail when cmux is missing" >&2
  exit 1
fi
if [[ "$MISSING_OUT" != *"cmux binary not found"* ]]; then
  echo "FAIL: expected 'cmux binary not found' in output, got: $MISSING_OUT" >&2
  exit 1
fi

echo "=== Test 2: Native Antigravity Setup Invocation ==="
rm -f "$LOG_FILE"
OUT="$("$SCRIPT")"
if ! grep -Fq "cmux args: hooks setup antigravity --yes" "$LOG_FILE"; then
  echo "FAIL: expected 'cmux args: hooks setup antigravity --yes' invocation, got: $(cat "$LOG_FILE" 2>/dev/null)" >&2
  exit 1
fi
if [[ "$OUT" != *"mock stdout: hooks setup finished"* ]]; then
  echo "FAIL: stdout was not preserved" >&2
  exit 1
fi

# Ensure installer did not create ~/.gemini/settings.json or ~/.gemini/config/hooks.json directly
if [ -f "$TEST_HOME/.gemini/settings.json" ]; then
  echo "FAIL: installer created ~/.gemini/settings.json directly" >&2
  exit 1
fi
if [ -f "$TEST_HOME/.gemini/config/hooks.json" ]; then
  echo "FAIL: installer created ~/.gemini/config/hooks.json directly" >&2
  exit 1
fi

echo "=== Test 3: Exit code and stderr preservation on failure ==="
rm -f "$LOG_FILE"
set +e
ERR_OUT="$(MOCK_FAIL=1 "$SCRIPT" 2>&1)"
STATUS="$?"
set -e
if [ "$STATUS" -ne 42 ]; then
  echo "FAIL: expected status 42, got $STATUS" >&2
  exit 1
fi
if [[ "$ERR_OUT" != *"mock error: cmux setup failed"* ]]; then
  echo "FAIL: stderr was not preserved" >&2
  exit 1
fi

echo "=== Test 4: Existing settings preservation ==="
mkdir -p "$TEST_HOME/.gemini/config"
echo '{"unrelated": true}' > "$TEST_HOME/.gemini/settings.json"
echo '{"existingHook": true}' > "$TEST_HOME/.gemini/config/hooks.json"
"$SCRIPT" >/dev/null
CONTENT_SETTINGS="$(cat "$TEST_HOME/.gemini/settings.json")"
CONTENT_HOOKS="$(cat "$TEST_HOME/.gemini/config/hooks.json")"
if [ "$CONTENT_SETTINGS" != '{"unrelated": true}' ]; then
  echo "FAIL: ~/.gemini/settings.json was modified" >&2
  exit 1
fi
if [ "$CONTENT_HOOKS" != '{"existingHook": true}' ]; then
  echo "FAIL: ~/.gemini/config/hooks.json was modified directly by launcher" >&2
  exit 1
fi

echo "=== Test 5: Help output ==="
for flag in -h --help; do
  HELP_OUT="$("$SCRIPT" "$flag")"
  if [[ "$HELP_OUT" != *"Usage:"* ]]; then
    echo "FAIL: help output missing Usage reference for $flag" >&2
    exit 1
  fi
done

echo "ALL TESTS PASSED"
