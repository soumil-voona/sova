#arith.sh
# shellcheck shell=bash
# Results are returned in globals (EX_V, PRETTY, MAPPED, OP, ...) that other
# files read, which ShellCheck can't see:
# shellcheck disable=SC2034
#
# Arithmetic expressions: + - * / %, parentheses, and unary minus, with the
# usual precedence (* / % before + -, left to right).
#
# Whole numbers use Bash arithmetic. / and % round down (floor division,
# like Python), so -7 / 2 is -4 and -7 % 2 is 1; the translations reproduce
# this exactly.
#
# Decimals (2.5, -0.75) are worked out exactly, as a whole number of
# hundredths, thousandths, ... (see dec_split), so 0.1 + 0.2 is 0.3. When
# either value is a decimal the result is one too, always written with at
# least one digit after the point (2.5 * 2 is 5.0). / then divides exactly,
# rounded to $DIVISION_PLACES decimal places, and % is what is left after
# rounding the quotient down. A decimal may have up to $DEC_MAX_DIGITS
# digits in all; a result that needs more is an error.
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
DECIMAL_PATTERN='^-?[0-9]+\.[0-9]+$'
DEC_MAX_DIGITS=18
DIVISION_PLACES=10
# 1 while translating a program that uses decimals: / then needs a helper
# that knows whether its values are whole (set by translate_to).
EX_DECIMALS=0
# In text mode: 1 if the expression just read has a decimal written in it
# (so its value is a decimal even where JavaScript can't tell, as with 3.0).
EX_ISDEC=0

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
                if [[ "${text:i:1}" == "." && "${text:i+1:1}" == [0-9] ]]; then
                    token+="."
                    i=$((i + 1))
                    while ((i < n)) && [[ "${text:i:1}" == [0-9] ]]; do
                        token+="${text:i:1}"
                        i=$((i + 1))
                    done
                    canonical_term "$token"
                    EX_TOKENS+=("$CANONICAL")
                else
                    EX_TOKENS+=("$((10#$token))")
                fi
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
    EX_ISDEC=0
    if [[ "$token" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        EX_V="$token"
        [[ "$token" == *.* ]] && EX_ISDEC=1
    elif expr_token_is_var "$token"; then
        case "$EX_MODE" in
            eval)
                walk "$token" "$EX_SUBST"
                if is_variable "$WALKED"; then
                    EX_ERROR="needs-value${AST_FS}${WALKED}"
                    return 1
                fi
                if ! [[ "$WALKED" =~ $NUMBER_PATTERN ]]; then
                    EX_ERROR="not-number${AST_FS}${token}${AST_FS}${WALKED}"
                    return 1
                fi
                if [[ "$WALKED" == *.* ]]; then
                    EX_V="$WALKED"
                else
                    number_value "$WALKED"
                    EX_V="$NUMBER_VALUE"
                fi
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
        if [[ "$EX_MODE" == "eval" && "$EX_V" == *.* ]]; then
            if [[ "$EX_V" == -* ]]; then
                EX_V="${EX_V#-}"
            elif [[ "$EX_V" != "0.0" ]]; then
                EX_V="-$EX_V"
            fi
        elif [[ "$EX_MODE" == "eval" ]]; then
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
    local left op right quotient remainder decimal right_decimal
    ex_unary || return 1
    left="$EX_V"
    decimal="$EX_ISDEC"
    while [[ "${EX_T[EX_I]}" == "*" || "${EX_T[EX_I]}" == "/" || "${EX_T[EX_I]}" == "%" ]]; do
        op="${EX_T[EX_I]}"
        EX_I=$((EX_I + 1))
        ex_unary || return 1
        right="$EX_V"
        right_decimal="$EX_ISDEC"
        if [[ "$EX_MODE" == "eval" && "$left$right" == *.* ]]; then
            if ! dec_op "$op" "$left" "$right"; then
                EX_ERROR="$DEC_ERROR"
                return 1
            fi
            left="$DEC_RESULT"
        elif [[ "$EX_MODE" == "eval" ]]; then
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
            # With decimals in the program, / depends on the values (whole
            # numbers round down, decimals don't), so it becomes divide().
            case "$EX_DECIMALS:$EX_LANG:$op" in
                1:pseudo:/)
                    left="$left / $right"
                    CODE_USES_DIVIDE=1
                    ;;
                1:javascript:/)
                    # A decimal written in the source (3.0) is known to be
                    # one, which JavaScript can't see from the value.
                    if [[ "$decimal$right_decimal" == *1* ]]; then
                        left="divide($left, $right, true)"
                    else
                        left="divide($left, $right)"
                    fi
                    CODE_USES_DIVIDE=1
                    ;;
                1:*:/)
                    left="divide($left, $right)"
                    CODE_USES_DIVIDE=1
                    ;;
                *:pseudo:/) left="$left DIV $right" ;;
                *:pseudo:%) left="$left MOD $right" ;;
                *:python:/ | *:functional:/) left="$left // $right" ;;
                *:javascript:/) left="Math.floor($left / $right)" ;;
                *:javascript:%) left="(($left % $right) + $right) % $right" ;;
                *) left="$left $op $right" ;;
            esac
        fi
        [[ "$right_decimal" -eq 1 ]] && decimal=1
    done
    EX_V="$left"
    EX_ISDEC="$decimal"
}

ex_sum() {
    local left op decimal
    ex_product || return 1
    left="$EX_V"
    decimal="$EX_ISDEC"
    while [[ "${EX_T[EX_I]}" == "+" || "${EX_T[EX_I]}" == "-" ]]; do
        op="${EX_T[EX_I]}"
        EX_I=$((EX_I + 1))
        ex_product || return 1
        if [[ "$EX_MODE" == "eval" && "$left$EX_V" == *.* ]]; then
            if ! dec_op "$op" "$left" "$EX_V"; then
                EX_ERROR="$DEC_ERROR"
                return 1
            fi
            left="$DEC_RESULT"
        elif [[ "$EX_MODE" == "eval" ]]; then
            if [[ "$op" == "+" ]]; then
                left=$((left + EX_V))
            else
                left=$((left - EX_V))
            fi
        elif [[ "$EX_MODE" == "text" ]]; then
            left="$left $op $EX_V"
        fi
        [[ "$EX_ISDEC" -eq 1 ]] && decimal=1
    done
    EX_V="$left"
    EX_ISDEC="$decimal"
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
    trim_to "$1"
    text="$TRIMMED"
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

# --- Decimals --------------------------------------------------------------
# A decimal is worked with as a whole number and a scale: 2.75 is 275 with
# scale 2 (275 hundredths). Values may mix whole numbers (scale 0) and
# decimals. Each function fails with DEC_ERROR set to "too-big" or
# "divide-by-zero".

# dec_split NUMBER -> DEC_M (the digits as a whole number, with its sign)
# and DEC_S (how many digits are after the point).
dec_split() {
    local v="$1" negative=0 whole digits fraction=""
    if [[ "$v" == -* ]]; then
        negative=1
        v="${v#-}"
    fi
    whole="${v%%.*}"
    [[ "$v" == *.* ]] && fraction="${v#*.}"
    digits="${whole}${fraction}"
    while [[ "$digits" == 0?* ]]; do
        digits="${digits#0}"
    done
    if ((${#digits} > DEC_MAX_DIGITS)); then
        DEC_ERROR="too-big"
        return 1
    fi
    DEC_M=$((10#$digits))
    ((negative)) && DEC_M=$((-DEC_M))
    DEC_S="${#fraction}"
}

# dec_scale M K -> DEC_SCALED: M * 10^K.
dec_scale() {
    local m="$1" k="$2"
    while ((k > 0)); do
        if ((m > 99999999999999999 || m < -99999999999999999)); then
            DEC_ERROR="too-big"
            return 1
        fi
        m=$((m * 10))
        k=$((k - 1))
    done
    DEC_SCALED="$m"
}

# dec_align A B -> DEC_A and DEC_B, both at scale DEC_S (the larger).
dec_align() {
    local am as bm bs
    dec_split "$1" || return 1
    am="$DEC_M" as="$DEC_S"
    dec_split "$2" || return 1
    bm="$DEC_M" bs="$DEC_S"
    if ((as < bs)); then
        dec_scale "$am" $((bs - as)) || return 1
        am="$DEC_SCALED" as="$bs"
    elif ((bs < as)); then
        dec_scale "$bm" $((as - bs)) || return 1
        bm="$DEC_SCALED"
    fi
    DEC_A="$am" DEC_B="$bm" DEC_S="$as"
}

# dec_format M S -> DEC_RESULT: M with scale S as Sova writes decimals:
# trailing zeros dropped, but always one digit after the point (5.0).
dec_format() {
    local m="$1" s="$2" sign="" digits
    while ((s > 1 && m % 10 == 0)); do
        m=$((m / 10))
        s=$((s - 1))
    done
    if ((s == 0)); then
        DEC_RESULT="${m}.0"
        return 0
    fi
    if ((m < 0)); then
        sign="-"
        m=$((-m))
    fi
    digits="$m"
    while ((${#digits} <= s)); do
        digits="0$digits"
    done
    DEC_RESULT="${sign}${digits:0:${#digits}-s}.${digits:${#digits}-s}"
    [[ "$DEC_RESULT" == "-0.0" ]] && DEC_RESULT="0.0"
    return 0
}

# dec_op OP A B -> DEC_RESULT: A OP B for + - * / %, as a decimal.
dec_op() {
    local op="$1" a="$2" b="$3" r am as
    DEC_ERROR=""
    case "$op" in
        "+" | "-")
            dec_align "$a" "$b" || return 1
            [[ "$op" == "-" ]] && DEC_B=$((-DEC_B))
            r=$((DEC_A + DEC_B))
            if ((DEC_A > 0 && DEC_B > 0 && r < 0)) || ((DEC_A < 0 && DEC_B < 0 && r >= 0)); then
                DEC_ERROR="too-big"
                return 1
            fi
            dec_format "$r" "$DEC_S"
            ;;
        "*")
            dec_split "$a" || return 1
            am="$DEC_M" as="$DEC_S"
            dec_split "$b" || return 1
            r=$((am * DEC_M))
            if ((am != 0 && r / am != DEC_M)); then
                DEC_ERROR="too-big"
                return 1
            fi
            dec_format "$r" $((as + DEC_S))
            ;;
        "/")
            # At the same scale, A / B is DEC_A / DEC_B: long division.
            dec_align "$a" "$b" || return 1
            if ((DEC_B == 0)); then
                DEC_ERROR="divide-by-zero"
                return 1
            fi
            local sign="" n="$DEC_A" d="$DEC_B" q fraction="" digit i last
            if (((n < 0) != (d < 0))); then
                sign="-"
            fi
            ((n < 0)) && n=$((-n))
            ((d < 0)) && d=$((-d))
            q=$((n / d))
            r=$((n % d))
            for ((i = 0; i <= DIVISION_PLACES; i++)); do
                if ((r > 922337203685477580)); then
                    DEC_ERROR="too-big"
                    return 1
                fi
                r=$((r * 10))
                digit=$((r / d))
                r=$((r % d))
                fraction+="$digit"
            done
            # One digit more than kept, to round half away from zero.
            last="${fraction: -1}"
            fraction="${fraction:0:DIVISION_PLACES}"
            if ((last >= 5)); then
                local carry=1 j rounded=""
                for ((j = DIVISION_PLACES - 1; j >= 0; j--)); do
                    digit=$((${fraction:j:1} + carry))
                    carry=$((digit / 10))
                    rounded="$((digit % 10))$rounded"
                done
                fraction="$rounded"
                q=$((q + carry))
            fi
            canonical_term "${sign}${q}.${fraction}"
            DEC_RESULT="$CANONICAL"
            ;;
        "%")
            dec_align "$a" "$b" || return 1
            if ((DEC_B == 0)); then
                DEC_ERROR="divide-by-zero"
                return 1
            fi
            r=$((DEC_A % DEC_B))
            if ((r != 0 && ((r < 0) != (DEC_B < 0)))); then
                r=$((r + DEC_B))
            fi
            dec_format "$r" "$DEC_S"
            ;;
    esac
}

# dec_cmp A B -> DEC_CMP: -1, 0, or 1 as A is less than, equal to, or
# greater than B (whole numbers or decimals).
dec_cmp() {
    dec_align "$1" "$2" || return 1
    if ((DEC_A < DEC_B)); then
        DEC_CMP=-1
    elif ((DEC_A > DEC_B)); then
        DEC_CMP=1
    else
        DEC_CMP=0
    fi
}
