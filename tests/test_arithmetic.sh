#!/usr/bin/env bash
# tests/test_arithmetic.sh
#
# Test suite for arithmetic expansion: $(( expr ))
#
# Covers: basic operators, precedence, unary ops, variables,
# nested expansions, assignment-in-arithmetic, and edge cases.
#
# Run:  bash tests/test_arithmetic.sh [path/to/shell]

SHELL_UNDER_TEST="${1:-./msh}"
PASS=0
FAIL=0

check() {
    local desc="$1" cmd="$2" expected="$3"
    local actual
    actual=$("$SHELL_UNDER_TEST" -c "$cmd" 2>&1) || true
    if [ "$actual" = "$expected" ]; then
        PASS=$((PASS + 1))
        printf "  PASS  %s\n" "$desc"
    else
        FAIL=$((FAIL + 1))
        printf "  FAIL  %s\n" "$desc"
        printf "        expected: %s\n" "$expected"
        printf "        actual:   %s\n" "$actual"
    fi
}

echo "=== Arithmetic Expansion Tests ==="
echo "    shell: $SHELL_UNDER_TEST"
echo

# ---- Basic four operations
echo "-- Basic operations"
check 'addition'           'echo $((3 + 4))'        '7'
check 'subtraction'        'echo $((10 - 3))'       '7'
check 'multiplication'     'echo $((3 * 4))'        '12'
check 'integer division'   'echo $((15 / 4))'       '3'
check 'modulo'             'echo $((17 % 5))'       '2'

# ---- Unary operators
echo "-- Unary operators"
check 'unary minus'        'echo $((-7))'           '-7'
check 'unary plus'         'echo $((+5))'           '5'
check 'bitwise NOT'        'echo $((~0))'           '-1'
check 'logical NOT true'   'echo $((! 0))'          '1'
check 'logical NOT false'  'echo $((! 1))'          '0'

# ---- Operator precedence
echo "-- Operator precedence"
check 'mul before add'     'echo $((2 + 3 * 4))'    '14'
check 'parens override'    'echo $(((2 + 3) * 4))'  '20'
check 'div before sub'     'echo $((10 - 8 / 2))'   '6'
check 'left-to-right div'  'echo $((12 / 4 / 3))'   '1'

# ---- Bitwise operators
echo "-- Bitwise operators"
check 'bitwise AND'        'echo $((15 & 9))'       '9'
check 'bitwise OR'         'echo $((12 | 3))'       '15'
check 'bitwise XOR'        'echo $((15 ^ 9))'       '6'
check 'left shift'         'echo $((1 << 4))'       '16'
check 'right shift'        'echo $((256 >> 3))'     '32'

# ---- Comparison and logical operators
echo "-- Comparison and logical operators"
check 'less than true'     'echo $((3 < 5))'        '1'
check 'less than false'    'echo $((5 < 3))'        '0'
check 'greater than'       'echo $((7 > 2))'        '1'
check 'equal'              'echo $((4 == 4))'       '1'
check 'not equal'          'echo $((4 != 5))'       '1'
check 'logical AND'        'echo $((1 && 1))'       '1'
check 'logical AND short'  'echo $((0 && 1))'       '0'
check 'logical OR'         'echo $((0 || 1))'       '1'
check 'ternary true'       'echo $((1 ? 42 : 99))'  '42'
check 'ternary false'      'echo $((0 ? 42 : 99))'  '99'

# ---- Variables
echo "-- Variables in arithmetic"
check 'simple var'         'x=7; echo $((x * 3))'  '21'
check 'two vars'           'a=5; b=3; echo $((a+b))' '8'
check 'undefined is zero'  'echo $((undef + 1))'   '1'

# ---- Assignment operators
echo "-- Assignment operators"
check '+= operator'        'x=10; x=$((x + 5)); echo $x'  '15'
check '-= operator'        'x=10; x=$((x - 3)); echo $x'  '7'
check '*= operator'        'x=4;  x=$((x * 3)); echo $x'  '12'
check '/= operator'        'x=12; x=$((x / 4)); echo $x'  '3'

# ---- Nested expansions
echo "-- Nested expansions"
check 'nested arith'       'echo $(( $((2+3)) * 2 ))'  '10'
check 'arith in string'    'echo "ans=$(( 6 * 7 ))"'   'ans=42'

# ---- Edge cases
echo "-- Edge cases"
check 'zero literal'       'echo $((0))'             '0'
check 'negative result'    'echo $((3 - 10))'        '-7'
check 'large number'       'echo $((1000 * 1000))'   '1000000'
check 'hex literal'        'echo $((0x1F))'          '31'
check 'octal literal'      'echo $((010))'           '8'

# ---- Summary
echo
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
