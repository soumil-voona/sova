#builtins.sh
# shellcheck shell=bash
# Results are returned in globals that other files read:
# shellcheck disable=SC2034
#
# Built-in predicates for text. They work like predicates defined by facts
# and rules (and a program can define its own with the same name, which
# then replaces the built-in):
#
#   concat(a, b, c)    c is a followed by b. Works in any direction where
#                      c, or both a and b, are known; with only c known it
#                      gives every way to split c.
#   text_length(t, n)  n is the number of characters in t.
#   chars(t, l)        l is the list of t's characters (["c", "a", "t"]),
#                      or t is the text made by joining the list l.
#
# Values must be text ("quoted"); anything else, or a value needed before
# it is known, is an error and makes the answer UNKNOWN.

is_text_builtin() {
    case "$1" in
        concat | text_length | chars) return 0 ;;
    esac
    return 1
}

# A built-in applies unless the program has its own facts or rules for the
# name (with the same number of arguments).
builtin_applies() {
    local name="$1" args="$2" ref ids expected
    is_text_builtin "$name" || return 1
    ref="KBF_${name}[@]"
    ids=("${!ref}")
    [[ "${#ids[@]}" -gt 0 ]] && return 1
    ref="KBA_${name}[@]"
    ids=("${!ref}")
    [[ "${#ids[@]}" -gt 0 ]] && return 1
    case "$name" in
        concat) expected=3 ;;
        *) expected=2 ;;
    esac
    arg_count "$args"
    [[ "$ARG_COUNT" -eq "$expected" ]]
}

# text_value TERM SUBST -> TEXT_STATE: "known" (TEXT is the text without
# its quotes), "unknown" (a variable with no value), or "wrong" (a value
# that isn't text; TEXT is how it reads).
text_value() {
    walk "$1" "$2"
    if is_variable "$WALKED"; then
        TEXT_STATE="unknown"
    elif [[ "$WALKED" == \"*\" ]]; then
        TEXT_STATE="known"
        TEXT="${WALKED:1:${#WALKED}-2}"
    else
        TEXT_STATE="wrong"
        term_text "$WALKED" "$2"
        TEXT="$TERM_TEXT"
    fi
}

# builtin_error GOAL_TEXT MESSAGE
builtin_error() {
    source_name "$1"
    add_unique ERRORS "'$SOURCE_NAME' $2"
}

# builtin_try A B SUBST: unify A with B, adding the result to BUILTIN_SUBSTS.
builtin_try() {
    if unify_terms "$1" "$2" "$3"; then
        BUILTIN_SUBSTS+=("$UNIFY_SUBST")
    fi
    return 0
}

# solve_text_builtin NAME ARGS SUBST -> BUILTIN_SUBSTS: one substitution
# per way the built-in can be true (none if it is false). Fails on an error.
solve_text_builtin() {
    local name="$1" args="$2" subst="$3" shown i
    local -a terms
    split_on "$AST_AS" "$args"
    terms=("${SPLIT[@]}")
    format_goal "$name" "$args"
    shown="$FORMATTED"
    BUILTIN_SUBSTS=()

    case "$name" in
        concat)
            local a_state a b_state b c_state c
            text_value "${terms[0]}" "$subst"
            a_state="$TEXT_STATE" a="$TEXT"
            text_value "${terms[1]}" "$subst"
            b_state="$TEXT_STATE" b="$TEXT"
            text_value "${terms[2]}" "$subst"
            c_state="$TEXT_STATE" c="$TEXT"
            for i in 0 1 2; do
                local state_name=("$a_state" "$b_state" "$c_state")
                if [[ "${state_name[i]}" == "wrong" ]]; then
                    text_value "${terms[i]}" "$subst"
                    builtin_error "$shown" "needs text, but $TEXT isn't text"
                    return 1
                fi
            done
            if [[ "$a_state" == "known" && "$b_state" == "known" ]]; then
                builtin_try "${terms[2]}" "\"${a}${b}\"" "$subst"
            elif [[ "$c_state" == "known" && "$a_state" == "known" ]]; then
                [[ "$c" == "$a"* ]] && builtin_try "${terms[1]}" "\"${c:${#a}}\"" "$subst"
            elif [[ "$c_state" == "known" && "$b_state" == "known" ]]; then
                [[ "$c" == *"$b" ]] && builtin_try "${terms[0]}" "\"${c:0:${#c}-${#b}}\"" "$subst"
            elif [[ "$c_state" == "known" ]]; then
                for ((i = 0; i <= ${#c}; i++)); do
                    if unify_terms "${terms[0]}" "\"${c:0:i}\"" "$subst" &&
                        unify_terms "${terms[1]}" "\"${c:i}\"" "$UNIFY_SUBST"; then
                        BUILTIN_SUBSTS+=("$UNIFY_SUBST")
                    fi
                done
            else
                builtin_error "$shown" "needs the whole text, or both parts, to be known first"
                return 1
            fi
            ;;
        text_length)
            text_value "${terms[0]}" "$subst"
            case "$TEXT_STATE" in
                known) builtin_try "${terms[1]}" "${#TEXT}" "$subst" ;;
                wrong)
                    builtin_error "$shown" "needs text, but $TEXT isn't text"
                    return 1
                    ;;
                *)
                    builtin_error "$shown" "needs the text to be known first"
                    return 1
                    ;;
            esac
            ;;
        chars)
            text_value "${terms[0]}" "$subst"
            if [[ "$TEXT_STATE" == "known" ]]; then
                local list="[]" text="$TEXT"
                for ((i = ${#text} - 1; i >= 0; i--)); do
                    new_cell "\"${text:i:1}\"" "$list"
                    list="$NEW_CELL"
                done
                builtin_try "${terms[1]}" "$list" "$subst"
            elif [[ "$TEXT_STATE" == "wrong" ]]; then
                builtin_error "$shown" "needs text, but $TEXT isn't text"
                return 1
            else
                # Join a known list of characters.
                if ! term_is_ground "${terms[1]}" "$subst"; then
                    builtin_error "$shown" "needs the text or the list to be known first"
                    return 1
                fi
                local item joined=""
                walk "${terms[1]}" "$subst"
                item="$WALKED"
                while is_cell "$item"; do
                    text_value "${CELL_HEAD[${item#@}]}" "$subst"
                    if [[ "$TEXT_STATE" != "known" ]]; then
                        builtin_error "$shown" "needs a list of text, but $TEXT isn't text"
                        return 1
                    fi
                    joined+="$TEXT"
                    walk "${CELL_TAIL[${item#@}]}" "$subst"
                    item="$WALKED"
                done
                if [[ "$item" != "[]" ]]; then
                    term_text "${terms[1]}" "$subst"
                    builtin_error "$shown" "needs a list, but $TERM_TEXT isn't a list"
                    return 1
                fi
                builtin_try "${terms[0]}" "\"$joined\"" "$subst"
            fi
            ;;
    esac

    return 0
}
