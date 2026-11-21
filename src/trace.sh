#trace.sh
# shellcheck shell=bash
# Sets globals that src/inference.sh and src/terms.sh read:
# shellcheck disable=SC2034
#
# Trace mode (--trace, or "trace" at the prompt): prints the search as it
# happens, so you can watch Sova work instead of only seeing the finished
# proof. src/inference.sh calls these functions while TRACE_ON is 1.
#
#   Trace:
#     [1] grandparent("Sam", who)
#         Try rule grandparent(x, z) if parent(x, y) AND parent(y, z)
#         matches, with x = "Sam", z = who
#         [2] parent("Sam", y)
#             2 options: 2 facts match
#             Try fact parent("Sam", "Jamie"): matches, with y = "Jamie"
#             [3] parent("Jamie", who)
#                 ✗ No matching fact exists.
#         ↩ Back to [2] parent("Sam", y): option 2 of 2
#             Try fact parent("Sam", "Alex"): matches, with y = "Alex"
#             ...
#     ✓ Answer 1: who = "Ben"
#     Search finished: 1 answer, 4 goals tried.
#
# Each goal is numbered when Sova starts on it, and indented by how deeply
# it is nested inside rules. When a goal can be met more than one way,
# Sova tries the first option and keeps the others; "↩ Back to" shows it
# returning to one of them after the path it was on ended (in a dead end,
# or with an answer, since Sova goes on looking for more).
#
# A goal's options are saved with a note (see trace_note) so the trace can
# say which goal and which option the search went back to.
#
# Long searches would print thousands of lines, so the trace stops after
# $SOVA_TRACE_LIMIT goals (the search itself carries on).

SOVA_TRACE="${SOVA_TRACE:-0}"
SOVA_TRACE_LIMIT="${SOVA_TRACE_LIMIT:-300}"
TRACE_ON=0
TRACE_GOALS=0
TRACE_CUT=0
# How far in answer lines go: 2 for the question, deeper for the inner
# search of a NOT, collect, or count.
TRACE_ANSWER_INDENT=2
TRACE_INNER=0

# trace_start: begins tracing a question.
trace_start() {
    TRACE_ON=1
    TRACE_GOALS=0
    TRACE_CUT=0
    TRACE_INNER=0
    TRACE_ANSWER_INDENT=2
    echo
    echo "${C_BOLD}Trace:${C_RESET}"
}

# trace_finish: the summary line, after the search.
trace_finish() {
    local count="${#SOLUTIONS[@]}" answers="answers" goals="goals"
    [[ "$count" -eq 1 ]] && answers="answer"
    [[ "$TRACE_GOALS" -eq 1 ]] && goals="goal"
    if [[ "$TRACE_CUT" -eq 1 ]]; then
        say 2 "${C_DIM}Search finished: $count $answers, $TRACE_GOALS $goals tried (the trace shows the first $SOVA_TRACE_LIMIT).${C_RESET}"
    else
        say 2 "${C_DIM}Search finished: $count $answers, $TRACE_GOALS $goals tried.${C_RESET}"
    fi
    TRACE_ON=0
}

# trace_text NAME ARGS SUBST -> TRACE_TEXT: a goal as it reads with the
# values known so far (unknowns keep their names).
trace_text() {
    RESOLVE_KEEP_NAMES=1
    resolve_args "$2" "$3"
    RESOLVE_KEEP_NAMES=0
    format_goal "$1" "$RESOLVED"
    TRACE_TEXT="$FORMATTED"
}

# trace_goal NAME ARGS SUBST LEVEL: counts a goal and, while tracing,
# prints it as "[n] goal". Sets TRACE_TEXT. Stops the trace once it has
# shown $SOVA_TRACE_LIMIT goals.
trace_goal() {
    TRACE_GOALS=$((TRACE_GOALS + 1))
    [[ "$TRACE_ON" -eq 1 ]] || return 0
    if [[ "$TRACE_GOALS" -gt "$SOVA_TRACE_LIMIT" ]]; then
        TRACE_ON=0
        TRACE_CUT=1
        say 2 "... the trace stops here, after $SOVA_TRACE_LIMIT goals (set SOVA_TRACE_LIMIT to see more); the search keeps going."
        return 0
    fi
    trace_text "$1" "$2" "$3"
    say $((2 + 4 * $4)) "${C_CYAN}[$TRACE_GOALS]${C_RESET} $TRACE_TEXT"
}

# trace_line LEVEL TEXT: a line about the goal at LEVEL (under it).
trace_line() {
    local text="$2"
    if [[ -n "$C_RESET" ]]; then
        case "$text" in
            "✓ "*) text="${C_GREEN}✓${C_RESET} ${text#"✓ "}" ;;
            "✗ "*) text="${C_RED}✗${C_RESET} ${text#"✗ "}" ;;
        esac
    fi
    say $((6 + 4 * $1)) "$text"
}

# trace_bindings SUBST LENGTH -> TRACE_BINDS: the bindings SUBST has gained
# since it was LENGTH long, as "x = value, y = value". Bindings that only
# pass a variable on under the same name (x = x) are left out, and two
# variables joined are shown with the rule's variable first (z = who).
trace_bindings() {
    local subst="$1" entry var name text=""
    local -a entries
    TRACE_BINDS=""
    [[ "${#subst}" -gt "$2" ]] || return 0
    split_on "$SUBST_SEP" "${subst:$2}"
    entries=("${SPLIT[@]}")
    for entry in "${entries[@]}"; do
        [[ -n "$entry" ]] || continue
        var="${entry%%=*}"
        name="${var%%#*}"
        TT_KEEP_NAMES=1
        term_text "$var" "$subst"
        TT_KEEP_NAMES=0
        [[ "$TERM_TEXT" == "$name" ]] && continue
        walk "$var" "$subst"
        if is_variable "$WALKED"; then
            # Two variables joined: say it as "the rule's z is the
            # question's who", whichever way round it was stored.
            if [[ "$var" == *"#"* ]]; then
                text="${text:+${text}, }$name = $TERM_TEXT"
            else
                text="${text:+${text}, }$TERM_TEXT = $name"
            fi
        else
            text="${text:+${text}, }$name = $TERM_TEXT"
        fi
    done
    TRACE_BINDS="$text"
}

# trace_result LEVEL NEW_SUBST OLD_SUBST: "✓ x = value" (or "✓ true") for
# a goal that is met without options to choose between.
trace_result() {
    trace_bindings "$2" "${#3}"
    if [[ -n "$TRACE_BINDS" ]]; then
        trace_line "$1" "✓ $TRACE_BINDS"
    else
        trace_line "$1" "✓ true"
    fi
}

# trace_failed LEVEL REASON: "✗ reason", or, when the goal couldn't be
# checked at all (REASON is empty), a pointer to the error.
trace_failed() {
    if [[ -n "$2" ]]; then
        trace_line "$1" "✗ $2"
    else
        trace_line "$1" "✗ It can't be checked yet (see the error after the trace)."
    fi
}

# trace_options LEVEL FACTS RESULTS KIND...: how many ways a goal can be
# met, when there is more than one. FACTS is how many facts matched,
# RESULTS how many results a built-in gave, and the KINDs (see trace_note)
# are the options, which tell whole rules apart from the OR branches of one
# rule.
trace_options() {
    local level="$1" facts="$2" results="$3" text="" word kind
    shift 3
    local total="$#" alts=0
    local -a rule_indexes=()
    [[ "$total" -gt 1 ]] || return 0
    if [[ "$results" -gt 0 ]]; then
        trace_line "$level" "$total options: $results possible results"
        return 0
    fi
    for kind in "$@"; do
        [[ "$kind" == A* ]] || continue
        alts=$((alts + 1))
        add_unique rule_indexes "${KB_ALTS[${kind#A}]%%"$AST_FS"*}"
    done
    if [[ "$facts" -gt 0 ]]; then
        word="facts"
        [[ "$facts" -eq 1 ]] && word="fact"
        text="$facts $word"
    fi
    if [[ "$alts" -gt 0 ]]; then
        if [[ "${#rule_indexes[@]}" -eq "$alts" ]]; then
            word="rules"
            [[ "$alts" -eq 1 ]] && word="rule"
        else
            # Some options are OR branches of the same rule.
            word="OR branches"
        fi
        text="${text:+${text} and }$alts $word"
    fi
    trace_line "$level" "$total options: $text match"
}

# trace_note NUMBER POSITION COUNT KIND SUBST LEVEL TEXT -> TRACE_NOTE:
# what a saved option is, for printing when the search takes it up. KIND
# is F<fact index>, A<KB_ALTS index>, or B (a built-in's result); TEXT is
# the goal as it read before the option.
trace_note() {
    TRACE_NOTE="${1}${AST_FS}${2}${AST_FS}${3}${AST_FS}${4}${AST_FS}${#5}${AST_FS}${6}${AST_FS}${7}"
}

# trace_option NOTE SUBST: the search has taken up a saved option: says so
# (with "↩ Back to" if earlier options were tried first) and shows what it
# matched.
trace_option() {
    [[ "$TRACE_ON" -eq 1 ]] || return 0
    split_on "$AST_FS" "$1"
    local number="${SPLIT[0]}" position="${SPLIT[1]}" count="${SPLIT[2]}"
    local kind="${SPLIT[3]}" length="${SPLIT[4]}" level="${SPLIT[5]}" text="${SPLIT[6]}"
    local id
    if [[ "$position" -gt 1 ]]; then
        say $((2 + 4 * level)) "${C_YELLOW}↩ Back to [$number]${C_RESET} $text: ${C_DIM}option $position of $count${C_RESET}"
    fi
    trace_bindings "$2" "$length"
    case "$kind" in
        F*)
            id="${kind#F}"
            format_goal "${KB_FACTS[id]%%"$AST_FS"*}" "${KB_FACTS[id]#*"$AST_FS"}"
            if [[ -n "$TRACE_BINDS" ]]; then
                trace_line "$level" "Try fact $FORMATTED: matches, with $TRACE_BINDS"
            else
                trace_line "$level" "Try fact $FORMATTED: matches"
            fi
            ;;
        A*)
            id="${kind#A}"
            rule_source "${KB_ALTS[id]%%"$AST_FS"*}"
            trace_line "$level" "Try rule $RULE_SOURCE"
            alt_branch "$id"
            [[ "$BRANCH_COUNT" -gt 1 ]] && trace_line "$level" "(using: $BRANCH_TEXT)"
            if [[ -n "$TRACE_BINDS" ]]; then
                trace_line "$level" "matches, with $TRACE_BINDS"
            else
                trace_line "$level" "matches"
            fi
            ;;
        *)
            if [[ -n "$TRACE_BINDS" ]]; then
                trace_line "$level" "✓ $TRACE_BINDS"
            else
                trace_line "$level" "✓ true"
            fi
            ;;
    esac
}

# trace_answer BEFORE: a path reached the end with every goal met. BEFORE
# is how many answers there were before it (an answer found again isn't
# counted twice).
trace_answer() {
    [[ "$TRACE_ON" -eq 1 ]] || return 0
    local count="${#SOLUTIONS[@]}" text
    source_name "${SOLUTIONS[count - 1]}"
    text="$SOURCE_NAME"
    if [[ "$TRACE_INNER" -gt 0 ]]; then
        if [[ "$count" -eq "$1" ]]; then
            say "$TRACE_ANSWER_INDENT" "✓ Found again${text:+: $text}"
        elif [[ -n "$text" ]]; then
            say "$TRACE_ANSWER_INDENT" "✓ Found: $text"
        else
            say "$TRACE_ANSWER_INDENT" "✓ It can be proved."
        fi
    elif [[ "$count" -eq "$1" ]]; then
        say 2 "✓ Same answer again${text:+: $text} (shown once)"
    elif [[ -n "$text" ]]; then
        say 2 "${C_BOLD}${C_GREEN}✓ Answer $count:${C_RESET} $text"
    else
        say 2 "✓ It's true."
    fi
}

# trace_inner_start LEVEL TEXT / trace_inner_end: around the inner search
# of a NOT, collect, or count at LEVEL. TEXT introduces it.
trace_inner_start() {
    TRACE_SAVED_INDENT+=("$TRACE_ANSWER_INDENT")
    TRACE_INNER=$((TRACE_INNER + 1))
    TRACE_ANSWER_INDENT=$((6 + 4 * $1))
    [[ "$TRACE_ON" -eq 1 ]] && trace_line "$1" "$2"
    return 0
}

TRACE_SAVED_INDENT=()
trace_inner_end() {
    local last=$((${#TRACE_SAVED_INDENT[@]} - 1))
    TRACE_ANSWER_INDENT="${TRACE_SAVED_INDENT[last]}"
    unset "TRACE_SAVED_INDENT[last]"
    TRACE_INNER=$((TRACE_INNER - 1))
}
