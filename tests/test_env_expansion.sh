#!/usr/bin/env bash
# tests/test_env_expansion.sh — Integration tests for variable expansion,
# quoting, and special parameters in hsh.
#
# Usage: bash tests/test_env_expansion.sh [path/to/hsh]
# Requires: make (to build) or a pre-built ./hsh binary.

set -euo pipefail

HSH="${1:-./hsh}"

if [[ ! -x "$HSH" ]]; then
  echo "ERROR: shell binary not found at $HSH" >&2
  echo "Run 'make' first, then re-run this script." >&2
  exit 1
fi

PASS=0
FAIL=0
ERRORS=()

run_test() {
  local desc="$1"
  local input="$2"
  local expected="$3"

  local actual
  actual=$(printf '%s\n' "$input" | "$HSH" 2>/dev/null) || true

  if [[ "$actual" == "$expected" ]]; then
    PASS=$(( PASS + 1 ))
    printf '  \033[32mPASS\033[0m  %s\n' "$desc"
  else
    FAIL=$(( FAIL + 1 ))
    ERRORS+=("$desc")
    printf '  \033[31mFAIL\033[0m  %s\n' "$desc"
    printf '         expected: %q\n' "$expected"
    printf '           actual: %q\n' "$actual"
  fi
}

echo "=== Environment & Variable Expansion Tests ==="
echo

# -------------------------------------------------------
# 1. Basic variable expansion
# -------------------------------------------------------
echo "--- Basic expansion ---"

run_test "simple variable" \
  'X=hello; echo $X' \
  'hello'

run_test "variable in double quotes" \
  'NAME=world; echo "hello $NAME"' \
  'hello world'

run_test "variable NOT expanded in single quotes" \
  "NAME=world; echo 'hello $NAME'" \
  'hello $NAME'

run_test "undefined variable expands to empty string" \
  'echo "[$UNDEFINED_VAR_XYZ]"' \
  '[]'

run_test "curly-brace variable expansion" \
  'FOO=bar; echo ${FOO}baz' \
  'barbaz'

# -------------------------------------------------------
# 2. Special parameters
# -------------------------------------------------------
echo
echo "--- Special parameters ---"

run_test '$? is 0 after successful command' \
  'true; echo $?' \
  '0'

run_test '$? is non-zero after failed command' \
  'false; echo $?' \
  '1'

run_test '$$ is a non-empty integer (shell PID)' \
  'echo $$ | grep -Eq "^[0-9]+$" && echo yes' \
  'yes'

run_test '$0 is the shell name' \
  'echo $0 | grep -q hsh && echo yes' \
  'yes'

# -------------------------------------------------------
# 3. export and unset
# -------------------------------------------------------
echo
echo "--- export / unset ---"

run_test "exported variable visible in child process" \
  'export MYVAR=42; env | grep -c "^MYVAR=42$"' \
  '1'

run_test "unset removes variable" \
  'MYVAR=42; unset MYVAR; echo "[$MYVAR]"' \
  '[]'

run_test "export VAR=value shorthand" \
  'export SHORTHAND=ok; echo $SHORTHAND' \
  'ok'

run_test "unset does not affect parent env" \
  'export OUTER=yes; (unset OUTER); echo $OUTER' \
  'yes'

# -------------------------------------------------------
# 4. Quoting edge cases
# -------------------------------------------------------
echo
echo "--- Quoting ---"

run_test "backslash escapes space" \
  'echo hello\ world' \
  'hello world'

run_test "double-quoted string preserves spaces" \
  'echo "  spaces  "' \
  '  spaces  '

run_test "single-quoted backslash is literal" \
  "echo '\\n'" \
  '\n'

run_test "adjacent quoted sections are concatenated" \
  'echo "foo"'"'"'bar'"'"'"baz"' \
  'foobarbaz'

run_test "variable expansion inside double quotes" \
  'A=x; B=y; echo "$A$B"' \
  'xy'

run_test "dollar sign literal in single quotes" \
  "echo '$HOME'" \
  '$HOME'

# -------------------------------------------------------
# 5. Expansion in redirections
# -------------------------------------------------------
echo
echo "--- Expansion in redirections ---"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

run_test "variable used as redirect target" \
  "OUTFILE=$TMP/out.txt; echo hello > "$OUTFILE"; cat "$OUTFILE"" \
  'hello'

run_test "redirect append with variable path" \
  "F=$TMP/append.txt; echo line1 > "$F"; echo line2 >> "$F"; wc -l < "$F" | tr -d ' '" \
  '2'

# -------------------------------------------------------
# 6. PATH and command resolution
# -------------------------------------------------------
echo
echo "--- PATH resolution ---"

run_test "command found via PATH" \
  'which ls | grep -q ls && echo yes' \
  'yes'

run_test "command not found exits 127" \
  'totally_nonexistent_cmd_xyz 2>/dev/null; echo $?' \
  '127'

# -------------------------------------------------------
# Summary
# -------------------------------------------------------
echo
echo "============================================"
printf "Results: \033[32m%d passed\033[0m, \033[31m%d failed\033[0m\n" "$PASS" "$FAIL"
echo "============================================"

if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo "Failed tests:"
  for e in "${ERRORS[@]}"; do
    echo "  - $e"
  done
  exit 1
fi

exit 0
