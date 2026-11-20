#terms.sh
# shellcheck shell=bash
# Results are returned in globals (TERM, TERM_TEXT, ...) that other files
# read, which ShellCheck can't see:
# shellcheck disable=SC2034
#
# Lists. [] is the empty list; [1, 2, 3] and [head | tail] are built from
# cells, each holding a first item (head) and the rest of the list (tail):
#   [1, 2] is the cell (1, the cell (2, []))
# Cells live in the CELL_HEAD and CELL_TAIL arrays and are written as @N,
# where N is the index. They never change once made, so backtracking needs
# no undo: a branch that fails simply stops using the cells it made.
# CELL_GROUND[N] is 1 if the list has no variables anywhere inside it.
#
# A term is then: a quoted string, a number, a variable (a name that starts
# with a letter or _), [] or a cell reference @N.

CELL_HEAD=()
CELL_TAIL=()
CELL_GROUND=()

# new_cell HEAD TAIL -> NEW_CELL ("@N")
new_cell() {
    local index="${#CELL_HEAD[@]}" ground=1
    CELL_HEAD[index]="$1"
    CELL_TAIL[index]="$2"
    term_has_no_variables "$1" || ground=0
    term_has_no_variables "$2" || ground=0
    CELL_GROUND[index]="$ground"
    NEW_CELL="@$index"
}

is_cell() {
    [[ "$1" == @* ]]
}

# True if TERM (not looked up in any substitution) contains no variables.
term_has_no_variables() {
    if is_variable "$1"; then
        return 1
    elif is_cell "$1"; then
        [[ "${CELL_GROUND[${1#@}]}" -eq 1 ]]
    fi
    return 0
}

# --- Parsing ------------------------------------------------------------

# parse_term TEXT -> TERM: a whole term, or fails.
parse_term() {
    PT_TEXT="$1"
    PT_POS=0
    pt_skip_space
    pt_term || return 1
    pt_skip_space
    [[ "$PT_POS" -eq "${#PT_TEXT}" ]]
}

pt_skip_space() {
    while [[ "${PT_TEXT:PT_POS:1}" == [[:space:]] ]]; do
        PT_POS=$((PT_POS + 1))
    done
}

pt_term() {
    local c="${PT_TEXT:PT_POS:1}" rest token
    rest="${PT_TEXT:PT_POS}"
    if [[ "$c" == "[" ]]; then
        pt_list
        return
    fi
    if [[ "$c" == '"' ]]; then
        token="${rest:1}"
        [[ "$token" == *'"'* ]] || return 1
        token="\"${token%%\"*}\""
    elif [[ "$rest" =~ ^(-?[0-9]+) ]]; then
        token="${BASH_REMATCH[1]}"
        canonical_term "$token"
        PT_POS=$((PT_POS + ${#token}))
        TERM="$CANONICAL"
        return 0
    elif [[ "$rest" =~ ^([a-zA-Z_][a-zA-Z0-9_]*) ]]; then
        token="${BASH_REMATCH[1]}"
    else
        return 1
    fi
    PT_POS=$((PT_POS + ${#token}))
    TERM="$token"
}

# [] | "[" term ("," term)* ("|" term)? "]"
pt_list() {
    local -a items=()
    local tail="[]" i
    PT_POS=$((PT_POS + 1))
    pt_skip_space
    if [[ "${PT_TEXT:PT_POS:1}" == "]" ]]; then
        PT_POS=$((PT_POS + 1))
        TERM="[]"
        return 0
    fi
    while true; do
        pt_term || return 1
        items+=("$TERM")
        pt_skip_space
        case "${PT_TEXT:PT_POS:1}" in
            ",")
                PT_POS=$((PT_POS + 1))
                pt_skip_space
                ;;
            "|")
                PT_POS=$((PT_POS + 1))
                pt_skip_space
                pt_term || return 1
                tail="$TERM"
                pt_skip_space
                [[ "${PT_TEXT:PT_POS:1}" == "]" ]] || return 1
                PT_POS=$((PT_POS + 1))
                break
                ;;
            "]")
                PT_POS=$((PT_POS + 1))
                break
                ;;
            *)
                return 1
                ;;
        esac
    done
    for ((i = ${#items[@]} - 1; i >= 0; i--)); do
        new_cell "${items[i]}" "$tail"
        tail="$NEW_CELL"
    done
    TERM="$tail"
}

# --- Showing terms ------------------------------------------------------

# term_text TERM [SUBST] -> TERM_TEXT: how a term reads, e.g. [1, 2 | t].
# With SUBST, variables are filled in and ones with no value show as _ (or,
# with TT_KEEP_NAMES=1, as the name the user wrote).
TT_KEEP_NAMES=0
term_text() {
    local term="$1" subst="$2" have_subst=0
    [[ "$#" -ge 2 ]] && have_subst=1
    term_text_inner "$term" "$subst" "$have_subst"
    TERM_TEXT="$TT_OUT"
}

term_text_inner() {
    local term="$1" subst="$2" have_subst="$3" out="" first=1 item
    if [[ "$have_subst" -eq 1 ]]; then
        walk "$term" "$subst"
        term="$WALKED"
        if is_variable "$term"; then
            if [[ "$TT_KEEP_NAMES" -eq 1 ]]; then
                TT_OUT="${term%%#*}"
            else
                TT_OUT="_"
            fi
            return 0
        fi
    fi
    if ! is_cell "$term"; then
        TT_OUT="$term"
        return 0
    fi
    out="["
    while is_cell "$term"; do
        term_text_inner "${CELL_HEAD[${term#@}]}" "$subst" "$have_subst"
        if [[ "$first" -eq 1 ]]; then
            out+="$TT_OUT"
            first=0
        else
            out+=", $TT_OUT"
        fi
        term="${CELL_TAIL[${term#@}]}"
        if [[ "$have_subst" -eq 1 ]]; then
            walk "$term" "$subst"
            term="$WALKED"
        fi
    done
    if [[ "$term" != "[]" ]]; then
        if is_variable "$term"; then
            if [[ "$have_subst" -eq 1 ]]; then
                item="_"
            else
                item="$term"
            fi
        else
            item="$term"
        fi
        out+=" | $item"
    fi
    TT_OUT="$out]"
}

# --- Unification --------------------------------------------------------

# unify_terms A B SUBST -> UNIFY_SUBST
unify_terms() {
    local a="$1" b="$2" subst="$3"
    while true; do
        walk "$a" "$subst"
        a="$WALKED"
        walk "$b" "$subst"
        b="$WALKED"
        if [[ "$a" == "$b" ]]; then
            UNIFY_SUBST="$subst"
            return 0
        fi
        if is_variable "$a"; then
            UNIFY_SUBST="${subst}${a}=${b}${SUBST_SEP}"
            return 0
        fi
        if is_variable "$b"; then
            UNIFY_SUBST="${subst}${b}=${a}${SUBST_SEP}"
            return 0
        fi
        is_cell "$a" && is_cell "$b" || return 1
        # Heads first, then loop on the tails (so long lists don't nest
        # function calls).
        unify_terms "${CELL_HEAD[${a#@}]}" "${CELL_HEAD[${b#@}]}" "$subst" || return 1
        subst="$UNIFY_SUBST"
        a="${CELL_TAIL[${a#@}]}"
        b="${CELL_TAIL[${b#@}]}"
    done
}

# True if TERM, looked up in SUBST, has no variables without values.
term_is_ground() {
    local term="$1" subst="$2"
    while true; do
        walk "$term" "$subst"
        term="$WALKED"
        is_variable "$term" && return 1
        is_cell "$term" || return 0
        [[ "${CELL_GROUND[${term#@}]}" -eq 1 ]] && return 0
        term_is_ground "${CELL_HEAD[${term#@}]}" "$subst" || return 1
        term="${CELL_TAIL[${term#@}]}"
    done
}

# --- Renaming -----------------------------------------------------------

# rename_term TERM SUFFIX -> RENAMED_TERM: a copy with every variable
# renamed (x -> x#SUFFIX). Lists without variables are shared, not copied.
rename_term() {
    local term="$1" suffix="$2" head
    if is_variable "$term"; then
        RENAMED_TERM="${term}#${suffix}"
    elif is_cell "$term" && [[ "${CELL_GROUND[${term#@}]}" -ne 1 ]]; then
        rename_term "${CELL_HEAD[${term#@}]}" "$suffix"
        head="$RENAMED_TERM"
        rename_term "${CELL_TAIL[${term#@}]}" "$suffix"
        new_cell "$head" "$RENAMED_TERM"
        RENAMED_TERM="$NEW_CELL"
    else
        RENAMED_TERM="$term"
    fi
}

# term_vars TERM -> adds the variables inside TERM to the TERM_VARS array.
term_vars() {
    local term="$1"
    if is_variable "$term"; then
        TERM_VARS+=("$term")
    elif is_cell "$term" && [[ "${CELL_GROUND[${term#@}]}" -ne 1 ]]; then
        term_vars "${CELL_HEAD[${term#@}]}"
        term_vars "${CELL_TAIL[${term#@}]}"
    fi
    return 0
}

# map_term TERM FUNCTION -> MAPPED_TERM: a copy of TERM with FUNCTION
# applied to each variable (FUNCTION reads $1 and sets MAPPED_TOKEN).
map_term() {
    local term="$1" fn="$2" head
    if is_variable "$term"; then
        "$fn" "$term"
        MAPPED_TERM="$MAPPED_TOKEN"
    elif is_cell "$term" && [[ "${CELL_GROUND[${term#@}]}" -ne 1 ]]; then
        map_term "${CELL_HEAD[${term#@}]}" "$fn"
        head="$MAPPED_TERM"
        map_term "${CELL_TAIL[${term#@}]}" "$fn"
        new_cell "$head" "$MAPPED_TERM"
        MAPPED_TERM="$NEW_CELL"
    else
        MAPPED_TERM="$term"
    fi
}

# resolve_term TERM SUBST -> RESOLVED_TERM: TERM with every variable that
# has a value in SUBST replaced by it, all the way into lists (making new
# cells where needed). Used to keep each answer that collect gathers.
resolve_term() {
    local term="$1" subst="$2" head
    walk "$term" "$subst"
    term="$WALKED"
    if is_cell "$term" && [[ "${CELL_GROUND[${term#@}]}" -ne 1 ]]; then
        resolve_term "${CELL_HEAD[${term#@}]}" "$subst"
        head="$RESOLVED_TERM"
        resolve_term "${CELL_TAIL[${term#@}]}" "$subst"
        new_cell "$head" "$RESOLVED_TERM"
        RESOLVED_TERM="$NEW_CELL"
    else
        RESOLVED_TERM="$term"
    fi
}
