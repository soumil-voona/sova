# Sova: Where It Stands and What's Next

_Started 2026-11-18, after the Day 5 commit (`adfdef6`). Last updated 2026-11-21. Steps 1 to 6 below are the original plan, kept with their checkboxes as a record. Current work is under [What's next](#whats-next)._

## What Sova is

Sova is a small logic programming language, in the same family as Prolog, written entirely in Bash. You write **facts** (`parent("Alex", "Sam")`), **rules** (`grandparent(x, z)` holds if `parent(x, y) AND parent(y, z)`), and **questions** (`ask grandparent("Alex", "Jamie")`). Sova works out the answer and shows the reasoning that led to it.

There are two goals:

1. **A working language**: facts, rules, variables, unification, backtracking inference.
2. **A teaching tool**: proof trees, explanations of why a query failed, and eventually pseudocode and Python/JS translations, so learners understand the logic well enough to write it themselves.

## What works today

| Piece | File | Status |
|---|---|---|
| CLI (`./sova` with `--brief`, `--trace`, `-i`, translations, exercises, debug views) | `sova` | Works from any directory |
| Lexer | `src/lexer.sh` | Quote-aware; used only by the `--tokens` view |
| Parser → flat AST (`FACT` / `RULE` / `GOAL` / `ASK`, plus `expect` / `hint`) | `src/parser.sh` | Works |
| Knowledge base (dedupes facts, indexes by predicate and first argument, arity warnings) | `src/knowledge_base.sh` | Works |
| Inference: unification, renaming, depth-first search with backtracking, cycle skipping, depth limit | `src/inference.sh` | Works |
| Built-ins: comparisons, arithmetic, lists, `NOT`, `collect`, `count`, text | `src/arith.sh`, `src/builtins.sh`, `src/terms.sh` | Works |
| Explanations and trace | `src/explain.sh`, `src/trace.sh` | Works |
| REPL | `src/repl.sh` | Works |
| Pseudocode, Python, functional Python, JavaScript, paradigm comparison | `src/pseudocode.sh`, `src/compare.sh` | Works; translations are tested by running them |
| Exercises and checker | `src/exercises.sh`, `src/check.sh`, `exercises/` | Ten exercises, each with a tested reference solution |
| Tests | `tests/` | 21 suites, run by `tests/run_all.sh`, also in CI |

---

## Next steps, in order

### 1. Quick cleanup (an afternoon)

- [x] **Update the README roadmap.** Every checkbox is still unchecked, but the lexer, parser, AST, knowledge base, and fact queries are all done.
- [x] **Make `./sova` work from any directory.** It runs `source ./src/...`, so it breaks unless you `cd` into the repo first. Resolve paths from the script's own location:
  ```bash
  SOVA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  source "$SOVA_DIR/src/lexer.sh"
  ```
- [x] **Decide what the lexer is for.** The parser does its own string handling and never calls `tokenize_file`. The lexer also mishandles quoted strings: `"Alex Smith"` becomes two identifiers, and a `#` inside a string gets treated as a comment. Pick one:
  - (recommended) Keep it as a `--tokens` debugging view and make it quote-aware (add a `STRING` token type). It's also a good teaching aid.
  - Or rewrite the parser to consume its tokens. That's more "proper," but it's a big refactor for little benefit right now.
- [x] **Run ShellCheck** on `sova` and `src/*.sh`, and add a `tests/run_all.sh`.

### 2. Tests for the knowledge base and queries

Write these **before** building inference, so you'll notice if something breaks.

- [x] `tests/test_kb.sh`: duplicate facts are dropped, rules and their goals are grouped correctly, and `--kb` output is right.
- [x] `tests/test_query.sh`: ground TRUE/FALSE, single-variable binding, a repeated variable (`ask same(x, x)`), arity mismatch, and multiple answers.
- [x] **Golden-output tests:** run `./sova examples/*.sova` and diff the output against `examples/*.expected`. This scales well once proofs exist.

### 3. Inference engine: rule evaluation with backtracking (the core milestone)

This is the most important step. Some design decisions are worth settling first:

- **Representing bindings.** You'll need a substitution, meaning a map from variables to values, that you can pass along and extend. In Bash, the simplest option is a string like `x="Alex"<US>y="Sam"` that you copy at each choice point (copying makes backtracking automatic), or an associative array that you save and restore. **Note:** macOS ships Bash 3.2, which has no associative arrays (`declare -A`), so the string approach is the portable choice.
- **Unification.** Generalize `match_fact` into `unify term1 term2 subst`, where *both* sides may contain variables. Rule-to-rule calls need this, not just query-to-fact.
- **Renaming variables.** Every time a rule is used, rename its variables (`x` → `x_7`). Otherwise recursive rules like `ancestor` mix up their own variables.
- **Search strategy.** Depth-first and left-to-right, like Prolog: for each goal, try matching facts, then matching rule clauses, and recurse on the remaining goals. Bash functions can recurse, so the call stack does the backtracking for you. Collect solutions in a global array.
- **AND/OR precedence.** The parser accepts mixed `AND`/`OR` but defines no precedence. Recommendation: **`OR` binds loosest**, so the body becomes alternatives, each one an `AND` chain. Document this in the README.
- **Multiple clauses.** Allow several `rule ancestor(x, z):` definitions; each is a separate alternative. `KB_RULES` already supports this. Just make sure goal grouping uses the rule's index, not its name. (It already does.)
- **Safety.** Add a depth limit (done: 100, since cost grows with the square of the depth in Bash) and report `ERROR: depth limit reached` instead of letting Bash overflow its stack on left-recursive rules.
- **Answers.** Deduplicate solutions and only show bindings for the query's own variables.

Add these examples as you go:
- [x] `examples/family.sova`: `grandparent` should return TRUE (this is the README's promise)
- [x] `examples/ancestor.sova`: a recursive rule with two clauses
- [x] `examples/or.sova`: a disjunction

### 4. Proof trees and `explain`

This is the feature that sets Sova apart, so build it right after inference works.

- [x] Have the solver record which fact or rule satisfied each goal, as a tree that travels alongside the bindings.
- [x] Print it in a readable format, indented by depth for nested rules. (Replaced on 2026-11-20 by the explanation format: `TRUE, because:` with the rule used, its variable bindings, and the proof of each goal. See `src/explain.sh`.)
- [x] **Explain failures** (now a goal-by-goal walk through each rule tried, with what matched and why the failing goal failed): for a FALSE query, report the first goal that had no match ("no fact `parent("Jamie", y)` exists"). It's simple to implement and very useful for learners.
- [x] **Trace mode** (done 2026-11-21): `--trace`, or `trace` at the prompt, prints the search as it runs. It shows each numbered goal, the fact or rule tried and what it matched, dead ends, and `↩ Back to [n]` when Sova returns to another option. `NOT`, `collect`, and `count` show their inner searches. It stops printing after `SOVA_TRACE_LIMIT` (300) goals. See `src/trace.sh`.

### 5. Language features that will be missed quickly

- [x] `NOT` (negation as failure)
- [x] Numbers and comparisons (`age(x, a) AND a > 18`), integers only since Bash arithmetic has no decimals
- [x] Constants in rule heads (`rule likes("Sam", x):`)
- [x] Arity checking: warn when `parent/2` and `parent/3` both appear
- [x] An interactive REPL (`./sova -i file.sova` → `?- grandparent("Alex", who)`)

### 5b. A complete language (done 2026-11-19)

- [x] **Checked the engine on real programs:** cycles, map coloring, a logic puzzle, and 400-step chains. Several fixes came out of it:
  - Variable lookup was quadratic in Bash. It now uses `${s%%pattern*}` instead of `${s#*pattern}`.
  - The solver uses an explicit stack instead of recursion.
  - Facts are indexed by predicate, and by their first argument.
  - A fully known goal that repeats while it's still being proved is skipped, so cycles and symmetric rules finish.
  - The depth limit now counts how deeply rules are nested (200), not the number of steps.
- [x] **Arithmetic:** `+ - * / %`, parentheses, and precedence, with `/` and `%` rounding down. `=` gives a value or checks one. Translated to assignments in every language.
- [x] **Lists:** `[]`, `[1, 2]`, and `[h | t]`, stored as unchangeable cells. Translated with list patterns (`isinstance` / `Array.isArray` checks, slices).
- [x] **`collect` and `count`:** they report an error when the gathered-over variable is needed later.
- [x] **Text built-ins:** `concat` (works in every direction), `text_length`, and `chars`.
- Still missing: decimals (Bash arithmetic has none), reading input or printing from rules, and importing other files.

### 6. Learning environment (later)

Once proofs exist, these follow naturally from the rule AST:
- [x] `pseudocode grandparent`: `./sova --pseudocode TARGET FILE`, or `pseudocode` at the prompt. Each rule becomes a function shaped by which arguments are known (`all_`, `_given_`, `is_`), and facts become data tables
- [x] `translate grandparent to python`: `./sova --python TARGET FILE`, or `python` / `translate ... to python` at the prompt. Built from the same logic as the pseudocode, and tested by running the Python and comparing its answers with Sova's
- [x] JavaScript target: `./sova --javascript TARGET FILE` (or `--js`), and `javascript` / `js` / `translate ... to javascript` at the prompt. Tested by running with Node and comparing with Sova's answers, using the same cases as Python
- [x] Side-by-side paradigm comparisons: `./sova --compare TARGET FILE` shows logic, imperative Python, and functional Python (list comprehensions, also `--functional`), with line counts and a table of how the ideas map
- [x] Exercises: ten in `exercises/`, from facts to `count`/`collect`. `--check` explains failures (dead ends, proofs, missing and unexpected answers, hints), and `--exercises` and `--start` manage your copies. Every exercise has a reference solution in `tests/exercise_solutions/` that the tests check.

---

## What's next

### 1. Trace mode
Done 2026-11-21 (see step 4).

### 2. Documentation cleanup
Done 2026-11-21. The "What works today" table and README now match the code. The README's project status, architecture diagram (the lexer is only the `--tokens` view), feature list, project layout, and roadmap were brought up to date, and its last sentence, which was cut off, was finished.

### 3. Continuous integration
Done 2026-11-21. `.github/workflows/ci.yml` runs ShellCheck and the full test suite on pushes to `main` and on pull requests, on Ubuntu and on macOS (Bash 3.2). CI sets `SOVA_TEST_STRICT=1`, so a translation suite that skips because `python3` or `node` is missing fails the run.

### 4. Regression and stress testing
Done 2026-11-21. `tests/test_stress.sh` covers recursion close to the depth limit, a raised `SOVA_MAX_DEPTH`, a knowledge base with thousands of facts, answers that are reached by many paths and must appear once, and heavy backtracking (permutations and 4-queens).

What it found: loading was the slow part for big programs, not the search. The parser started a subshell (`$(trim ...)`) for nearly every line, and `kb_load` compared each new fact with every earlier one to drop duplicates. About 1,500 facts took 10 seconds to load and 3,000 took 23 seconds. Fixed in step 5.

### 5. Faster loading of large programs
Done 2026-11-21.
- `src/parser.sh` and `parse_side` in `src/arith.sh` use `trim_to`, `strip_comment_to`, and `join_args_to`, which set a variable (`TRIMMED`, `STRIPPED`, `JOINED`) instead of printing, so no subshell is started per line. `split_args` and `strip_comment_to` skip the character-by-character loop when the text has no quotes, brackets, or parentheses. The printing versions are still there for the other files.
- `kb_load` drops duplicate facts with one `awk '!seen[$0]++'` pass, which keeps the first of each in order. Bash 3.2 has no associative arrays.
- `record_solution` found repeated answers by looping over every earlier one, which made `count` and `collect` over thousands of answers slow. It now checks one string of every answer seen so far (`SOLUTION_SEEN`), which is reset, saved, and restored along with `SOLUTIONS`.

Results: 3,000 facts load in 1.25 seconds instead of 23. A 3,000-fact program that counts every edge runs in 6.5 seconds instead of 60. The stress test now loads 3,200 fact lines.

### 6. Language gaps
Decimals, reading input and printing from rules, and importing other files.
