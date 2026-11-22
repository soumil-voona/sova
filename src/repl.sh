#repl.sh
# shellcheck shell=bash
#
# repl [FILE]: an interactive prompt. Loads FILE if given (without running its
# asks), then reads one input at a time:
#   parent(who, "Sam")      a question ("ask" and a trailing "?" are optional)
#   trace parent(who, "Sam")
#                           the same, showing the search step by step first
#   fact parent("A", "B")   adds a fact
#   rule r(x):              adds a rule; type its body lines, then an empty line
#   import "lib.sova"       adds a file's facts and rules (paths are relative
#                           to FILE's folder, or the current one without FILE)
#   pseudocode ancestor     shows ancestor written as pseudocode (also takes
#                           a call, e.g. pseudocode ancestor("Ada", who))
#   python ancestor         the same as a Python program; also written as
#                           translate ancestor to python
#   javascript ancestor     the same as a JavaScript program (or js, or
#                           translate ancestor to javascript)
#   functional ancestor     the same as Python list comprehensions
#   compare ancestor        logic vs. imperative vs. functional, side by side
#   facts                   shows the knowledge base
#   help, quit
#
# Everything accepted so far is kept as source text in a session file. Each
# new fact or rule is parsed on its own first (so syntax errors report the
# right line), then appended and the whole session is reloaded.
# When input isn't a terminal (e.g. piped in tests) no prompts are printed.

REPL_INTERACTIVE=0
REPL_SESSION=""
REPL_SCRATCH=""
REPL_SHOWN_WARNINGS=()

repl_read() {
    if [[ "$REPL_INTERACTIVE" -eq 1 ]]; then
        local prompt="$1"
        # \001 and \002 tell readline the color codes take no space.
        [[ -n "$C_RESET" ]] && prompt=$'\001'"${C_BOLD}${C_MAGENTA}"$'\002'"$1"$'\001'"${C_RESET}"$'\002'
        IFS= read -e -r -p "$prompt" REPLY
    else
        IFS= read -r REPLY
    fi
}

repl_help() {
    cat <<'EOF'
  parent(who, "Sam")      ask a question ("ask" and "?" are optional)
  trace parent(who, "Sam")
                          the same, showing each step of the search first
  fact parent("A", "B")   add a fact
  rule r(x):              add a rule: type its body lines, then an empty line
  import "lib.sova"       add the facts and rules from another file
  pseudocode ancestor     show a predicate as pseudocode; a call like
                          ancestor("Ada", who) shapes it around known values
  python ancestor         the same as a runnable Python program
                          (or: translate ancestor to python)
  javascript ancestor     the same as a JavaScript program
                          (or: js ancestor, translate ancestor to javascript)
  functional ancestor     the same as Python list comprehensions
  compare ancestor        logic vs. imperative vs. functional code
  facts                   show everything Sova knows
  quit                    leave
EOF
}

# Prints arity warnings that haven't been shown yet this session.
repl_new_warnings() {
    local warning shown seen
    kb_check_arity
    for warning in "${ARITY_WARNINGS[@]}"; do
        seen=0
        for shown in "${REPL_SHOWN_WARNINGS[@]}"; do
            [[ "$shown" == "$warning" ]] && seen=1
        done
        if [[ "$seen" -eq 0 ]]; then
            # shellcheck disable=SC2153 # set in src/color.sh
            echo "${E_YELLOW}Warning:${E_RESET} $warning" >&2
            REPL_SHOWN_WARNINGS+=("$warning")
        fi
    done
}

# repl_add TEXT: adds facts or rules in TEXT to the session.
repl_add() {
    local text="$1" before
    printf '%s\n' "$text" > "$REPL_SCRATCH"
    parse_program "$REPL_SCRATCH" || return 0
    before="${#KB_FACTS[@]}/${#KB_RULES[@]}"

    printf '%s\n' "$text" >> "$REPL_SESSION"
    parse_program "$REPL_SESSION" || return 0
    kb_load
    repl_new_warnings
    if [[ "${#KB_FACTS[@]}/${#KB_RULES[@]}" == "$before" ]]; then
        echo "  ${C_DIM}Already known.${C_RESET}"
    else
        echo "  ${C_GREEN}Added.${C_RESET}"
    fi
}

# repl_ask TEXT: answers one "ask ..." line against the current session.
repl_ask() {
    local text="$1" node rest
    printf '%s\n' "$text" > "$REPL_SCRATCH"
    parse_program "$REPL_SCRATCH" || return 0
    node="${AST[0]}"
    if [[ "${#AST[@]}" -ne 1 || "${node%%"$AST_FS"*}" != "ASK" ]]; then
        echo "  Expected one question, like parent(who, \"Sam\")" >&2
        return 0
    fi
    rest="${node#*"$AST_FS"}"
    kb_ask "${rest%%"$AST_FS"*}" "${rest#*"$AST_FS"}"
}

repl() {
    local file="$1" line text

    [[ -t 0 ]] && REPL_INTERACTIVE=1
    REPL_SESSION="$(mktemp)"
    REPL_SCRATCH="$(mktemp)"
    # shellcheck disable=SC2064 # expand the paths now
    trap "rm -f '$REPL_SESSION' '$REPL_SCRATCH'" EXIT

    # The session is a temporary copy, so imports are looked up from FILE's
    # folder (or the current one) instead of the copy's.
    local base_dir="$PWD"
    [[ -n "$file" ]] && base_dir="$(cd "$(dirname "$file")" && pwd)"
    # shellcheck disable=SC2034 # read by parse_program in src/parser.sh
    PARSE_BASE_DIR="$base_dir"

    AST=()
    if [[ -n "$file" ]]; then
        cp "$file" "$REPL_SESSION"
        parse_program "$REPL_SESSION" || return 1
    fi
    kb_load
    repl_new_warnings

    if [[ "$REPL_INTERACTIVE" -eq 1 ]]; then
        if [[ -n "$file" ]]; then
            local facts="facts" rules="rules"
            [[ "${#KB_FACTS[@]}" -eq 1 ]] && facts="fact"
            [[ "${#KB_RULES[@]}" -eq 1 ]] && rules="rule"
            echo "Loaded $file: ${#KB_FACTS[@]} $facts, ${#KB_RULES[@]} $rules."
        fi
        echo "Ask a question like parent(who, \"Sam\"), or type 'help'."
    fi

    while repl_read "?- "; do
        line="$(trim "$REPLY")"
        case "$line" in
            "")
                continue
                ;;
            quit | exit)
                break
                ;;
            help)
                repl_help
                ;;
            pseudocode\ *)
                translate_to pseudo "$(trim "${line#pseudocode}")"
                ;;
            python\ *)
                translate_to python "$(trim "${line#python}")"
                ;;
            javascript\ * | js\ *)
                translate_to javascript "$(trim "${line#* }")"
                ;;
            functional\ *)
                translate_to functional "$(trim "${line#functional}")"
                ;;
            compare\ *)
                compare_paradigms "$(trim "${line#compare}")"
                ;;
            translate\ *\ to\ *)
                text="${line#translate }"
                case "${line##* to }" in
                    python) translate_to python "$(trim "${text% to *}")" ;;
                    javascript | js) translate_to javascript "$(trim "${text% to *}")" ;;
                    functional) translate_to functional "$(trim "${text% to *}")" ;;
                    pseudocode) translate_to pseudo "$(trim "${text% to *}")" ;;
                    *) echo "  Can translate to pseudocode, python, functional, or javascript" >&2 ;;
                esac
                ;;
            facts | kb)
                kb_print
                ;;
            trace\ *)
                line="$(trim "${line#trace}")"
                line="${line%\?}"
                [[ "$line" == ask\ * ]] || line="ask $line"
                local saved_trace="$SOVA_TRACE"
                SOVA_TRACE=1
                repl_ask "$line"
                SOVA_TRACE="$saved_trace"
                ;;
            fact\ * | import\ *)
                repl_add "$line"
                ;;
            rule\ *)
                text="$line"
                while repl_read "..  "; do
                    [[ -z "$(trim "$REPLY")" ]] && break
                    text+=$'\n'"$REPLY"
                done
                repl_add "$text"
                ;;
            *)
                line="${line%\?}"
                [[ "$line" == ask\ * ]] || line="ask $line"
                repl_ask "$line"
                ;;
        esac
    done
    [[ "$REPL_INTERACTIVE" -eq 1 ]] && echo
    return 0
}
