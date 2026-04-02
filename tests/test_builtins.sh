#!/usr/bin/env bash
# tests/test_builtins.sh
# Focused integration tests for hsh built-in commands.
# Run with:  bash tests/test_builtins.sh [path/to/hsh]
#
# Each test sends commands to the shell via stdin and checks stdout/stderr
# and the exit status.  A summary is printed at the end.
#
# Requirements: the shell binary must be built first (make).

set -euo pipefail

HSH="${1:-./hsh}"

if [[ ! -x "$HSH" ]]; then
  echo "ERROR: shell binary not found at '$HSH'. Run 'make' first." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

PASS=0
FAIL=0
SKIP=0

_run() {
  # _run <description> <stdin_commands> <expected_stdout_pattern> [expected_exit]
  local desc="$1" cmds="$2" pattern="$3" expected_exit="${4:-0}"
  local actual_out actual_exit

  actual_out=$(printf '%s\n' "$cmds" | "$HSH" 2>/dev/null) || true
  actual_exit=$?

  if echo "$actual_out" | grep -qE "$pattern" && [[ "$actual_exit" -eq "$expected_exit" ]]; then
    echo "  PASS  $desc"
    (( PASS++ )) || true
  else
    echo "  FAIL  $desc"
    echo "        expected pattern : $pattern  (exit $expected_exit)"
    echo "        got output       : $(echo "$actual_out" | head -3)"
    echo "        got exit         : $actual_exit"
    (( FAIL++ )) || true
  fi
}

_section() { echo; echo "=== $* ==="; }

# ---------------------------------------------------------------------------
# cd / pwd
# ---------------------------------------------------------------------------

_section "cd and pwd"

_run "pwd prints working directory" \
  "pwd" \
  "^/"

_run "cd to /tmp then pwd" \
  $'cd /tmp\npwd' \
  "^/tmp$"

_run "cd to absolute path" \
  $'cd /usr/bin\npwd' \
  "^/usr/bin$"

_run "cd with no args goes to HOME" \
  $'cd\npwd' \
  "^$HOME"

_run "cd - returns to previous dir" \
  $'cd /tmp\ncd /var\ncd -\npwd' \
  "^/tmp$"

_run "cd to nonexistent dir exits nonzero" \
  "cd /no_such_dir_xyz_abc" \
  "." \
  1

# ---------------------------------------------------------------------------
# export / unset
# ---------------------------------------------------------------------------

_section "export and unset"

_run "export sets a variable visible to child" \
  $'export MYVAR=hello\necho $MYVAR' \
  "^hello$"

_run "unset removes a variable" \
  $'export FOO=bar\nunset FOO\necho ${FOO:-UNSET}' \
  "^UNSET$"

_run "unset of nonexistent variable does not error" \
  "unset NO_SUCH_VAR_XYZ" \
  "" \
  0

_run "exported variable visible to child process" \
  $'export GREETING=hi\n/usr/bin/env | grep GREETING' \
  "GREETING=hi"

# ---------------------------------------------------------------------------
# exit
# ---------------------------------------------------------------------------

_section "exit"

_run "exit with no args returns 0" \
  "exit" \
  "" \
  0

_run "exit 42 returns 42" \
  "exit 42" \
  "" \
  42

_run "exit after failed command returns that exit code" \
  $'false\nexit $?' \
  "" \
  1

# ---------------------------------------------------------------------------
# history
# ---------------------------------------------------------------------------

_section "history"

_run "history shows previous commands" \
  $'echo one\necho two\nhistory' \
  "echo one"

_run "history numbers entries" \
  $'echo alpha\nhistory' \
  "[0-9]"

# ---------------------------------------------------------------------------
# $? — last exit status
# ---------------------------------------------------------------------------

_section "Exit status"

_run "dollar-question is 0 after successful command" \
  $'true\necho $?' \
  "^0$"

_run "dollar-question is 1 after failed command" \
  $'false\necho $?' \
  "^1$"

_run "dollar-question is 127 for command not found" \
  $'no_such_cmd_xyz 2>/dev/null\necho $?' \
  "^127$"

# ---------------------------------------------------------------------------
# jobs smoke tests
# ---------------------------------------------------------------------------

_section "jobs (smoke tests)"

_run "jobs prints nothing when no background jobs" \
  "jobs" \
  "" \
  0

# fg/bg cannot be fully tested in non-interactive pipe but shell must not crash
_run "fg with no jobs does not crash shell" \
  $'fg\necho still_alive' \
  "still_alive"

_run "bg with no jobs does not crash shell" \
  $'bg\necho still_alive' \
  "still_alive"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo
echo "Results: $PASS passed, $FAIL failed, $SKIP skipped"
echo

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
exit 0
