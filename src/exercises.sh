#exercises.sh
# shellcheck shell=bash
#
# The exercises in exercises/ are numbered Sova files with instructions in
# comments, facts to work with, and expect lines that check the answer.
#
#   ./sova --exercises   lists them and how far your copies have got
#   ./sova --start N     copies exercise N into your work folder
#   ./sova --check FILE  checks a copy (see src/check.sh)
#
# Copies go in $SOVA_EXERCISE_DIR, or my-exercises/ in the current folder.
# Starting an exercise never overwrites a copy you already have.

EXERCISE_SOURCE_DIR="$SOVA_DIR/exercises"
EXERCISE_WORK_DIR="${SOVA_EXERCISE_DIR:-$PWD/my-exercises}"

# exercise_title FILE -> EXERCISE_TITLE: from its first line,
# "# Exercise 3: AND" -> "AND".
exercise_title() {
    local line
    IFS= read -r line < "$1"
    line="${line#\# }"
    EXERCISE_TITLE="${line#*: }"
}

# exercise_file N -> EXERCISE_FILE (exercises/03-....sova), or fails.
exercise_file() {
    local number file
    [[ "$1" =~ ^[0-9]+$ ]] || return 1
    printf -v number '%02d' "$((10#$1))"
    for file in "$EXERCISE_SOURCE_DIR/$number"-*.sova; do
        if [[ -f "$file" ]]; then
            EXERCISE_FILE="$file"
            return 0
        fi
    done
    return 1
}

list_exercises() {
    local file name copy status number
    echo "Sova exercises"
    echo
    for file in "$EXERCISE_SOURCE_DIR"/*.sova; do
        name="$(basename "$file")"
        number="$((10#${name%%-*}))"
        exercise_title "$file"
        copy="$EXERCISE_WORK_DIR/$name"
        if [[ ! -f "$copy" ]]; then
            status="not started"
        else
            # Each check runs in a subshell so one copy can't affect another.
            local counts
            # shellcheck disable=SC2034 # CHECK_QUIET is read by check_file
            counts="$(CHECK_QUIET=1; check_file "$copy" > /dev/null 2>&1; echo "$CHECK_PASSED $CHECK_TOTAL")"
            local passed="${counts%% *}" total="${counts##* }"
            if [[ "$total" -gt 0 && "$passed" -eq "$total" ]]; then
                status="done"
            elif [[ "$total" -eq 0 ]]; then
                status="has a syntax error"
            else
                status="$passed of $total checks pass"
            fi
        fi
        printf '  %2d  %-34s %s\n' "$number" "$EXERCISE_TITLE" "$status"
    done
    echo
    echo "Start one with:  ./sova --start N"
    echo "Check your copy: ./sova --check ${EXERCISE_WORK_DIR#"$PWD"/}/FILE"
}

start_exercise() {
    local copy
    if ! exercise_file "$1"; then
        echo "There is no exercise $1. See the list with: ./sova --exercises" >&2
        return 1
    fi
    mkdir -p "$EXERCISE_WORK_DIR" || return 1
    copy="$EXERCISE_WORK_DIR/$(basename "$EXERCISE_FILE")"
    local shown="${copy#"$PWD"/}"
    if [[ -f "$copy" ]]; then
        echo "You already have $shown (it wasn't changed)."
    else
        cp "$EXERCISE_FILE" "$copy" || return 1
        echo "Created $shown"
    fi
    echo "Open it, follow the instructions at the top, then check your work with:"
    echo "  ./sova --check $shown"
}
