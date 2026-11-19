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
  Proof:
    grandparent("Alex", "Jamie")  [rule grandparent]
      parent("Alex", "Sam")  [fact]
      parent("Sam", "Jamie")  [fact]
  TRUE
```

Each answer comes with a proof tree: every goal is indented under the rule that needed it, and labeled with the fact or rule that proved it. When a query is FALSE, Sova lists the dead ends, meaning the goals nothing could match:

```text
ask grandparent("Sam", "Alex")
  FALSE
  Dead ends (no fact or rule matches):
    parent("Jamie", "Alex")
```

Sova aims to go beyond returning a result.

For example, users will eventually be able to request:

```text
explain
pseudocode grandparent
translate grandparent to python
```

These features will help users understand both the logical solution and how to implement it independently.

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
- [ ] Pseudocode generation
- [ ] Python translation
- [ ] JavaScript translation
- [ ] Interactive learning environment
- [ ] Programming paradigm comparisons

## How Queries Are Answered

- A quoted string (`"Alex"`) is a constant; a bare name (`who`, `x`) is a variable.
- Sova searches depth-first and backtracks, like Prolog. For each goal it tries facts first, then rules in source order.
- A predicate can have several rules with the same name; each is an alternative (e.g. a base case and a recursive case).
- `OR` binds loosest: `a AND b OR c` means `(a AND b) OR c`.
- Each answer is shown once. Variables used only inside a rule are not shown.
- The search stops at a depth of 100 steps, so a rule that calls itself forever gives `UNKNOWN` instead of hanging. Set `SOVA_MAX_DEPTH` to change the limit.

## Running and Testing

```bash
./sova examples/ancestor.sova          # answer the queries, with proofs
./sova --brief examples/ancestor.sova  # answers only
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