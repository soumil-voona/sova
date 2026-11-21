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
#   EXPECT <kind> <name> <args> <answers>
#                                  a check for ./sova --check (exercises):
#                                  expect grandparent("Alex", "Jamie")       kind yes
#                                  expect NOT grandparent("Sam", "Alex")     kind no
#                                  expect parent("Ada", c) gives "Ben", "Fay"  kind gives
#                                  Answers are joined by $ANSWER_SEP, and the
#                                  values in one answer by $AST_AS. With
#                                  several variables an answer is written in
#                                  parentheses: gives ("Ada", "Ben"), ...
#   HINT <text>                    hint "Use two parent goals." (shown when
#                                  a check fails)
#
# Terms are quoted strings ("Alex"), integers (17, -3), variables (x), or
# lists ([], [1, 2], [head | tail]; see src/terms.sh).
# Rule heads may contain any term: rule likes("Sam", food):
#
# Besides predicate calls, a rule body goal can be:
#   a comparison   age >= 18     name is the operator (<, >, <=, >=, ==, !=)
#                                and args are the left and right sides
#   a calculation  m = n - 1     name is "="; gives an unknown side the other
#                                side's value, or checks the two are equal
#   Each side is a term, or an arithmetic expression stored as tokens (see
#   src/arith.sh).
#   a negation     NOT p(x)      name is "!p"; true when p(x) can't be proved
#   gathering      collect(c, parent(p, c), kids)
#                  count(parent(p, c), n)
#                  name is "collect:parent" or "count:parent"; args are the
#                  template (collect only), parent's arguments, and the
#                  result. kids is the list of c for every answer to
#                  parent(p, c); n is how many answers there are.

# shellcheck source=src/arith.sh
source "$(dirname "${BASH_SOURCE[0]}")/arith.sh"
# shellcheck source=src/terms.sh
source "$(dirname "${BASH_SOURCE[0]}")/terms.sh"

AST_FS=$'\x1f'
ANSWER_SEP=$'\x11'
AST_AS=$'\x1e'
AST=()

NAME_PATTERN='^[a-zA-Z_][a-zA-Z0-9_]*$'
NUMBER_PATTERN='^-?[0-9]+$'

# The parser runs these helpers several times per line, so they set a
# global instead of printing: "$(...)" would start a subshell each time,
# which made loading a few thousand facts take tens of seconds.

# trim_to TEXT -> TRIMMED: TEXT without leading or trailing whitespace.
trim_to() {
    TRIMMED="${1#"${1%%[![:space:]]*}"}"
    TRIMMED="${TRIMMED%"${TRIMMED##*[![:space:]]}"}"
}

# trim TEXT: prints TEXT trimmed, for callers outside the parser.
trim() {
    trim_to "$1"
    printf '%s' "$TRIMMED"
}

# strip_comment_to LINE -> STRIPPED: LINE without its '#' comment, unless
# the '#' sits inside a quoted string.
strip_comment_to() {
    local line="$1"
    local in_string=0
    local i char
    STRIPPED="$line"
    [[ "$line" == *"#"* ]] || return 0
    if [[ "$line" != *'"'* ]]; then
        STRIPPED="${line%%#*}"
        return 0
    fi
    for ((i = 0; i < ${#line}; i++)); do
        char="${line:$i:1}"
        if [[ "$char" == '"' ]]; then
            in_string=$((1 - in_string))
        elif [[ "$char" == "#" && "$in_string" -eq 0 ]]; then
            STRIPPED="${line:0:$i}"
            return 0
        fi
    done
}

strip_comment() {
    strip_comment_to "$1"
    printf '%s' "$STRIPPED"
}

# is_term TEXT: succeeds if TEXT is one whole term, and leaves it in TERM.
is_term() {
    parse_term "$1"
}

# parse_terms TEXT... -> SPLIT_RESULT: each text parsed as a term (numbers
# made canonical, lists built). Fails if any isn't a term.
parse_terms() {
    local text
    local -a terms=()
    for text in "$@"; do
        parse_term "$text" || return 1
        terms+=("$TERM")
    done
    SPLIT_RESULT=("${terms[@]}")
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

# Splits on commas outside quotes, brackets, and parentheses into
# SPLIT_RESULT. Fails on an unclosed quote.
split_args() {
    local text="$1"
    local in_string=0 depth=0
    local current=""
    local i char
    SPLIT_RESULT=()
    # Fast path: with no quotes, brackets, or parentheses, every comma
    # separates arguments, so cut at each one instead of reading every
    # character.
    if [[ "$text" != *[\"\[\(\]\)]* ]]; then
        while [[ "$text" == *,* ]]; do
            trim_to "${text%%,*}"
            SPLIT_RESULT+=("$TRIMMED")
            text="${text#*,}"
        done
        trim_to "$text"
        SPLIT_RESULT+=("$TRIMMED")
        return 0
    fi
    for ((i = 0; i < ${#text}; i++)); do
        char="${text:$i:1}"
        if [[ "$char" == '"' ]]; then
            in_string=$((1 - in_string))
            current+="$char"
        elif [[ "$in_string" -eq 0 && ( "$char" == "[" || "$char" == "(" ) ]]; then
            depth=$((depth + 1))
            current+="$char"
        elif [[ "$in_string" -eq 0 && ( "$char" == "]" || "$char" == ")" ) ]]; then
            depth=$((depth - 1))
            current+="$char"
        elif [[ "$char" == "," && "$in_string" -eq 0 && "$depth" -eq 0 ]]; then
            trim_to "$current"
            SPLIT_RESULT+=("$TRIMMED")
            current=""
        else
            current+="$char"
        fi
    done
    [[ "$in_string" -eq 0 ]] || return 1
    trim_to "$current"
    SPLIT_RESULT+=("$TRIMMED")
}

# join_args_to TERM... -> JOINED: the terms joined with $AST_AS.
join_args_to() {
    local IFS="$AST_AS"
    JOINED="$*"
}

join_args() {
    join_args_to "$@"
    printf '%s' "$JOINED"
}

# Parses "name(term, ...)" into CALL_NAME and CALL_ARGS (joined with $AST_AS).
parse_call() {
    local expression="$1"
    local arguments
    [[ "$expression" == *"("*")" ]] || return 1
    trim_to "${expression%%(*}"
    CALL_NAME="$TRIMMED"
    [[ "$CALL_NAME" =~ $NAME_PATTERN ]] || return 1
    arguments="${expression#*(}"
    arguments="${arguments%)}"
    trim_to "$arguments"
    [[ -n "$TRIMMED" ]] || return 1
    split_args "$arguments" || return 1
    parse_terms "${SPLIT_RESULT[@]}" || return 1
    join_args_to "${SPLIT_RESULT[@]}"
    CALL_ARGS="$JOINED"
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
    if parse_gather "$expression"; then
        return 0
    fi
    if find_operator "$expression"; then
        local op="$OP" left right
        parse_side "${expression:0:OP_POS}" || return 1
        left="$SIDE"
        parse_side "${expression:OP_POS + ${#op}}" || return 1
        right="$SIDE"
        GOAL_NAME="$op"
        GOAL_ARGS="${left}${AST_AS}${right}"
        return 0
    fi
    parse_call "$expression" || return 1
    GOAL_NAME="$CALL_NAME"
    GOAL_ARGS="$CALL_ARGS"
}

# parse_gather EXPRESSION: collect(template, call, result) or
# count(call, result) -> GOAL_NAME and GOAL_ARGS. Fails (so the goal is
# read as an ordinary call) if EXPRESSION isn't one of these shapes.
parse_gather() {
    local expression="$1" kind inner template result
    local -a parts
    [[ "$expression" =~ ^(collect|count)[[:space:]]*\((.*)\)$ ]] || return 1
    kind="${BASH_REMATCH[1]}"
    split_args "${BASH_REMATCH[2]}" || return 1
    parts=("${SPLIT_RESULT[@]}")
    if [[ "$kind" == "collect" ]]; then
        [[ "${#parts[@]}" -eq 3 ]] || return 1
        parse_term "${parts[0]}" || return 1
        template="$TERM"
        inner="${parts[1]}"
        parse_term "${parts[2]}" || return 1
        result="$TERM"
    else
        [[ "${#parts[@]}" -eq 2 ]] || return 1
        inner="${parts[0]}"
        parse_term "${parts[1]}" || return 1
        result="$TERM"
    fi
    parse_call "$inner" || return 1
    GOAL_NAME="${kind}:${CALL_NAME}"
    if [[ "$kind" == "collect" ]]; then
        GOAL_ARGS="${template}${AST_AS}${CALL_ARGS}${AST_AS}${result}"
    else
        GOAL_ARGS="${CALL_ARGS}${AST_AS}${result}"
    fi
}

# find_gives TEXT -> GIVES_POS: where " gives " starts, outside quotes.
find_gives() {
    local text="$1" i n="${#1}" in_string=0
    for ((i = 0; i < n; i++)); do
        if [[ "${text:i:1}" == '"' ]]; then
            in_string=$((1 - in_string))
        elif [[ "$in_string" -eq 0 && "${text:i:7}" == " gives " ]]; then
            GIVES_POS="$i"
            return 0
        fi
    done
    return 1
}

# parse_expect TEXT -> EXPECT_NODE ("kind FS name FS args FS answers"), or
# fails with EXPECT_ERROR.
parse_expect() {
    local text="$1" kind="yes" call answers_text="" answer
    local -a answers=() items values
    if [[ "$text" =~ ^NOT[[:space:]]+(.+)$ ]]; then
        kind="no"
        text="${BASH_REMATCH[1]}"
    fi
    call="$text"
    if find_gives "$text"; then
        [[ "$kind" == "no" ]] && EXPECT_ERROR="expect NOT can't have 'gives'" && return 1
        kind="gives"
        call="${text:0:GIVES_POS}"
        trim_to "${text:GIVES_POS + 7}"
        answers_text="$TRIMMED"
    fi
    trim_to "$call"
    if ! parse_call "$TRIMMED"; then
        EXPECT_ERROR="expected a predicate call after expect"
        return 1
    fi
    local name="$CALL_NAME" args="$CALL_ARGS"

    # How many variables the question has: each answer gives one value each.
    TERM_VARS=()
    split_on "$AST_AS" "$args"
    local term
    for term in "${SPLIT[@]}"; do
        term_vars "$term"
    done
    local -a vars=()
    for term in "${TERM_VARS[@]}"; do
        add_unique vars "$term"
    done

    if [[ "$kind" == "gives" ]]; then
        if [[ "${#vars[@]}" -eq 0 ]]; then
            EXPECT_ERROR="'gives' needs a question with a variable, like parent(\"Ada\", child)"
            return 1
        fi
        split_args "$answers_text" || { EXPECT_ERROR="unclosed string in the answers"; return 1; }
        items=("${SPLIT_RESULT[@]}")
        for answer in "${items[@]}"; do
            values=()
            if [[ "${#vars[@]}" -gt 1 ]]; then
                if [[ "$answer" != "("*")" ]]; then
                    EXPECT_ERROR="with ${#vars[@]} variables, write each answer in parentheses, like (\"a\", 1)"
                    return 1
                fi
                answer="${answer:1:${#answer}-2}"
                split_args "$answer" || { EXPECT_ERROR="unclosed string in the answers"; return 1; }
                values=("${SPLIT_RESULT[@]}")
            else
                values=("$answer")
            fi
            if [[ "${#values[@]}" -ne "${#vars[@]}" ]]; then
                EXPECT_ERROR="each answer needs ${#vars[@]} values (one for each of: ${vars[*]})"
                return 1
            fi
            if ! parse_terms "${values[@]}"; then
                EXPECT_ERROR="couldn't read the answer '$answer'"
                return 1
            fi
            local IFS="$AST_AS"
            answers+=("${SPLIT_RESULT[*]}")
            unset IFS
        done
        local IFS="$ANSWER_SEP"
        answers_text="${answers[*]}"
        unset IFS
    fi
    EXPECT_NODE="${kind}${AST_FS}${name}${AST_FS}${args}${AST_FS}${answers_text}"
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
        strip_comment_to "$line"
        trim_to "$STRIPPED"
        content="$TRIMMED"
        [[ -z "$content" ]] && continue

        if [[ "$in_rule" -eq 1 ]]; then
            if [[ "$content" =~ ^(fact|rule|ask|expect|hint)[[:space:]] ]]; then
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
                    parser_error "$line_number" "expected a predicate call, comparison, calculation, NOT, collect, or count in rule '$rule_name'"
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

        if [[ "$content" =~ ^hint[[:space:]]+(\".*\")$ ]]; then
            AST+=("HINT${AST_FS}${BASH_REMATCH[1]}")
            continue
        fi

        if [[ "$content" =~ ^expect[[:space:]]+(.+)$ ]]; then
            if ! parse_expect "${BASH_REMATCH[1]}"; then
                parser_error "$line_number" "$EXPECT_ERROR"
                return 1
            fi
            AST+=("EXPECT${AST_FS}${EXPECT_NODE}")
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
            trim_to "${BASH_REMATCH[1]}"
            rule_signature="$TRIMMED"
            if [[ "$rule_signature" != *"):" || "$rule_signature" != *"("* ]]; then
                parser_error "$line_number" "invalid rule declaration"
                return 1
            fi
            rule_signature="${rule_signature%:}"
            trim_to "${rule_signature%%(*}"
            rule_name="$TRIMMED"
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
            parse_terms "${params[@]}"
            join_args_to "${SPLIT_RESULT[@]}"
            AST+=("RULE${AST_FS}${rule_name}${AST_FS}${JOINED}")
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
# Lists are shown as written ([1, 2]) rather than as cell numbers.
print_ast() {
    local node field term shown out
    local -a fields terms
    for node in "${AST[@]}"; do
        split_on "$AST_FS" "$node"
        fields=("${SPLIT[@]}")
        out=""
        for field in "${fields[@]}"; do
            split_on "$AST_AS" "$field"
            terms=("${SPLIT[@]}")
            shown=""
            for term in "${terms[@]}"; do
                if is_expression "$term"; then
                    expr_pretty "$term"
                    term="$PRETTY"
                elif is_cell "$term"; then
                    term_text "$term"
                    term="$TERM_TEXT"
                fi
                shown="${shown:+${shown}, }${term}"
            done
            out="${out:+${out} | }${shown}"
        done
        printf '%s\n' "$out"
    done
}
