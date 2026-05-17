#!/bin/sh
# Unit tests for validation functions in amneziawg.sh

validate_uint() {
    local input="$1"
    echo "$input" | grep -qE '^[0-9]+$' || return 1
    [ "$input" -le 4294967295 ] 2>/dev/null || return 1
    return 0
}

validate_int() {
    local input="$1"
    echo "$input" | grep -qE '^-?[0-9]+$' || return 1
    [ "$input" -ge -2147483648 ] 2>/dev/null && [ "$input" -le 2147483647 ] 2>/dev/null || return 1
    return 0
}

validate_uint_range() {
    local input="$1"
    if echo "$input" | grep -qE '^[0-9]+-[0-9]+$'; then
        local lower="${input%-*}"
        local upper="${input#*-}"
        [ "$lower" -le "$upper" ] 2>/dev/null || return 1
        [ "$upper" -le 4294967295 ] 2>/dev/null || return 1
        return 0
    fi
    validate_uint "$input"
}

test_func() {
    local func="$1"
    local val="$2"
    local expected="$3"
    if $func "$val"; then
        actual="valid"
    else
        actual="invalid"
    fi

    if [ "$actual" = "$expected" ]; then
        echo "PASS: $func('$val') is $actual"
    else
        echo "FAIL: $func('$val') expected $expected, got $actual"
        exit 1
    fi
}

echo "Testing validate_uint..."
test_func validate_uint "123" "valid"
test_func validate_uint "0" "valid"
test_func validate_uint "4294967295" "valid"
test_func validate_uint "4294967296" "invalid"
test_func validate_uint "100-200" "invalid"
test_func validate_uint "abc" "invalid"

echo "Testing validate_int..."
test_func validate_int "123" "valid"
test_func validate_int "-123" "valid"
test_func validate_int "0" "valid"
test_func validate_int "2147483647" "valid"
test_func validate_int "-2147483648" "valid"
test_func validate_int "2147483648" "invalid"
test_func validate_int "-2147483649" "invalid"
test_func validate_int "100-200" "invalid"

echo "Testing validate_uint_range..."
test_func validate_uint_range "123" "valid"
test_func validate_uint_range "100-200" "valid"
test_func validate_uint_range "200-100" "invalid"
test_func validate_uint_range "0-4294967295" "valid"
test_func validate_uint_range "0-4294967296" "invalid"
test_func validate_uint_range "abc" "invalid"

echo "All tests passed!"
