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
    esac
}

