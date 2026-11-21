#check.sh
# shellcheck shell=bash
# Sets globals that the search (src/inference.sh) reads:
# shellcheck disable=SC2034
#
# check_file FILE runs the expect lines in FILE (see src/parser.sh) and says
# which pass. When one fails it explains why, like a tutor:
#   - a question that should be true: Sova's dead ends (what couldn't be
#     proved), or which predicate isn't defined yet
#   - a question that should be false: the proof Sova found
#   - a "gives" question: which answers are missing and which are unexpected
# and then shows the file's hints. When everything passes, it suggests
# seeing the rule as code with --compare.
#
# Sets CHECK_PASSED and CHECK_TOTAL; with CHECK_QUIET=1 it prints nothing
# (used to show progress in the exercise list). Returns 0 if all checks pass.

CHECK_QUIET=0
CHECK_MISSING_PREDS=()
CHECK_PASSED=0
CHECK_TOTAL=0

check_say() {
    [[ "$CHECK_QUIET" -eq 1 ]] || printf '%s\n' "$1"
}

# check_answers -> CHECK_GOT: each answer found by the last search, as the
# values of QUERY_VARS: "Ben" for one variable, ("Ada", "Ben") for several.
check_answers() {
    local subst var values
    local -a parts
    CHECK_GOT=()
    for subst in "${SOLUTION_SUBSTS[@]}"; do
        parts=()
        for var in "${QUERY_VARS[@]}"; do
            term_text "$var" "$subst"
            parts+=("$TERM_TEXT")
        done
        if [[ "${#parts[@]}" -eq 1 ]]; then
            values="${parts[0]}"
        else
            values="$(IFS=$'\x01'; printf '%s' "${parts[*]}")"
            values="(${values//$'\x01'/, })"
        fi
        CHECK_GOT+=("$values")
    done
}

# check_expected ANSWERS -> CHECK_WANT: the answers written in the expect
# line, in the same form as CHECK_GOT.
check_expected() {
    local answer term values
    local -a answer_list parts terms
    CHECK_WANT=()
    [[ -n "$1" ]] || return 0
    split_on "$ANSWER_SEP" "$1"
    answer_list=("${SPLIT[@]}")
    for answer in "${answer_list[@]}"; do
        split_on "$AST_AS" "$answer"
        terms=("${SPLIT[@]}")
        parts=()
        for term in "${terms[@]}"; do
            term_text "$term"
            parts+=("$TERM_TEXT")
        done
        if [[ "${#parts[@]}" -eq 1 ]]; then
            values="${parts[0]}"
        else
            values="$(IFS=$'\x01'; printf '%s' "${parts[*]}")"
            values="(${values//$'\x01'/, })"
        fi
        CHECK_WANT+=("$values")
    done
}

# in_list VALUE ITEM...: succeeds if VALUE is one of the items.
in_list() {
    local value="$1" item
    shift
    for item in "$@"; do
        [[ "$item" == "$value" ]] && return 0
    done
    return 1
}

# check_explain_nothing NAME ARGS: why the last search found nothing, in
# the same words a normal run uses (src/explain.sh), indented under the
# check. Errors are shown instead when there were any.
#
# Only the first failing check is explained in full, so the output points
# at one thing to fix at a time.
CHECK_EXPLAINED=0
check_explain_nothing() {
    local entry
    [[ "$CHECK_QUIET" -eq 1 || "$CHECK_EXPLAINED" -eq 1 ]] && return 0
    CHECK_EXPLAINED=1
    if [[ "${#ERRORS[@]}" -gt 0 ]]; then
        for entry in "${ERRORS[@]}"; do
            check_say "      Error: $entry"
        done
        return 0
    fi
    if [[ "$DEPTH_LIMIT_HIT" -eq 1 ]]; then
        check_say "      The search stopped at the depth limit: a rule may be calling itself forever."
        return 0
    fi
    # Already said at the top: nothing defines it yet.
    in_list "$1" "${CHECK_MISSING_PREDS[@]}" && return 0
    explain_false "$1" "$2" | sed 's/^\(.\)/      \1/'
}

# check_one KIND NAME ARGS ANSWERS: runs one expect line. Succeeds if it
# passes.
check_one() {
    local kind="$1" name="$2" args="$3" answers="$4" term var label i
    format_goal "$name" "$args"
    local goal="$FORMATTED"

    QUERY_VARS=()
    SOLUTIONS=()
    SOLUTION_PROOFS=()
    SOLUTION_SUBSTS=()
    ERRORS=()
    DEPTH_LIMIT_HIT=0
    FAIL_KEYS=()
    FAIL_PATHS=()
    FAIL_PATH_SUBSTS=()
    FAIL_COUNTS=()
    FAIL_DEPTHS=()
    FAIL_RECORDING=1
    TERM_VARS=()
    split_on "$AST_AS" "$args"
    for term in "${SPLIT[@]}"; do
        term_vars "$term"
    done
    for var in "${TERM_VARS[@]}"; do
        add_unique QUERY_VARS "$var"
    done
    # Proofs are needed to show why a "should be false" check failed.
    # shellcheck disable=SC2034 # read by src/inference.sh
    SOVA_BRIEF=0
    run_search "0${AST_FS}${name}${AST_FS}${args}" "$SUBST_SEP" 0 ""
    FAIL_RECORDING=0
    check_answers

    local found="${#CHECK_GOT[@]}" unknown=0
    [[ "$found" -eq 0 && ( "${#ERRORS[@]}" -gt 0 || "$DEPTH_LIMIT_HIT" -eq 1 ) ]] && unknown=1

    case "$kind" in
        yes)
            label="$goal is true"
            if [[ "$found" -gt 0 ]]; then
                check_say "  ✓ $label"
                return 0
            fi
            check_say "  ✗ $label"
            check_explain_nothing "$name" "$args"
            return 1
            ;;
        no)
            label="$goal is false"
            # Before the predicate is written, "false" would pass for the
            # wrong reason, so it only counts once the predicate exists.
            if in_list "$name" "${CHECK_MISSING_PREDS[@]}"; then
                check_say "  ✗ $label"
                return 1
            fi
            if [[ "$found" -eq 0 && "$unknown" -eq 0 ]]; then
                check_say "  ✓ $label"
                return 0
            fi
            check_say "  ✗ $label"
            if [[ "$found" -gt 0 ]]; then
                if [[ "$CHECK_QUIET" -ne 1 && "$CHECK_EXPLAINED" -eq 0 ]]; then
                    CHECK_EXPLAINED=1
                    check_say "      But Sova can prove it:"
                    explain_answer "${SOLUTION_PROOFS[0]}" "${SOLUTION_SUBSTS[0]}" 8 ""
                fi
            else
                check_explain_nothing "$name" "$args"
            fi
            return 1
            ;;
        gives)
            check_expected "$answers"
            local want_text got_text
            want_text="$(IFS=$'\x01'; printf '%s' "${CHECK_WANT[*]}")"
            want_text="${want_text//$'\x01'/, }"
            label="$goal gives $want_text"
            local -a missing=() extra=()
            for ((i = 0; i < ${#CHECK_WANT[@]}; i++)); do
                in_list "${CHECK_WANT[i]}" "${CHECK_GOT[@]}" || missing+=("${CHECK_WANT[i]}")
            done
            for ((i = 0; i < found; i++)); do
                in_list "${CHECK_GOT[i]}" "${CHECK_WANT[@]}" || extra+=("${CHECK_GOT[i]}")
            done
            if [[ "${#missing[@]}" -eq 0 && "${#extra[@]}" -eq 0 && "$unknown" -eq 0 ]]; then
                check_say "  ✓ $label"
                return 0
            fi
            check_say "  ✗ $label"
            if [[ "$found" -eq 0 ]]; then
                check_say "      Sova found no answers."
                check_explain_nothing "$name" "$args"
                return 1
            fi
            got_text="$(IFS=$'\x01'; printf '%s' "${CHECK_GOT[*]}")"
            check_say "      Sova gave: ${got_text//$'\x01'/, }"
            if [[ "${#missing[@]}" -gt 0 ]]; then
                got_text="$(IFS=$'\x01'; printf '%s' "${missing[*]}")"
                check_say "      Missing: ${got_text//$'\x01'/, }"
            fi
            if [[ "${#extra[@]}" -gt 0 ]]; then
                got_text="$(IFS=$'\x01'; printf '%s' "${extra[*]}")"
                check_say "      Not expected: ${got_text//$'\x01'/, }"
            fi
            return 1
            ;;
    esac
}

# check_file FILE
check_file() {
    local file="$1" node kind rest name args answers
    local -a expects=() hints=()
    CHECK_PASSED=0
    CHECK_TOTAL=0

    if [[ "$CHECK_QUIET" -eq 1 ]]; then
        parse_program "$file" 2>/dev/null || return 2
    else
        parse_program "$file" || return 2
    fi
    kb_load
    [[ "$CHECK_QUIET" -eq 1 ]] || kb_print_arity_warnings

    for node in "${AST[@]}"; do
        case "${node%%"$AST_FS"*}" in
            EXPECT) expects+=("${node#*"$AST_FS"}") ;;
            HINT) hints+=("${node#*"$AST_FS"}") ;;
        esac
    done
    if [[ "${#expects[@]}" -eq 0 ]]; then
        check_say "$file has no expect lines to check."
        return 2
    fi

    check_say "Checking $file"
    check_say ""
    CHECK_EXPLAINED=0

    # Say once which predicates the checks need but nothing defines yet.
    CHECK_MISSING_PREDS=()
    for node in "${expects[@]}"; do
        split_on "$AST_FS" "$node"
        name="${SPLIT[1]}"
        if ! pred_has_rules "$name" && ! pred_has_facts "$name" && ! is_text_builtin "$name"; then
            add_unique CHECK_MISSING_PREDS "$name"
        fi
    done
    local missing_pred
    for missing_pred in "${CHECK_MISSING_PREDS[@]}"; do
        check_say "Nothing defines '$missing_pred' yet: write it where the file says."
    done
    [[ "${#CHECK_MISSING_PREDS[@]}" -gt 0 ]] && check_say ""

    local first_pred=""
    for node in "${expects[@]}"; do
        split_on "$AST_FS" "$node"
        kind="${SPLIT[0]}" name="${SPLIT[1]}" args="${SPLIT[2]}" answers="${SPLIT[3]}"
        [[ -z "$first_pred" ]] && first_pred="$name"
        CHECK_TOTAL=$((CHECK_TOTAL + 1))
        if check_one "$kind" "$name" "$args" "$answers"; then
            CHECK_PASSED=$((CHECK_PASSED + 1))
        fi
    done

    check_say ""
    if [[ "$CHECK_PASSED" -eq "$CHECK_TOTAL" ]]; then
        check_say "All $CHECK_TOTAL checks pass."
        if pred_has_rules "$first_pred"; then
            check_say "See your rule written as code: ./sova --compare $first_pred $file"
        fi
        return 0
    fi
    check_say "$CHECK_PASSED of $CHECK_TOTAL checks pass."
    local hint
    for hint in "${hints[@]}"; do
        hint="${hint#\"}"
        check_say "Hint: ${hint%\"}"
    done
    return 1
}
