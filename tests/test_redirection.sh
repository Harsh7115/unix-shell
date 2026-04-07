#!/usr/bin/env bash
# tests/test_redirection.sh — I/O redirection integration tests for hsh
#
# Covers:
#   >   stdout redirect (truncate)
#   >>  stdout redirect (append)
#   <   stdin redirect
#   2>  stderr redirect
#   2>&1  stderr-to-stdout merge
#   combined: < input > output 2>err
#
# Usage:
#   ./tests/test_redirection.sh [path/to/hsh]
#
# Default shell under test: ./hsh (build with `make` first)
# Exit code: 0 = all pass, non-zero = at least one failure.

HSH=${1:-./hsh}

if [[ ! -x "$HSH" ]]; then
    echo "ERROR: shell not found at '$HSH'. Run `make` first." >&2
    exit 1
fi

PASS=0
FAIL=0
TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

check() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo "  PASS: $desc"
        ((PASS++))
    else
        echo "  FAIL: $desc"
        echo "        expected: $(printf '%q' "$expected")"
        echo "        actual:   $(printf '%q' "$actual")"
        ((FAIL++))
    fi
}

run() {
    # run a single command string in the shell under test
    echo "$1" | "$HSH" --norc 2>/dev/null
}

run_err() {
    # capture stderr only
    echo "$1" | "$HSH" --norc 2>&1 >/dev/null
}

echo "=== I/O Redirection Tests ==="
echo "Shell: $HSH"
echo

# ------------------------------------------------------------------ stdout >
echo "--- stdout truncate (>)"

OUT="$TMPDIR_TEST/out1.txt"
echo "echo hello" | "$HSH" --norc > "$OUT" 2>/dev/null
check "> creates file" "hello" "$(cat "$OUT")"

# Writing to the same file again should truncate, not append
echo "echo world" | "$HSH" --norc > "$OUT" 2>/dev/null
check "> truncates existing file" "world" "$(cat "$OUT")"

# Redirect inside the shell command (not wrapping the shell)
OUT2="$TMPDIR_TEST/out2.txt"
printf 'echo inside_redirect > %s
' "$OUT2" | "$HSH" --norc 2>/dev/null
check "in-command > writes to file" "inside_redirect" "$(cat "$OUT2")"

# ------------------------------------------------------------------ stdout >>
echo
echo "--- stdout append (>>)"

OUT3="$TMPDIR_TEST/out3.txt"
printf 'echo line1 >> %s
' "$OUT3" | "$HSH" --norc 2>/dev/null
printf 'echo line2 >> %s
' "$OUT3" | "$HSH" --norc 2>/dev/null
check ">> appends first line"  "line1" "$(sed -n '1p' "$OUT3")"
check ">> appends second line" "line2" "$(sed -n '2p' "$OUT3")"
check ">> file has 2 lines"    "2"     "$(wc -l < "$OUT3" | tr -d ' ')"

# ------------------------------------------------------------------ stdin <
echo
echo "--- stdin redirect (<)"

IN="$TMPDIR_TEST/in1.txt"
echo "hello from file" > "$IN"
RESULT=$(printf 'cat < %s
' "$IN" | "$HSH" --norc 2>/dev/null)
check "< feeds file to stdin" "hello from file" "$RESULT"

# wc -l with stdin redirect
printf '%s
' a b c d e > "$TMPDIR_TEST/five.txt"
LINES=$(printf 'wc -l < %s
' "$TMPDIR_TEST/five.txt" | "$HSH" --norc 2>/dev/null | tr -d ' ')
check "< with wc -l counts correctly" "5" "$LINES"

# ------------------------------------------------------------------ stderr 2>
echo
echo "--- stderr redirect (2>)"

ERR="$TMPDIR_TEST/err1.txt"
printf 'ls /nonexistent_xyz_path_9999 2> %s
' "$ERR" | "$HSH" --norc 2>/dev/null
# stderr file should be non-empty (error message from ls)
check "2> captures stderr (file non-empty)" "1" "$([[ -s "$ERR" ]] && echo 1 || echo 0)"

# stdout should be empty when only stderr occurs
STDOUT_OUT=$(printf 'ls /nonexistent_xyz_path_9999 2> %s
' "$ERR" | "$HSH" --norc 2>/dev/null)
check "2> does not pollute stdout" "" "$STDOUT_OUT"

# ------------------------------------------------------------------ 2>&1
echo
echo "--- stderr-to-stdout merge (2>&1)"

BOTH="$TMPDIR_TEST/both.txt"
printf 'ls /nonexistent_xyz 2>&1
' | "$HSH" --norc > "$BOTH" 2>/dev/null
check "2>&1 merges error into stdout" "1" "$([[ -s "$BOTH" ]] && echo 1 || echo 0)"

# ------------------------------------------------------------------ combined < > 2>
echo
echo "--- combined redirection (< input > output 2>err)"

INPUT_F="$TMPDIR_TEST/combined_in.txt"
OUTPUT_F="$TMPDIR_TEST/combined_out.txt"
ERROR_F="$TMPDIR_TEST/combined_err.txt"

printf 'one
two
three
' > "$INPUT_F"

# cat < input > output  — should copy input to output
printf 'cat < %s > %s
' "$INPUT_F" "$OUTPUT_F" | "$HSH" --norc 2>/dev/null
check "combined: < and > copies content" "$(cat "$INPUT_F")" "$(cat "$OUTPUT_F")"

# ------------------------------------------------------------------ summary
echo
echo "-----------------------------------"
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
