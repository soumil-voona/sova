#!/usr/bin/env bash
#test_text.sh
#
# Tests for the text built-ins: concat, text_length, and chars.

# shellcheck source=tests/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TEXT="$(cat "$TEST_DIR/translations/text.sova")"

check_output "concat joins text" "--brief" \
"$TEXT
ask greet(\"Sam\", m)
ask concat(\"ab\", \"cd\", x)
ask concat(\"ab\", \"cd\", \"abcd\")
ask concat(\"ab\", \"cd\", \"abc\")" \
'ask greet("Sam", m)
  m = "Hello, Sam!"
  TRUE

ask concat("ab", "cd", x)
  x = "abcd"
  TRUE

ask concat("ab", "cd", "abcd")
  TRUE

ask concat("ab", "cd", "abc")
  FALSE'

check_output "concat works backwards" "--brief" \
"$TEXT
ask suffix_of(\"walking\", \"ing\", s)
ask concat(\"un\", rest, \"undo\")
ask concat(\"re\", rest, \"undo\")
ask splits(\"ab\", a, b)" \
'ask suffix_of("walking", "ing", s)
  s = "walk"
  TRUE

ask concat("un", rest, "undo")
  rest = "do"
  TRUE

ask concat("re", rest, "undo")
  FALSE

ask splits("ab", a, b)
  a = "", b = "ab"
  a = "a", b = "b"
  a = "ab", b = ""
  TRUE'

check_output "text_length" "--brief" \
"$TEXT
ask text_length(\"hello\", n)
ask text_length(\"\", n)
ask long_word(\"banana\")
ask long_word(\"kiwi\")" \
'ask text_length("hello", n)
  n = 5
  TRUE

ask text_length("", n)
  n = 0
  TRUE

ask long_word("banana")
  TRUE

ask long_word("kiwi")
  FALSE'

check_output "chars both ways" "--brief" \
"$TEXT
ask chars(\"cat\", l)
ask chars(t, [\"d\", \"o\", \"g\"])
ask shout(\"hi\", l)
ask palindrome(\"level\")
ask palindrome(\"sova\")" \
'ask chars("cat", l)
  l = ["c", "a", "t"]
  TRUE

ask chars(t, ["d", "o", "g"])
  t = "dog"
  TRUE

ask shout("hi", l)
  l = "hi!!"
  TRUE

ask palindrome("level")
  TRUE

ask palindrome("sova")
  FALSE'

check_output "Errors: not text, or not known yet" "--brief" \
'ask text_length(5, n)
ask concat(a, b, c)
ask chars(t, l)
ask chars(t, [1, 2])' \
'ask text_length(5, n)
  UNKNOWN: some goals could not be checked
  ERROR: '"'"'text_length(5, n)'"'"' needs text, but 5 isn'"'"'t text

ask concat(a, b, c)
  UNKNOWN: some goals could not be checked
  ERROR: '"'"'concat(a, b, c)'"'"' needs the whole text, or both parts, to be known first

ask chars(t, l)
  UNKNOWN: some goals could not be checked
  ERROR: '"'"'chars(t, l)'"'"' needs the text or the list to be known first

ask chars(t, [1, 2])
  UNKNOWN: some goals could not be checked
  ERROR: '"'"'chars(t, [1, 2])'"'"' needs a list of text, but 1 isn'"'"'t text'

check_output "Built-ins in proofs" "" \
"$TEXT
ask greet(\"Sam\", m)" \
'ask greet("Sam", m)
  m = "Hello, Sam!"
    greet("Sam", "Hello, Sam!")  [rule greet]
      concat("Hello, ", "Sam", "Hello, Sam")  [built-in]
      concat("Hello, Sam", "!", "Hello, Sam!")  [built-in]
  TRUE'

check_output "A program's own concat replaces the built-in" "--brief" \
'fact concat("a", "b", "custom")
ask concat("a", "b", x)' \
'ask concat("a", "b", x)
  x = "custom"
  TRUE'

finish_tests
