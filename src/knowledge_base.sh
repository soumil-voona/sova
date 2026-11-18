#knowledge_base.sh
#
# kb_load builds the knowledge base from the AST produced by parse_program:
#   KB_FACTS    "<name> FS <args>"                 (duplicates are skipped)
#   KB_RULES    "<name> FS <params>"
#   KB_GOALS    "<rule index> FS <op> FS <name> FS <args>"
#   KB_QUERIES  "<name> FS <args>"
# kb_run_queries answers each query against the stored facts.
# Rules are stored but not evaluated yet (that is the inference engine's job).

KB_FACTS=()
KB_RULES=()
KB_GOALS=()
KB_QUERIES=()

kb_load() {
    local node kind rest existing duplicate
    KB_FACTS=()
    KB_RULES=()
    KB_GOALS=()
    KB_QUERIES=()

    for node in "${AST[@]}"; do
        kind="${node%%"$AST_FS"*}"
        rest="${node#*"$AST_FS"}"
        case "$kind" in
            FACT)
                duplicate=0
                for existing in "${KB_FACTS[@]}"; do
                    [[ "$existing" == "$rest" ]] && duplicate=1 && break
                done
                [[ "$duplicate" -eq 0 ]] && KB_FACTS+=("$rest")
                ;;
            RULE)
                KB_RULES+=("$rest")
                ;;
            GOAL)
                KB_GOALS+=("$((${#KB_RULES[@]} - 1))${AST_FS}${rest}")
                ;;
            ASK)
                KB_QUERIES+=("$rest")
                ;;
        esac
    done
}

kb_has_rule() {
    local rule
    for rule in "${KB_RULES[@]}"; do
        [[ "${rule%%"$AST_FS"*}" == "$1" ]] && return 0
    done
    return 1
}

is_variable() {
    [[ "$1" != \"* ]]
}

# Matches query args against one fact's args, extending MATCH_BINDINGS.
# Variables are bound on first sight and must agree on later sightings.
match_fact() {
    local -a query_args fact_args
    IFS="$AST_AS" read -ra query_args <<< "$1"
    IFS="$AST_AS" read -ra fact_args <<< "$2"
    [[ "${#query_args[@]}" -eq "${#fact_args[@]}" ]] || return 1

    local -a names=() values=()
    local i j q f bound
    for ((i = 0; i < ${#query_args[@]}; i++)); do
        q="${query_args[$i]}"
        f="${fact_args[$i]}"
        if is_variable "$q"; then
            bound=0
            for ((j = 0; j < ${#names[@]}; j++)); do
                if [[ "${names[$j]}" == "$q" ]]; then
                    [[ "${values[$j]}" == "$f" ]] || return 1
                    bound=1
                fi
            done
            if [[ "$bound" -eq 0 ]]; then
                names+=("$q")
                values+=("$f")
            fi
        elif [[ "$q" != "$f" ]]; then
            return 1
        fi
    done

    MATCH_BINDINGS=""
    for ((j = 0; j < ${#names[@]}; j++)); do
        [[ -n "$MATCH_BINDINGS" ]] && MATCH_BINDINGS+=", "
        MATCH_BINDINGS+="${names[$j]} = ${values[$j]}"
    done
}

kb_ask() {
    local name="$1"
    local args="$2"
    local fact found=0

    echo "ask $name(${args//$AST_AS/, })"
    for fact in "${KB_FACTS[@]}"; do
        [[ "${fact%%"$AST_FS"*}" == "$name" ]] || continue
        if match_fact "$args" "${fact#*"$AST_FS"}"; then
            found=1
            [[ -n "$MATCH_BINDINGS" ]] && echo "  $MATCH_BINDINGS"
        fi
    done

    if [[ "$found" -eq 1 ]]; then
        echo "  TRUE"
        kb_has_rule "$name" && echo "  (results from rules are not included yet)"
    elif kb_has_rule "$name"; then
        echo "  UNKNOWN: '$name' is defined by a rule; rule evaluation is not implemented yet"
    else
        echo "  FALSE"
    fi
}

kb_run_queries() {
    local query
    for query in "${KB_QUERIES[@]}"; do
        kb_ask "${query%%"$AST_FS"*}" "${query#*"$AST_FS"}"
        echo
    done
}

kb_print() {
    local entry
    echo "Facts (${#KB_FACTS[@]}):"
    for entry in "${KB_FACTS[@]}"; do
        entry="${entry/$AST_FS/(}"
        echo "  ${entry//$AST_AS/, })"
    done
    echo "Rules (${#KB_RULES[@]}):"
    local i goal
    for ((i = 0; i < ${#KB_RULES[@]}; i++)); do
        entry="${KB_RULES[$i]/$AST_FS/(}"
        echo "  ${entry//$AST_AS/, }):"
        for goal in "${KB_GOALS[@]}"; do
            [[ "${goal%%"$AST_FS"*}" == "$i" ]] || continue
            goal="${goal#*"$AST_FS"}"
            goal="${goal/$AST_FS/ }"
            goal="${goal/$AST_FS/(}"
            goal="${goal#FIRST }"
            echo "    ${goal//$AST_AS/, })"
        done
    done
}
