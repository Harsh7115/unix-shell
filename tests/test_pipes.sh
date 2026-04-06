#!/usr/bin/env bash
# test_pipes.sh — Integration tests for pipe and I/O redirection in unix-shell
#
# Usage:
#   chmod +x tests/test_pipes.sh
#   ./tests/test_pipes.sh [path/to/hsh]
#
# If no shell path is given, defaults to ./hsh (built with: make)
#
# Exit code: 0 if all tests pass, non-zero otherwise.

set -euo pipefail

HSH="${1:-./hsh}"
PASS=0
FAIL=0
TMPDIR_TESTS="$(mktemp -d)"

cleanup() { rm -rf "$TMPDIR_TESTS"; }
trap cleanup EXIT

# ---------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------

run() {
    # run_hsh CMD_STRING
    # Feeds CMD_STRING to the shell via stdin, captures stdout+stderr.
    printf '%s\n' "$1" | "$HSH" 2>&1
}

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        printf '  [PASS] %s\n' "$desc"
        PASS=$((PASS + 1))
    else
        printf '  [FAIL] %s\n' "$desc"
        printf '         expected: %q\n' "$expected"
        printf '         actual  : %q\n' "$actual"
        FAIL=$((FAIL + 1))
    fi
}

assert_contains() {
    local desc="$1" needle="$2" haystack="$3"
    if printf '%s' "$haystack" | grep -qF "$needle"; then
        printf '  [PASS] %s\n' "$desc"
        PASS=$((PASS + 1))
    else
        printf '  [FAIL] %s\n' "$desc"
        printf '         looking for: %q\n' "$needle"
        printf '         in output  : %q\n' "$haystack"
        FAIL=$((FAIL + 1))
    fi
}

assert_file_contains() {
    local desc="$1" needle="$2" file="$3"
    if grep -qF "$needle" "$file"; then
        printf '  [PASS] %s\n' "$desc"
        PASS=$((PASS + 1))
    else
        printf '  [FAIL] %s\n' "$desc"
        printf '         file %s does not contain: %q\n' "$file" "$needle"
        FAIL=$((FAIL + 1))
    fi
}

# ---------------------------------------------------------------
# Section 1: Basic single-pipe tests
# ---------------------------------------------------------------
printf '\n=== Single-pipe tests ===\n'

out=$(run 'echo hello | cat')
assert_eq "echo hello | cat" "hello" "$out"

out=$(run 'printf "a\nb\nc\n" | wc -l')
assert_eq "printf | wc -l (3 lines)" "3" "$(printf '%s' "$out" | tr -d ' ')"

out=$(run 'echo "foo bar baz" | cut -d" " -f2')
assert_eq "cut field 2 via pipe" "bar" "$out"

out=$(run 'echo "HELLO" | tr A-Z a-z')
assert_eq "tr uppercase to lowercase via pipe" "hello" "$out"

# ---------------------------------------------------------------
# Section 2: Multi-stage pipelines
# ---------------------------------------------------------------
printf '\n=== Multi-stage pipeline tests ===\n'

out=$(run 'printf "banana\napple\ncherry\n" | sort | head -1')
assert_eq "sort | head -1 gives first alphabetically" "apple" "$out"

out=$(run 'printf "1\n2\n3\n4\n5\n" | grep -v 3 | wc -l')
assert_eq "grep -v | wc -l filters one line" "4" "$(printf '%s' "$out" | tr -d ' ')"

out=$(run 'echo "the quick brown fox" | tr " " "\n" | sort | uniq | wc -l')
assert_eq "word count pipeline (4 unique words)" "4" "$(printf '%s' "$out" | tr -d ' ')"

# ---------------------------------------------------------------
# Section 3: Output redirection (> and >>)
# ---------------------------------------------------------------
printf '\n=== Output redirection tests ===\n'

OUTFILE="$TMPDIR_TESTS/out.txt"

run "echo hello_world > $OUTFILE" > /dev/null 2>&1 || true
assert_file_contains "> creates file with content" "hello_world" "$OUTFILE"

run "echo second_line >> $OUTFILE" > /dev/null 2>&1 || true
assert_file_contains ">> appends to file" "second_line" "$OUTFILE"
assert_file_contains ">> preserves original line" "hello_world" "$OUTFILE"

# Truncation test
run "echo new_content > $OUTFILE" > /dev/null 2>&1 || true
lines=$(wc -l < "$OUTFILE" | tr -d ' ')
assert_eq "> truncates existing file (1 line)" "1" "$lines"

# ---------------------------------------------------------------
# Section 4: Input redirection (<)
# ---------------------------------------------------------------
printf '\n=== Input redirection tests ===\n'

INFILE="$TMPDIR_TESTS/in.txt"
printf 'line1\nline2\nline3\n' > "$INFILE"

out=$(run "wc -l < $INFILE")
assert_eq "wc -l < file counts 3 lines" "3" "$(printf '%s' "$out" | tr -d ' ')"

out=$(run "cat < $INFILE | head -1")
assert_eq "cat < file | head -1 gives first line" "line1" "$out"

# ---------------------------------------------------------------
# Section 5: Stderr redirection (2> and 2>&1)
# ---------------------------------------------------------------
printf '\n=== Stderr redirection tests ===\n'

ERRFILE="$TMPDIR_TESTS/err.txt"

run "ls /nonexistent_path_xyz 2> $ERRFILE" > /dev/null || true
[ -s "$ERRFILE" ] && { printf '  [PASS] 2> captures stderr to file\n'; PASS=$((PASS+1)); }                   || { printf '  [FAIL] 2> did not write to error file\n'; FAIL=$((FAIL+1)); }

out=$(run 'ls /nonexistent_path_xyz 2>&1')
assert_contains "2>&1 merges stderr into stdout" "No such file" "$out"

# ---------------------------------------------------------------
# Section 6: Combined pipe + redirection
# ---------------------------------------------------------------
printf '\n=== Combined pipe + redirection tests ===\n'

COMBO="$TMPDIR_TESTS/combo.txt"
run "printf 'z\na\nm\n' | sort > $COMBO" > /dev/null 2>&1 || true
first=$(head -1 "$COMBO")
assert_eq "sort output redirected to file (first line = a)" "a" "$first"

# pipe with input redirect
WORDS="$TMPDIR_TESTS/words.txt"
printf 'dog\ncat\nbird\nelephant\n' > "$WORDS"
out=$(run "sort < $WORDS | head -2")
first_word=$(printf '%s' "$out" | head -1)
assert_eq "sort < file | head -2 (first word = bird)" "bird" "$first_word"

# ---------------------------------------------------------------
# Summary
# ---------------------------------------------------------------
printf '\n=== Results: %d passed, %d failed ===\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
