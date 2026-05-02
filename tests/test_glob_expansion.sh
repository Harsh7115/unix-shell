#!/usr/bin/env bash
# test_glob_expansion.sh -- test suite for glob / wildcard expansion in ush
#
# Covers:
#   *   -- match any sequence of characters (excluding /)
#   ?   -- match exactly one character
#   [...] -- character class / range
#   ~   -- tilde home-directory expansion
#
# Exit codes:
#   0  all tests passed
#   1  one or more tests failed

set -euo pipefail

USH="${USH:-./ush}"        # path to the shell binary under test
PASS=0
FAIL=0
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

# ------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------

pass() { PASS=$((PASS + 1)); printf "  PASS  %s\n" "$1"; }
fail() { FAIL=$((FAIL + 1)); printf "  FAIL  %s  (expected: %s  got: %s)\n" "$1" "$2" "$3"; }

run_ush() {
    "$USH" -c "$1" 2>/dev/null
}

# Populate a scratch directory with known files
setup_tree() {
    mkdir -p "$TMPDIR/src" "$TMPDIR/include" "$TMPDIR/build"
    touch "$TMPDIR/src/main.c"
    touch "$TMPDIR/src/util.c"
    touch "$TMPDIR/src/parser.c"
    touch "$TMPDIR/include/util.h"
    touch "$TMPDIR/include/parser.h"
    touch "$TMPDIR/build/main.o"
    touch "$TMPDIR/build/util.o"
    touch "$TMPDIR/README.md"
    touch "$TMPDIR/Makefile"
    touch "$TMPDIR/a1"
    touch "$TMPDIR/a2"
    touch "$TMPDIR/b1"
}
setup_tree

# ------------------------------------------------------------------
# Test group 1 -- star glob (*)
# ------------------------------------------------------------------

echo "=== Star glob (*) ==="

result=$(run_ush "echo $TMPDIR/src/*.c" | tr ' ' '\n' | sort | xargs -I{} basename {})
expected=$(printf "main.c\nparser.c\nutil.c")
if [ "$result" = "$expected" ]; then
    pass "src/*.c matches all C source files"
else
    fail "src/*.c matches all C source files" "$expected" "$result"
fi

result=$(run_ush "echo $TMPDIR/include/*.h" | tr ' ' '\n' | sort | xargs -I{} basename {})
expected=$(printf "parser.h\nutil.h")
if [ "$result" = "$expected" ]; then
    pass "include/*.h matches all header files"
else
    fail "include/*.h matches all header files" "$expected" "$result"
fi

# Star with no match returns literal pattern (POSIX)
result=$(run_ush "echo $TMPDIR/src/*.z")
if echo "$result" | grep -q '[*]'; then
    pass "no-match glob returns literal pattern"
else
    fail "no-match glob returns literal pattern" "*literal*" "$result"
fi

# ------------------------------------------------------------------
# Test group 2 -- question mark glob (?)
# ------------------------------------------------------------------

echo "=== Question-mark glob (?) ==="

result=$(run_ush "echo $TMPDIR/a?" | tr ' ' '\n' | sort | xargs -I{} basename {})
expected=$(printf "a1\na2")
if [ "$result" = "$expected" ]; then
    pass "a? matches a1 and a2"
else
    fail "a? matches a1 and a2" "$expected" "$result"
fi

result=$(run_ush "echo $TMPDIR/b?" | tr ' ' '\n' | sort | xargs -I{} basename {})
expected="b1"
if [ "$result" = "$expected" ]; then
    pass "b? matches only b1"
else
    fail "b? matches only b1" "$expected" "$result"
fi

# ------------------------------------------------------------------
# Test group 3 -- character class / range ([...])
# ------------------------------------------------------------------

echo "=== Character class glob ([...]) ==="

result=$(run_ush "echo $TMPDIR/[ab]1" | tr ' ' '\n' | sort | xargs -I{} basename {})
expected=$(printf "a1\nb1")
if [ "$result" = "$expected" ]; then
    pass "[ab]1 matches a1 and b1"
else
    fail "[ab]1 matches a1 and b1" "$expected" "$result"
fi

result=$(run_ush "echo $TMPDIR/[a-b]2" | tr ' ' '\n' | sort | xargs -I{} basename {})
expected="a2"
if [ "$result" = "$expected" ]; then
    pass "[a-b]2 matches a2 only (b2 missing)"
else
    fail "[a-b]2 matches a2 only (b2 missing)" "$expected" "$result"
fi

result=$(run_ush "echo $TMPDIR/[!b]1" | tr ' ' '\n' | sort | xargs -I{} basename {})
expected="a1"
if [ "$result" = "$expected" ]; then
    pass "[!b]1 matches a1 via negated class"
else
    fail "[!b]1 matches a1 via negated class" "$expected" "$result"
fi

# ------------------------------------------------------------------
# Test group 4 -- tilde expansion
# ------------------------------------------------------------------

echo "=== Tilde expansion (~) ==="

home_via_ush=$(run_ush 'echo ~')
if [ "$home_via_ush" = "$HOME" ]; then
    pass "~ expands to HOME"
else
    fail "~ expands to HOME" "$HOME" "$home_via_ush"
fi

path_via_ush=$(run_ush 'echo ~/testdir')
expected_path="$HOME/testdir"
if [ "$path_via_ush" = "$expected_path" ]; then
    pass "~/testdir expands to $HOME/testdir"
else
    fail "~/testdir expands to $HOME/testdir" "$expected_path" "$path_via_ush"
fi

# ------------------------------------------------------------------
# Test group 5 -- glob in command arguments
# ------------------------------------------------------------------

echo "=== Glob in ls argument ==="

count=$(run_ush "ls $TMPDIR/src/*.c" | wc -l | tr -d ' ')
if [ "$count" = "3" ]; then
    pass "ls src/*.c lists 3 files"
else
    fail "ls src/*.c lists 3 files" "3" "$count"
fi

count=$(run_ush "ls $TMPDIR/build/*.o" | wc -l | tr -d ' ')
if [ "$count" = "2" ]; then
    pass "ls build/*.o lists 2 files"
else
    fail "ls build/*.o lists 2 files" "2" "$count"
fi

# ------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -eq 0 ]; then
    echo "All glob expansion tests passed."
    exit 0
else
    echo "Some glob expansion tests FAILED."
    exit 1
fi
