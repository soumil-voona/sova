
#!/usr/bin/env bash

source ./src/parser.sh

PASS=0
FAIL=0

run_test() {
    local name="$1"
    local input="$2"
    local expected="$3"

    local temp_file
    temp_file=$(mktemp)
    printf '%s\n' "$input" > "$temp_file"

    if parse_program "$temp_file" >/dev/null 2>&1; then
        actual="PASS"
    else
        actual="FAIL"
    fi

    if [[ "$actual" == "$expected" ]]; then
        echo "[PASS] $name"
        ((PASS++))
    else
        echo "[FAIL] $name (expected $expected, got $actual)"
        ((FAIL++))
    fi

    rm -f "$temp_file"
}

# Tests go here
run_test "Valid fact" \
    'fact parent("Alex", "Sam")' \
    "PASS"

run_test "Valid query" \
    'ask parent(x, "Sam")' \
    "PASS"

run_test "Missing arguments" \
    'fact parent()' \
    "FAIL"

run_test "Invalid predicate name" \
    'fact 123("Alex")' \
    "FAIL"

run_test "Unclosed string" \
    'fact parent("Alex, "Sam")' \
    "FAIL"

run_test "Missing rule body" \
    'rule ancestor(x, y):' \
    "FAIL"

run_test "Valid AND rule" \
    $'rule grandparent(x, z):\n    parent(x, y)\n    AND parent(y, z)' \
    "PASS"

run_test "Valid OR rule" \
    $'rule sibling(x, y):\n    parent(x, z)\n    OR parent(y, z)' \
    "PASS"

run_test "Rule starts with AND" \
    $'rule ancestor(x, y):\n    AND parent(x, y)' \
    "FAIL"

run_test "Missing AND or OR" \
    $'rule ancestor(x, y):\n    parent(x, z)\n    parent(z, y)' \
    "FAIL"

run_test "Invalid rule parameter" \
    'rule ancestor(1x, y):' \
    "FAIL"

run_test "Hash inside string" \
    'fact tag("Alex#1")' \
    "PASS"

run_ast_test() {
    local temp_file
    temp_file=$(mktemp)

    cat > "$temp_file" <<'EOF'
fact parent("Alex", "Sam")

rule grandparent(x, z):
    parent(x, y)
    AND parent(y, z)
EOF

    AST=()
    if parse_program "$temp_file" >/dev/null 2>&1; then
        local facts=0 rules=0 goals=0 and_goals=0
        local node kind rest op

        for node in "${AST[@]}"; do
            kind="${node%%"$AST_FS"*}"
            rest="${node#*"$AST_FS"}"

            case "$kind" in
                FACT) ((facts++)) ;;
                RULE) ((rules++)) ;;
                GOAL)
                    ((goals++))
                    op="${rest%%"$AST_FS"*}"
                    [[ "$op" == "AND" ]] && ((and_goals++))
                    ;;
            esac
        done

        if [[ "$facts" -eq 1 &&
              "$rules" -eq 1 &&
              "$goals" -eq 2 &&
              "$and_goals" -eq 1 ]]; then
            echo "[PASS] AST structure"
            ((PASS++))
        else
            echo "[FAIL] AST structure (facts=$facts rules=$rules goals=$goals AND=$and_goals)"
            ((FAIL++))
        fi
    else
        echo "[FAIL] AST structure (parsing failed)"
        ((FAIL++))
    fi

    rm -f "$temp_file"
}

run_ast_test

echo
echo "Results: $PASS passed, $FAIL failed"

[[ "$FAIL" -eq 0 ]]
