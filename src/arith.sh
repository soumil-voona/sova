#arith.sh
# shellcheck shell=bash
# Results are returned in globals (EX_V, PRETTY, MAPPED, OP, ...) that other
# files read, which ShellCheck can't see:
# shellcheck disable=SC2034
#
# Arithmetic expressions: + - * / %, parentheses, and unary minus, with the
# usual precedence (* / % before + -, left to right). Values are whole
# numbers. / and % round down (floor division, like Python), so -7 / 2 is -4
# and -7 % 2 is 1; the translations reproduce this exactly.
#
# A side of a comparison or = that is more than a single term is stored as
# its tokens joined by $EXPR_SEP ("n", "-", "1"), so variables inside it can
# be renamed, filled in, and translated one token at a time.
#
# One recursive-descent parser does three jobs, chosen by EX_MODE:
#   check  validate the syntax (used by the parser)
#   eval   compute the value, looking variables up in EX_SUBST
#   text   write the expression in a target language (used by translations)
#
#   sum     := product (("+" | "-") product)*
#   product := unary (("*" | "/" | "%") unary)*
#   unary   := "-" unary | atom
#   atom    := number | variable | "(" sum ")"

EXPR_SEP=$'\x04'

EX_T=()
EX_I=0
EX_V=""
EX_MODE="check"
EX_SUBST=""
EX_ERROR=""
EX_LANG="pseudo"

is_expression() {
    [[ "$1" == *"$EXPR_SEP"* ]]
}

# A token that is a variable name (operators and numbers aren't).
expr_token_is_var() {
    [[ "$1" == [a-zA-Z_]* ]]
}

# expr_tokenize TEXT -> EX_TOKENS. Fails on a character that can't appear
# in an expression.
expr_tokenize() {
    local text="$1" i=0 n="${#1}" c token
    EX_TOKENS=()
    while ((i < n)); do
        c="${text:i:1}"
        case "$c" in
            [[:space:]])
                i=$((i + 1))
                ;;
            [0-9])
                token=""
                while ((i < n)) && [[ "${text:i:1}" == [0-9] ]]; do
                    token+="${text:i:1}"
                    i=$((i + 1))
                done
                EX_TOKENS+=("$((10#$token))")
                ;;
            [a-zA-Z_])
                token=""
                while ((i < n)) && [[ "${text:i:1}" == [a-zA-Z0-9_] ]]; do
                    token+="${text:i:1}"
                    i=$((i + 1))
                done
                EX_TOKENS+=("$token")
                ;;
            "+" | "-" | "*" | "/" | "%" | "(" | ")")
                EX_TOKENS+=("$c")
                i=$((i + 1))
                ;;
            *)
                return 1
                ;;
        esac
    done
    [[ "${#EX_TOKENS[@]}" -gt 0 ]]
}

ex_atom() {
    local token="${EX_T[EX_I]}"
    if [[ "$token" == "(" ]]; then
        EX_I=$((EX_I + 1))
        ex_sum || return 1
        [[ "${EX_T[EX_I]}" == ")" ]] || return 1
        EX_I=$((EX_I + 1))
        [[ "$EX_MODE" == "text" ]] && EX_V="($EX_V)"
        return 0
    fi
    if [[ "$token" =~ ^[0-9]+$ ]]; then
        EX_V="$token"
    elif expr_token_is_var "$token"; then
        case "$EX_MODE" in
            eval)
                walk "$token" "$EX_SUBST"
                if is_variable "$WALKED"; then
                    EX_ERROR="needs-value${AST_FS}${WALKED}"
                    return 1
                fi
                if ! [[ "$WALKED" =~ ^-?[0-9]+$ ]]; then
                    EX_ERROR="not-number${AST_FS}${token}${AST_FS}${WALKED}"
                    return 1
                fi
                number_value "$WALKED"
                EX_V="$NUMBER_VALUE"
                ;;
            text)
                pseudo_disp "$token"
                EX_V="$DISP"
                ;;
            *)
                EX_V="$token"
                ;;
        esac
    else
        return 1
    fi
    EX_I=$((EX_I + 1))
}

ex_unary() {
    if [[ "${EX_T[EX_I]}" == "-" ]]; then
        EX_I=$((EX_I + 1))
        ex_unary || return 1
        if [[ "$EX_MODE" == "eval" ]]; then
            EX_V=$((-EX_V))
        elif [[ "$EX_V" == -* ]]; then
            EX_V="-($EX_V)"
        else
            EX_V="-$EX_V"
        fi
        return 0
    fi
    ex_atom
}

ex_product() {
    local left op right quotient remainder
    ex_unary || return 1
    left="$EX_V"
    while [[ "${EX_T[EX_I]}" == "*" || "${EX_T[EX_I]}" == "/" || "${EX_T[EX_I]}" == "%" ]]; do
        op="${EX_T[EX_I]}"
        EX_I=$((EX_I + 1))
        ex_unary || return 1
        right="$EX_V"
        if [[ "$EX_MODE" == "eval" ]]; then
            if [[ "$op" != "*" && "$right" -eq 0 ]]; then
                EX_ERROR="divide-by-zero"
                return 1
            fi
            case "$op" in
                "*")
                    left=$((left * right))
                    ;;
                "/")
                    quotient=$((left / right))
                    if ((left % right != 0 && ((left < 0) != (right < 0)))); then
                        quotient=$((quotient - 1))
                    fi
                    left="$quotient"
                    ;;
                "%")
                    remainder=$((left % right))
                    if ((remainder != 0 && ((remainder < 0) != (right < 0)))); then
                        remainder=$((remainder + right))
                    fi
                    left="$remainder"
                    ;;
            esac
        elif [[ "$EX_MODE" == "text" ]]; then
            case "$EX_LANG:$op" in
                pseudo:/) left="$left DIV $right" ;;
                pseudo:%) left="$left MOD $right" ;;
                python:/ | functional:/) left="$left // $right" ;;
                javascript:/) left="Math.floor($left / $right)" ;;
                javascript:%) left="(($left % $right) + $right) % $right" ;;
                *) left="$left $op $right" ;;
            esac
        fi
    done
    EX_V="$left"
}

ex_sum() {
    local left op
    ex_product || return 1
    left="$EX_V"
    while [[ "${EX_T[EX_I]}" == "+" || "${EX_T[EX_I]}" == "-" ]]; do
        op="${EX_T[EX_I]}"
        EX_I=$((EX_I + 1))
        ex_product || return 1
        if [[ "$EX_MODE" == "eval" ]]; then
            if [[ "$op" == "+" ]]; then
                left=$((left + EX_V))
            else
                left=$((left - EX_V))
            fi
        elif [[ "$EX_MODE" == "text" ]]; then
            left="$left $op $EX_V"
        fi
    done
    EX_V="$left"
}

# expr_run MODE EXPR: runs the parser over EXPR (tokens joined by
# $EXPR_SEP) -> EX_V. Fails on bad syntax, or in eval mode on an error
# described by EX_ERROR.
expr_run() {
    EX_MODE="$1"
    EX_ERROR=""
    split_tokens "$2"
    EX_T=("${EX_TOKENS[@]}")
    EX_I=0
    ex_sum || return 1
    [[ "$EX_I" -eq "${#EX_T[@]}" ]]
}

# split_tokens EXPR -> EX_TOKENS
split_tokens() {
    local text="$1"
    EX_TOKENS=()
    while [[ "$text" == *"$EXPR_SEP"* ]]; do
        EX_TOKENS+=("${text%%"$EXPR_SEP"*}")
        text="${text#*"$EXPR_SEP"}"
    done
    EX_TOKENS+=("$text")
}

# join_tokens TOKEN... -> JOINED_TOKENS (joined by $EXPR_SEP)
join_tokens() {
    local IFS="$EXPR_SEP"
    JOINED_TOKENS="$*"
}

# expr_pretty EXPR -> PRETTY: how an expression reads in Sova source,
# e.g. "(n - 1) * 2" or "-x". Tokens are separated by spaces, except after
# "(", before ")", and after a unary minus.
expr_pretty() {
    local token out="" previous="" glue=1
    split_tokens "$1"
    for token in "${EX_TOKENS[@]}"; do
        if [[ "$glue" -eq 1 || "$token" == ")" ]]; then
            out+="$token"
        else
            out+=" $token"
        fi
        glue=0
        [[ "$token" == "(" ]] && glue=1
        if [[ "$token" == "-" ]]; then
            case "$previous" in
                "" | "+" | "-" | "*" | "/" | "%" | "(") glue=1 ;;
            esac
        fi
        previous="$token"
    done
    PRETTY="$out"
}

# expr_vars EXPR -> EXPR_VARS: the variables in an expression, in order.
expr_vars() {
    local token
    EXPR_VARS=()
    split_tokens "$1"
    for token in "${EX_TOKENS[@]}"; do
        expr_token_is_var "$token" && EXPR_VARS+=("$token")
    done
    return 0
}

# expr_map EXPR FUNCTION -> MAPPED: EXPR with FUNCTION applied to each
# variable token (FUNCTION reads $1 and sets MAPPED_TOKEN).
expr_map() {
    local token
    local -a out=()
    split_tokens "$1"
    local -a tokens=("${EX_TOKENS[@]}")
    for token in "${tokens[@]}"; do
        if expr_token_is_var "$token"; then
            "$2" "$token"
            token="$MAPPED_TOKEN"
        fi
        out+=("$token")
    done
    join_tokens "${out[@]}"
    MAPPED="$JOINED_TOKENS"
}

# parse_side TEXT -> SIDE: one side of a comparison or =, either a single
# term (canonical) or an expression (tokens joined by $EXPR_SEP).
parse_side() {
    local text
    text="$(trim "$1")"
    [[ -n "$text" ]] || return 1
    if is_term "$text"; then
        SIDE="$TERM"
        return 0
    fi
    expr_tokenize "$text" || return 1
    join_tokens "${EX_TOKENS[@]}"
    SIDE="$JOINED_TOKENS"
    expr_run check "$SIDE"
}

# find_operator TEXT -> OP and OP_POS: the first comparison or = operator
# outside quoted strings. Fails if there is none.
find_operator() {
    local text="$1" i n="${#1}" in_string=0 c two
    for ((i = 0; i < n; i++)); do
        c="${text:i:1}"
        if [[ "$c" == '"' ]]; then
            in_string=$((1 - in_string))
            continue
        fi
        [[ "$in_string" -eq 1 ]] && continue
        two="${text:i:2}"
        case "$two" in
            "<=" | ">=" | "==" | "!=")
                OP="$two"
                OP_POS="$i"
                return 0
                ;;
        esac
        case "$c" in
            "<" | ">" | "=")
                OP="$c"
                OP_POS="$i"
                return 0
                ;;
        esac
    done
    return 1
}
