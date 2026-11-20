#lexer.sh
# shellcheck shell=bash

classify_word() {
    word="$1"
    KEYWORDS=("fact" "rule" "ask" "AND" "OR" "NOT")
    found=0
    for item in "${KEYWORDS[@]}"; do
        if [[ "$word" == "$item" ]]; then
            found=1
            break
        fi
    done
    if [[ "$found" -eq 1 ]]; then
        echo "KEYWORD: $word"
    elif [[ "$word" =~ ^-?[0-9]+$ ]]; then
        echo "NUMBER: $word"
    else
        echo "IDENTIFIER: $word"
    fi
}


emit_punctuation() {
    case "$1" in
        "(") echo "LEFT_PAREN" ;;
        ")") echo "RIGHT_PAREN" ;;
        ",") echo "COMMA" ;;
        ":") echo "COLON" ;;
    esac
}


# Prints one token per line. Quoted strings become a single STRING token, so
# spaces, commas, and '#' inside them are kept. A '#' outside a string starts a
# comment. Fails on an unterminated string.
tokenize_file() {
    local line char i line_number=0
    local current_word=""
    local in_string=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_number++))

        for ((i = 0; i < ${#line}; i++)); do
            char="${line:$i:1}"

            if [[ "$in_string" -eq 1 ]]; then
                current_word+="$char"
                if [[ "$char" == '"' ]]; then
                    echo "STRING: $current_word"
                    current_word=""
                    in_string=0
                fi

            elif [[ "$char" == '"' ]]; then
                if [[ -n "$current_word" ]]; then
                    classify_word "$current_word"
                fi
                current_word="$char"
                in_string=1

            elif [[ "$char" == "#" ]]; then
                break

            elif [[ "$char" =~ [[:space:]] ]]; then
                if [[ -n "$current_word" ]]; then
                    classify_word "$current_word"
                    current_word=""
                fi

            elif [[ "$char" == "<" || "$char" == ">" || "$char" == "=" || "$char" == "!" ]]; then
                if [[ -n "$current_word" ]]; then
                    classify_word "$current_word"
                    current_word=""
                fi
                if [[ "${line:$((i + 1)):1}" == "=" ]]; then
                    echo "OPERATOR: ${char}="
                    i=$((i + 1))
                else
                    echo "OPERATOR: $char"
                fi

            elif [[ "$char" == "(" || "$char" == ")" || "$char" == "," || "$char" == ":" ]]; then
                if [[ -n "$current_word" ]]; then
                    classify_word "$current_word"
                    current_word=""
                fi

                emit_punctuation "$char"

            else
                current_word+="$char"
            fi
        done

        if [[ "$in_string" -eq 1 ]]; then
            echo "Lexical error on line $line_number: unterminated string" >&2
            return 1
        fi

        if [[ -n "$current_word" ]]; then
            classify_word "$current_word"
            current_word=""
        fi

    done < "$1"
}
