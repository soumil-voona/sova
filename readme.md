# Sova

**Think logically. Code independently.**

Sova is an experimental declarative programming language built in Bash, designed to make logical reasoning, programming, and problem-solving more accessible.

Rather than specifying every step a computer must execute, Sova allows programmers to define facts, relationships, rules, and goals. Its inference engine determines what conclusions can be derived and explains how it reached them.

Sova also aims to bridge the gap between declarative and conventional programming by teaching users how to translate logical solutions into pseudocode and other programming languages.

> **Project status:** Early development. Core language and architecture are being designed.

## Vision

Sova has two interconnected goals:

1. **A programming language:** Provide a functional logic programming environment with facts, rules, queries, and automated inference.
2. **A learning environment:** Help programmers understand the reasoning behind solutions and learn how to implement those solutions in conventional languages.

The goal is not just to produce answers, but to help programmers understand how and why those answers are reached.

## Core Features

### Language Engine
- Declarative programming syntax
- Fact and rule declarations
- Variables and logical unification
- Query evaluation
- Inference and backtracking
- Knowledge base management

### Explainable Execution
- Trace the reasoning behind query results
- Generate human-readable proof trees
- Identify which facts and rules contributed to a conclusion
- Explain unsuccessful queries

### Learning Environment
- Generate language-independent pseudocode
- Translate Sova logic into conventional programming languages
- Compare different programming paradigms
- Interactive exercises and programming challenges
- Explanations of underlying computer science concepts

## Example

A Sova program might look like this:

```text
# Define facts
fact parent("Alex", "Sam")
fact parent("Sam", "Jamie")

# Define a logical relationship
rule grandparent(x, z):
    parent(x, y)
    AND parent(y, z)

# Ask a question
ask grandparent("Alex", "Jamie")
```

Result:

```text
ask grandparent("Alex", "Jamie")

TRUE, because:
  grandparent("Alex", "Jamie") is satisfied by:
    grandparent(x, z) if parent(x, y) AND parent(y, z)

  Variable bindings:
    x = "Alex"
    y = "Sam"
    z = "Jamie"

  Proof:
    parent("Alex", "Sam") is a fact.
    parent("Sam", "Jamie") is a fact.
```

Every answer is explained from what the search actually did. When a rule proves the answer, Sova shows that rule as written, the value each of its variables took, and how each of its goals was proved, nesting the same explanation for rules used inside rules. When a question is FALSE, Sova walks through each rule it tried, goal by goal. It shows each goal as it looked before it was tried, what it matched, and why the goal that failed couldn't be proved:

```text
ask grandparent("Sam", "Alex")

FALSE, because:

  Tried:
    grandparent(x, z) if parent(x, y) AND parent(y, z)

  First goal:
    parent("Sam", y)

    Matched:
      y = "Jamie"

  Second goal:
    parent("Jamie", "Alex")

    FAILED:
      No matching fact exists.
```

`--brief` prints just the answers.

Sova can also show how a rule could be written in a conventional language:

```text
$ ./sova --pseudocode 'ancestor("Ada", who)' examples/ancestor.sova

FUNCTION ancestor_given_x(x):
    # Returns every y where ancestor(x, y) is true.
    results ← empty list
    # rule ancestor, clause 1: ancestor(x, y) if parent(x, y)
    FOR EACH (v1, y) IN parent:
        IF v1 = x:
            IF y NOT IN results:
                ADD y TO results
    # rule ancestor, clause 2: ancestor(x, y) if parent(x, z) AND ancestor(z, y)
    FOR EACH (v1, z) IN parent:
        IF v1 = x:
            FOR EACH y IN ancestor_given_x(z):
                IF y NOT IN results:
                    ADD y TO results
    RETURN results

MAIN
    FOR EACH who IN ancestor_given_x("Ada"):
        PRINT who

DATA
    parent ← [("Ada", "Ben"), ("Ben", "Cleo"), ("Cleo", "Dev"), ("Dev", "Eli"), ... (1 more)]
```

How the pseudocode is built:

- Facts become data tables.
- Each rule becomes a function, shaped by which arguments are already known when it's called:
  - `all_ancestor()` when nothing is known
  - `ancestor_given_x(x)` when some arguments are known
  - `is_ancestor(x, y)` when every argument is known; it returns TRUE or FALSE
- `AND` becomes nested loops (for goals that find new values) and `IF`s (for goals that only check).
- Each extra clause or `OR` branch adds to the same results. A result is only added if it isn't already there, so each answer appears once, in the order it was first found, just like Sova's own answers.
- A rule that calls itself before doing anything else gets a warning, because it would loop forever.

The same translation is available as a runnable Python program:

```text
$ ./sova --python 'ancestor("Ada", who)' examples/ancestor.sova > ancestor.py
$ python3 ancestor.py
Ben
Fay
Cleo
Dev
Eli
```

And as a JavaScript program for Node.js:

```text
$ ./sova --javascript 'ancestor("Ada", who)' examples/ancestor.sova > ancestor.js
$ node ancestor.js
```

Both programs list every fact so they run on their own, and use a `seen` set to skip repeated answers quickly. JavaScript can't compare arrays with `===`, so when rows have several values the program includes two small helpers: `key(row)` turns a row into text, and `has(table, row)` checks whether a table contains a row. Names that would break the target language get a trailing `_`, such as keywords like `from` or `const`, or a variable named the same as a table.

The tests run the generated Python and JavaScript programs and check that they print the same answers as Sova, in the same order.

### Comparing paradigms

`./sova --compare TARGET FILE` shows a rule written three ways:

1. **Logic**, the Sova rule: it says what is true.
2. **Imperative** Python: it spells out every step with loops and ifs.
3. **Functional** Python: it describes the results with list comprehensions.

Each version comes with its line count. After them comes a table of how the ideas map, listing only the ideas that rule uses, and then Sova's answer. For example, `member` from `examples/club.sova` takes 4 lines in Sova, 10 imperative lines, and 4 functional lines:

```python
def all_member():
    """Return every x where member(x) is true."""
    return unique(
        # rule member: member(x) if age(x, a) AND a >= 18 AND NOT banned(x)
        [x for (x, a) in age if a >= 18 and x not in banned]
    )
```

You can also get the functional version on its own with `./sova --functional TARGET FILE`. It is tested the same way as the other translations.

## Architecture

Sova is designed around a modular interpreter architecture.

```text
Source Code
    |
    v
Lexer
    |
    v
Parser
    |
    v
Abstract Syntax Tree
    |
    v
Knowledge Base
    |
    v
Inference Engine
    |
    v
Proof / Execution Trace
    |
    +----> Result Engine
    |
    +----> Explanation Engine
    |
    +----> Learning Environment
              |
              +----> Pseudocode Generator
              +----> Language Translator
              +----> Interactive Tutor
              +----> Paradigm Comparator
```

## Technology

- **Bash:** Entire language implementation
- **Git:** Version control
- **ShellCheck:** Shell script analysis
- **Bash testing:** Automated interpreter tests

The project intentionally uses Bash to explore how much of a programming language implementation can be built using shell scripting.

## Development Roadmap

- [x] Lexer and tokenizer
- [x] Parser and syntax validation
- [x] Abstract syntax tree
- [x] Fact storage and knowledge base
- [x] Variables and unification
- [x] Rule evaluation
- [x] Inference engine
- [x] Query evaluation and backtracking
- [x] Proof trees and explanations
- [x] Numbers, comparisons, and `NOT`
- [x] Interactive prompt
- [x] Pseudocode generation
- [x] Python translation
- [x] JavaScript translation
- [x] Interactive learning environment (exercises with a checker)
- [x] Programming paradigm comparisons
- [x] Arithmetic (`m = n - 1`)
- [x] Lists and `[head | tail]` patterns
- [x] `collect` and `count`
- [x] Text built-ins (`concat`, `text_length`, `chars`)

## Language Reference

A program is a list of `fact`, `rule`, and `ask` lines. `#` starts a comment.

```text
fact parent("Ada", "Ben")          # something that is true
rule grandparent(x, z):            # true when every goal below is
    parent(x, y)
    AND parent(y, z)
ask grandparent("Ada", who)        # a question; who is filled in
```

| Values | |
|---|---|
| `"text"`, `42`, `-3` | constants (whole numbers only) |
| `x`, `who` | variables: any name starting with a letter or `_` |
| `[]`, `[1, 2, 3]` | lists |
| `[head \| tail]`, `[a, b \| rest]` | a list's first item(s) and the rest |

| Goals in a rule body | |
|---|---|
| `parent(x, y)` | a call to a fact or rule |
| `AND`, `OR` | join goals; `OR` binds loosest |
| `NOT p(x)` | true when `p(x)` can't be proved |
| `a > 18`, `x + 1 <= y`, `x != "Bob"` | comparisons: `<` `>` `<=` `>=` `==` `!=` |
| `m = n - 1` | calculation: `+ - * / %` and parentheses. Gives `m` a value, or checks it if `m` already has one. `/` and `%` round down. |
| `l = [h \| t]` | matching: takes a list apart, or builds one |
| `collect(c, parent(p, c), kids)` | `kids` is the list of `c` for every answer |
| `count(parent(p, c), n)` | `n` is the number of answers |
| `concat(a, b, c)` | `c` is text `a` followed by `b`; works backwards too |
| `text_length(t, n)` | `n` is the number of characters in `t` |
| `chars(t, l)` | `l` is the list of `t`'s characters, or `t` is `l` joined |

A rule with no goals is written as a fact with variables: `fact member(x, [x | rest])`.

The [examples](examples) folder shows each feature in use. See `math.sova` for factorial, Fibonacci, GCD, and Collatz, and `lists.sova` for length, append, reverse, sum, max, and insertion sort.

## How Queries Are Answered

- A quoted string (`"Alex"`) or a whole number (`17`, `-3`) is a constant; a bare name (`who`, `x`) is a variable. Numbers match by value, so `007` and `7` are the same.
- Sova searches depth-first and backtracks, like Prolog. For each goal it tries facts first, then rules in source order.
- A predicate can have several rules with the same name; each is an alternative (e.g. a base case and a recursive case).
- `OR` binds loosest: `a AND b OR c` means `(a AND b) OR c`.
- Each answer is shown once. Variables used only inside a rule are not shown.
- Rule heads can contain constants: `rule likes("Sam", food):` only applies to Sam.
- Comparisons (`a >= 18`, `x != "Bob"`) can appear in rule bodies. `<`, `>`, `<=`, `>=` compare numbers; `==` and `!=` compare numbers or text. Both sides need values first, so put the goal that sets a variable before the comparison that tests it.
- `NOT p(x)` is true when `p(x)` can't be proved (negation as failure). Like comparisons, its variables need values first. Otherwise Sova says so and answers `UNKNOWN` instead of guessing.
- Calculations need values for everything on the side being computed. Dividing by zero, or doing arithmetic on text, is an error, and the answer is `UNKNOWN`.
- `collect` and `count` look at the distinct answers to their inner question, in the order Sova finds them. If a variable in the inner question has no value yet but is needed later in the rule, Sova reports an error instead of quietly collecting over every value. Give it a value first, for example with `parent(p, someone) AND count(parent(p, c), n)`.
- The text built-ins are replaced by a program's own facts or rules with the same name.
- Sova warns when a predicate is used with different numbers of arguments, such as `parent/2` in one place and `parent/3` in another.
- If a fully known goal comes up again while it is still being proved (a cycle in a graph, or a rule like `knows(x, y) if knows(y, x)`), Sova doesn't try to prove it a second time, because the second attempt can never find a new answer.
- The search stops when rules are nested 200 calls deep, so a rule that calls itself forever gives `UNKNOWN` instead of hanging. Long computations are fine: the limit is on nesting, not on the number of steps. Set `SOVA_MAX_DEPTH` to change the limit.

## Exercises

Ten exercises build up the language one idea at a time. They start with facts and simple rules, move on to `AND`, `OR`, recursion, comparisons, `NOT`, arithmetic, and lists, and finish with `count` and `collect`.

```bash
./sova --exercises          # list them, with your progress
./sova --start 1            # copy exercise 1 into my-exercises/
./sova --check my-exercises/01-facts.sova
```

Each exercise explains its idea at the top, gives you the facts, and marks where to write. At the bottom are checks:

```text
hint "You need two parent goals."
expect grandparent("Ada", "Cy")                       # should be true
expect NOT grandparent("Ben", "Cy")                   # should be false
expect grandparent("Ada", who) gives "Cy", "Di", "Eli" # exactly these answers
```

`--check` marks each check as passing or failing. When one fails, it explains why:

- the goals that couldn't be proved, or an error like using a value before it is known
- the proof, when something is true that shouldn't be
- which answers are missing and which weren't expected

Then it shows the hints. When everything passes, it suggests `--compare` so you can see your rule written as code. `--start` never overwrites a copy you already have. Any file can use `expect` and `hint` lines, and a normal run ignores them.

## Interactive Prompt

`./sova -i FILE` loads a program without running its `ask` lines, then lets you type questions and add facts or rules:

```text
?- parent(who, "Jamie")
ask parent(who, "Jamie")

TRUE:
  who = "Sam"

  Because parent("Sam", "Jamie") is a fact.
?- fact parent("Jamie", "Kai")
  Added.
?- rule great(x, y):
..      grandparent(x, z)
..      AND parent(z, y)
..
  Added.
?- quit
```

`ask` and a trailing `?` are optional. Type `pseudocode ancestor("Ada", who)` to see a rule as pseudocode, `python ancestor("Ada", who)`, `functional …` or `javascript …` for a program (or `translate ancestor to python`), `compare ancestor` to see three paradigms side by side, `facts` to see everything Sova knows, and `help` for the commands.

## Running and Testing

```bash
./sova examples/ancestor.sova          # answer the queries, with proofs
./sova --brief examples/ancestor.sova  # answers only
./sova -i examples/family.sova         # interactive prompt (file optional)
./sova --pseudocode grandparent examples/family.sova   # rule as pseudocode
./sova --python grandparent examples/family.sova       # rule as a Python program
./sova --js grandparent examples/family.sova           # rule as a JavaScript program
./sova --functional grandparent examples/family.sova   # rule as Python comprehensions
./sova --compare 'member(who)' examples/club.sova      # logic vs. imperative vs. functional
./sova --tokens examples/family.sova   # show lexer tokens
./sova --ast examples/family.sova      # show the parsed AST
./sova --kb examples/family.sova       # show the knowledge base
tests/run_all.sh                       # run every test suite
shellcheck -x sova src/*.sh tests/*.sh # lint
```

## Project Structure

```text
sova/
├── sova
├── readme.md
├── src/
├── examples/
├── tests/
└── docs/
```

## Design Principles

**Explainability:** Every logical conclusion should be traceable to its supporting facts and rules.

**Accessibility:** Syntax and explanations should be approachable to beginners without sacrificing the underlying computer science.

**Independence:** Learning features should help users understand and independently implement solutions, rather than simply copy generated code.

**Determinism:** The core inference and explanation engines should work without external AI APIs.

**Extensibility:** The architecture should support additional language features and translation targets over time.

---

Sova is an independent experimental project exploring programming
