classify_word() {
    word="$1"
    KEYWORDS=("fact" "rule" "ask" "AND" "OR")
    found=0
    for item in "${KEYWORDS[@]}"; do
        if [[ "$word" == "$item" ]]; then
            found=1
            break
        fi
    done
    if [[ "$found" -eq 1 ]]; then
        echo "KEYWORD: $word"
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


tokenize_file() {
    local line char i
    local current_word=""

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%%#*}"

        for ((i = 0; i < ${#line}; i++)); do
            char="${line:$i:1}"

            if [[ "$char" =~ [[:space:]] ]]; then
                if [[ -n "$current_word" ]]; then
                    classify_word "$current_word"
                    current_word=""
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

        if [[ -n "$current_word" ]]; then
            classify_word "$current_word"
            current_word=""
        fi

    done < "$1"
}
