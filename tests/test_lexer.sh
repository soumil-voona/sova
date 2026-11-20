#!/usr/bin/env bash
#test_lexer.sh
#
# Tests for tokenize_file (checked through ./sova --tokens).

# shellcheck source=tests/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

check_output "Fact tokens" "--tokens" \
'fact parent("Alex", "Sam")' \
'KEYWORD: fact
IDENTIFIER: parent
LEFT_PAREN
STRING: "Alex"
COMMA
STRING: "Sam"
RIGHT_PAREN'

check_output "Strings keep spaces, commas, and #" "--tokens" \
'fact name("Smith, Alex #1")' \
'KEYWORD: fact
IDENTIFIER: name
LEFT_PAREN
STRING: "Smith, Alex #1"
RIGHT_PAREN'

check_output "Comments are skipped" "--tokens" \
'# a comment
ask p(x) # trailing' \
'KEYWORD: ask
IDENTIFIER: p
LEFT_PAREN
IDENTIFIER: x
RIGHT_PAREN'

check_output "Rule keywords and colon" "--tokens" \
'rule g(x):
    p(x)
    AND q(x)' \
'KEYWORD: rule
IDENTIFIER: g
LEFT_PAREN
IDENTIFIER: x
RIGHT_PAREN
COLON
IDENTIFIER: p
LEFT_PAREN
IDENTIFIER: x
RIGHT_PAREN
KEYWORD: AND
IDENTIFIER: q
LEFT_PAREN
IDENTIFIER: x
RIGHT_PAREN'

check_output "Unterminated string is an error" "--tokens" \
'fact p("oops)' \
'KEYWORD: fact
IDENTIFIER: p
LEFT_PAREN
Lexical error on line 1: unterminated string'

check_output "Numbers, NOT, and operators" "--tokens" \
'rule r(x):
    a >= -18
    AND NOT p(x)
    AND x!="b"' \
'KEYWORD: rule
IDENTIFIER: r
LEFT_PAREN
IDENTIFIER: x
RIGHT_PAREN
COLON
IDENTIFIER: a
OPERATOR: >=
NUMBER: -18
KEYWORD: AND
KEYWORD: NOT
IDENTIFIER: p
LEFT_PAREN
IDENTIFIER: x
RIGHT_PAREN
KEYWORD: AND
IDENTIFIER: x
OPERATOR: !=
STRING: "b"'

finish_tests
