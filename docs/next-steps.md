# Sova: Where It Stands and What's Next

_Written 2026-11-18, after the Day 5 commit (`adfdef6`)._

## What Sova is

Sova is a small logic programming language, in the same family as Prolog, written entirely in Bash. You write **facts** (`parent("Alex", "Sam")`), **rules** (`grandparent(x, z)` holds if `parent(x, y) AND parent(y, z)`), and **questions** (`ask grandparent("Alex", "Jamie")`). Sova works out the answer and shows the reasoning that led to it.

There are two goals:

1. **A working language**: facts, rules, variables, unification, backtracking inference.
2. **A teaching tool**: proof trees, explanations of why a query failed, and eventually pseudocode and Python/JS translations, so learners understand the logic well enough to write it themselves.

## What works today

| Piece | File | Status |
|---|---|---|
| CLI (`./sova [--tokens\|--ast\|--kb] FILE`) | `sova` | Works |
| Lexer | `src/lexer.sh` | Works for simple input, but nothing else uses it (see below) |
| Parser → flat AST (`FACT` / `RULE` / `GOAL` / `ASK`) | `src/parser.sh` | Solid: handles comments, quoted strings, and good error messages |
| Knowledge base (dedupes facts, stores rules) | `src/knowledge_base.sh` | Works |
| Fact queries with variables | `match_fact` / `kb_ask` | Works: `ask parent(who, "Jamie")` → `who = "Sam"` |
| **Rule evaluation / inference** | n/a | **Not started.** `ask grandparent(...)` prints `UNKNOWN` |
| Tests | `tests/test_parser.sh` | 13/13 pass, but they cover the parser only |

So the front half of the pipeline (source → AST → KB) is done. The next milestone is the part that makes Sova a logic language: **the inference engine**.

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
- **Safety.** Add a depth limit (e.g. 200) and report `ERROR: depth limit reached` instead of letting Bash overflow its stack on left-recursive rules.
- **Answers.** Deduplicate solutions and only show bindings for the query's own variables.

Add these examples as you go:
- [ ] `examples/family.sova`: `grandparent` should return TRUE (this is the README's promise)
- [ ] `examples/ancestor.sova`: a recursive rule with two clauses
- [ ] `examples/or.sova`: a disjunction

### 4. Proof trees and `explain`

This is the feature that sets Sova apart, so build it right after inference works.

- [ ] Have the solver record which fact or rule satisfied each goal, as a tree that travels alongside the bindings.
- [ ] Print it in the README's `Proof: … Therefore: …` format, indented by depth for nested rules.
- [ ] **Explain failures:** for a FALSE query, report the first goal that had no match ("no fact `parent("Jamie", y)` exists"). It's simple to implement and very useful for learners.

### 5. Language features that will be missed quickly

- [ ] `NOT` (negation as failure)
- [ ] Numbers and comparisons (`age(x, a) AND a > 18`)
- [ ] Constants in rule heads (`rule likes("Sam", x):`). The parser currently rejects these.
- [ ] Arity checking: warn when `parent/2` and `parent/3` both appear
- [ ] An interactive REPL (`./sova -i file.sova` → `?- grandparent("Alex", who)`)

### 6. Learning environment (later)

Once proofs exist, these follow naturally from the rule AST:
- [ ] `pseudocode grandparent`: nested loops over facts, one loop per goal
- [ ] `translate grandparent to python`: a comprehension or generator over fact tuples
- [ ] JavaScript target, side-by-side paradigm comparisons, exercises

---

## Suggested near-term plan

| Day | Goal |
|---|---|
| 6 | Cleanup (step 1) + KB/query tests (step 2) |
| 7–8 | `unify` + renaming variables + recursive solver; `grandparent` returns TRUE |
| 9 | Multiple clauses, `OR`, depth limit; `ancestor` example passes |
| 10 | Proof trees + failure explanations |

**Definition of done for the next milestone:** `./sova examples/family.sova` prints exactly the `TRUE` + `Proof:` output shown in the README.
