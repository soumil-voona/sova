#parser.sh
# shellcheck shell=bash
#
# parse_program FILE validates FILE and fills the global AST array with one
# node per entry. Fields within a node are separated by $AST_FS, and argument
# lists by $AST_AS, so quoted strings may safely contain commas, spaces, or '#'.
#
# Node kinds:
#   FACT <name> <args>             fact parent("Alex", "Sam")
#   RULE <name> <params>           rule grandparent(x, z):
#   GOAL <op> <name> <args>        body goal of the most recent RULE;
#                                  op is FIRST, AND, or OR
#   ASK  <name> <args>             ask grandparent("Alex", "Jamie")
#
# Terms are quoted strings ("Alex"), integers (17, -3), or variables (x).
# Rule heads may contain any term: rule likes("Sam", food):
#
# Besides predicate calls, a rule body goal can be:
#   a comparison   age >= 18     name is the operator (<, >, <=, >=, ==, !=)
#                                and args are the left and right terms
#   a negation     NOT p(x)      name is "!p"; true when p(x) can't be proved

AST_FS=$'\x1f'
AST_AS=$'\x1e'
AST=()

NAME_PATTERN='^[a-zA-Z_][a-zA-Z0-9_]*$'
NUMBER_PATTERN='^-?[0-9]+$'
TERM_REGEX='("[^"]*"|-?[a-zA-Z0-9_]+)'
COMPARISON_PATTERN="^${TERM_REGEX}[[:space:]]*(<=|>=|==|!=|<|>)[[:space:]]*${TERM_REGEX}\$"

trim() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

# Removes a '#' comment unless the '#' sits inside a quoted string.
strip_comment() {
    local line="$1"
    local in_string=0
    local i char
    for ((i = 0; i < ${#line}; i++)); do
        char="${line:$i:1}"
        if [[ "$char" == '"' ]]; then
            in_string=$((1 - in_string))
        elif [[ "$char" == "#" && "$in_string" -eq 0 ]]; then
            printf '%s' "${line:0:$i}"
            return
        fi
    done
    printf '%s' "$line"
}

is_term() {
    [[ "$1" =~ ^\"[^\"]*\"$ || "$1" =~ $NAME_PATTERN || "$1" =~ $NUMBER_PATTERN ]]
}

# canonical_term TERM -> CANONICAL: numbers in standard form (007 -> 7,
# -0 -> 0) so equal numbers match; other terms unchanged.
canonical_term() {
    local term="$1" sign=""
    if [[ "$term" =~ $NUMBER_PATTERN ]]; then
        if [[ "$term" == -* ]]; then
            sign="-"
            term="${term#-}"
        fi
        term=$((10#$term))
        [[ "$term" == "0" ]] && sign=""
        term="${sign}${term}"
    fi
    CANONICAL="$term"
}

# canonical_args TERM... -> SPLIT_RESULT with each term made canonical.
canonical_args() {
    local term
    SPLIT_RESULT=()
    for term in "$@"; do
        canonical_term "$term"
        SPLIT_RESULT+=("$CANONICAL")
    done
}

# Splits on commas outside quotes into SPLIT_RESULT. Fails on an unclosed quote.
split_args() {
    local text="$1"
    local in_string=0
    local current=""
    local i char
    SPLIT_RESULT=()
    for ((i = 0; i < ${#text}; i++)); do
        char="${text:$i:1}"
        if [[ "$char" == '"' ]]; then
            in_string=$((1 - in_string))
            current+="$char"
        elif [[ "$char" == "," && "$in_string" -eq 0 ]]; then
            SPLIT_RESULT+=("$(trim "$current")")
            current=""
        else
            current+="$char"
        fi
    done
    [[ "$in_string" -eq 0 ]] || return 1
    SPLIT_RESULT+=("$(trim "$current")")
}

join_args() {
    local IFS="$AST_AS"
    printf '%s' "$*"
}

# Parses "name(term, ...)" into CALL_NAME and CALL_ARGS (joined with $AST_AS).
parse_call() {
    local expression="$1"
    local argument
    local arguments
    [[ "$expression" == *"("*")" ]] || return 1
    CALL_NAME="$(trim "${expression%%(*}")"
    [[ "$CALL_NAME" =~ $NAME_PATTERN ]] || return 1
    arguments="${expression#*(}"
    arguments="${arguments%)}"
    [[ -n "$(trim "$arguments")" ]] || return 1
    split_args "$arguments" || return 1
    for argument in "${SPLIT_RESULT[@]}"; do
        is_term "$argument" || return 1
    done
    canonical_args "${SPLIT_RESULT[@]}"
    CALL_ARGS="$(join_args "${SPLIT_RESULT[@]}")"
}


# Parses one rule body goal (a call, a comparison, or NOT call) into
# GOAL_NAME and GOAL_ARGS. See the node kinds at the top of this file.
parse_goal() {
    local expression="$1"
    if [[ "$expression" =~ ^NOT[[:space:]]+(.+)$ ]]; then
        parse_call "${BASH_REMATCH[1]}" || return 1
        GOAL_NAME="!${CALL_NAME}"
        GOAL_ARGS="$CALL_ARGS"
        return 0
    fi
    if [[ "$expression" =~ $COMPARISON_PATTERN ]]; then
        local left="${BASH_REMATCH[1]}" op="${BASH_REMATCH[2]}" right="${BASH_REMATCH[3]}"
        is_term "$left" && is_term "$right" || return 1
        canonical_term "$left"
        left="$CANONICAL"
        canonical_term "$right"
        right="$CANONICAL"
        GOAL_NAME="$op"
        GOAL_ARGS="${left}${AST_AS}${right}"
        return 0
    fi
    parse_call "$expression" || return 1
    GOAL_NAME="$CALL_NAME"
    GOAL_ARGS="$CALL_ARGS"
}

parser_error() {
    echo "Syntax error on line $1: $2" >&2
    return 1
}

parse_program() {
    local source_file="$1"
    local line_number=0
    local line content op
    local in_rule=0
    local rule_name=""
    local goal_count=0
    local rule_signature rule_parameters parameter
    local params

    AST=()

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_number++))
        content="$(trim "$(strip_comment "$line")")"
        [[ -z "$content" ]] && continue

        if [[ "$in_rule" -eq 1 ]]; then
            if [[ "$content" =~ ^(fact|rule|ask)[[:space:]] ]]; then
                if [[ "$goal_count" -eq 0 ]]; then
                    parser_error "$line_number" "rule '$rule_name' has no body"
                    return 1
                fi
                in_rule=0
            else
                op="FIRST"
                if [[ "$content" =~ ^(AND|OR)[[:space:]]+(.+)$ ]]; then
                    op="${BASH_REMATCH[1]}"
                    content="${BASH_REMATCH[2]}"
                    if [[ "$goal_count" -eq 0 ]]; then
                        parser_error "$line_number" "rule '$rule_name' body cannot start with $op"
                        return 1
                    fi
                elif [[ "$goal_count" -gt 0 ]]; then
                    parser_error "$line_number" "expected AND or OR before goal in rule '$rule_name'"
                    return 1
                fi
                if ! parse_goal "$content"; then
                    parser_error "$line_number" "expected a predicate call, comparison, or NOT in rule '$rule_name'"
                    return 1
                fi
                AST+=("GOAL${AST_FS}${op}${AST_FS}${GOAL_NAME}${AST_FS}${GOAL_ARGS}")
                ((goal_count++))
                continue
            fi
        fi

        if [[ "$content" =~ ^fact[[:space:]]+(.+)$ ]]; then
            if ! parse_call "${BASH_REMATCH[1]}"; then
                parser_error "$line_number" "expected fact predicate and arguments"
                return 1
            fi
            AST+=("FACT${AST_FS}${CALL_NAME}${AST_FS}${CALL_ARGS}")
            continue
        fi

        if [[ "$content" =~ ^ask[[:space:]]+(.+)$ ]]; then
            if ! parse_call "${BASH_REMATCH[1]}"; then
                parser_error "$line_number" "expected query predicate and arguments"
                return 1
            fi
            AST+=("ASK${AST_FS}${CALL_NAME}${AST_FS}${CALL_ARGS}")
            continue
        fi

        if [[ "$content" =~ ^rule[[:space:]]+(.+)$ ]]; then
            rule_signature="$(trim "${BASH_REMATCH[1]}")"
            if [[ "$rule_signature" != *"):" || "$rule_signature" != *"("* ]]; then
                parser_error "$line_number" "invalid rule declaration"
                return 1
            fi
            rule_signature="${rule_signature%:}"
            rule_name="$(trim "${rule_signature%%(*}")"
            if ! [[ "$rule_name" =~ $NAME_PATTERN ]]; then
                parser_error "$line_number" "invalid rule declaration"
                return 1
            fi
            rule_parameters="${rule_signature#*(}"
            rule_parameters="${rule_parameters%)}"
            if ! split_args "$rule_parameters"; then
                parser_error "$line_number" "unclosed string in rule '$rule_name'"
                return 1
            fi
            params=("${SPLIT_RESULT[@]}")
            for parameter in "${params[@]}"; do
                if ! is_term "$parameter"; then
                    parser_error "$line_number" "invalid rule parameter '$parameter'"
                    return 1
                fi
            done
            canonical_args "${params[@]}"
            AST+=("RULE${AST_FS}${rule_name}${AST_FS}$(join_args "${SPLIT_RESULT[@]}")")
            in_rule=1
            goal_count=0
            continue
        fi

        parser_error "$line_number" "expected fact, rule, or ask declaration"
        return 1
    done < "$source_file"

    if [[ "$in_rule" -eq 1 && "$goal_count" -eq 0 ]]; then
        parser_error "$line_number" "rule '$rule_name' has no body"
        return 1
    fi
}

# Prints the AST in a readable form, one node per line.
print_ast() {
    local node
    for node in "${AST[@]}"; do
        node="${node//$AST_FS/ | }"
        printf '%s\n' "${node//$AST_AS/, }"
    done
}
