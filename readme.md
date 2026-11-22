<p align="center">
  <img src="docs/logo/sova-logo.png" alt="Sova logo: an owl with a proof tree on its chest" width="200">
</p>

# Sova

**Think logically. Code independently.**

Sova is an experimental declarative programming language built in Bash, designed to make logical reasoning, programming, and problem-solving more accessible.

Rather than specifying every step a computer must execute, Sova allows programmers to define facts, relationships, rules, and goals. Its inference engine determines what conclusions can be derived and explains how it reached them.

Sova also aims to bridge the gap between declarative and conventional programming by teaching users how to translate logical solutions into pseudocode and other programming languages.

> **Project status:** Experimental, but the full pipeline works: parsing, inference with backtracking, explanations and traces, an interactive prompt, translations to pseudocode, Python, and JavaScript, and a set of exercises. The test suite has 489 tests.

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
- Importing facts and rules from other files
- Exact decimal arithmetic
- Printing and reading input from rules

### Explainable Execution
- Trace the reasoning behind query results
- Generate human-readable proof trees
- Identify which facts and rules contributed to a conclusion
- Explain unsuccessful queries

### Learning Environment
- Generate language-independent pseudocode
- Translate Sova logic into conventional programming languages
- Compare different programming paradigms
- Exercises with a checker that explains failing answers

## Quick Example

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

See [Reading the output](#reading-the-output) for what a FALSE answer looks like.

## Installation

Sova is a set of Bash scripts. There is nothing to compile.

### Quick install

One command downloads Sova to `~/.local/share/sova` and puts a `sova` command in `~/.local/bin`:

```bash
curl -fsSL https://raw.githubusercontent.com/soumil-voona/sova/main/install.sh | bash
```

If `~/.local/bin` isn't on your `PATH` yet, the installer prints the line to add to `~/.zshrc` or `~/.bashrc`. Then, from any folder:

```bash
sova myprogram.sova
```

Run the same command again to update. To uninstall:

```bash
curl -fsSL https://raw.githubusercontent.com/soumil-voona/sova/main/install.sh | bash -s -- --uninstall
```

You can change the folders with `SOVA_HOME` and `SOVA_BIN_DIR`, and pick a branch or tag with `SOVA_REF`. From a clone, `./install.sh` installs that copy without downloading anything.

The examples live in `~/.local/share/sova/examples`. The rest of this manual writes commands as `./sova` because that's how you run Sova from a clone; with the quick install, type `sova` instead. `sova --start N` puts exercises in a `my-exercises/` folder inside whichever folder you run it from.

The rest of this section covers installing by hand with a clone, which is what you want if you're working on Sova itself.

### Requirements

| Tool | Needed for | Notes |
|---|---|---|
| Bash 3.2 or newer | everything | macOS ships Bash 3.2, which works. Linux distributions ship Bash 4 or 5. On Windows, use WSL or Git Bash. |
| Standard Unix tools (`sed`, `awk`, `grep`, `sort`) | everything | Already present on macOS, Linux, and WSL. |
| Git | downloading and updating | Optional: you can download a ZIP instead. |
| Python 3 | running programs made by `--python`, `--functional`, `--compare` | Optional. Sova makes the program without Python; you only need Python to run it. |
| Node.js | running programs made by `--javascript` | Optional, same as Python. |
| ShellCheck | linting, if you work on Sova itself | Optional. |

To check what you have:

```bash
bash --version | head -1
```

```bash
python3 --version; node --version
```

### 1. Get the code

With Git:

```bash
git clone https://github.com/soumil-voona/sova.git
```

```bash
cd sova
```

Without Git, download the ZIP from the repository's GitHub page (**Code → Download ZIP**), unzip it, and `cd` into the folder.

### 2. Make the script executable

Git keeps the executable bit, but a ZIP download may lose it:

```bash
chmod +x sova
```

### 3. Try it

```bash
./sova examples/family.sova
```

You should see each question in `examples/family.sova` answered with `TRUE` or `FALSE` and an explanation. If you do, Sova is installed. `./sova` works from any folder, so `/path/to/sova/sova myprogram.sova` works too.

### 4. Run `sova` from anywhere (optional)

To type `sova` instead of `./sova` or the full path, do one of the following. The examples assume you cloned into `~/sova`, so change the path if you didn't.

**Option A: link it into a bin folder.** Sova follows the link back to its real folder, so a symlink works. To link it into `/usr/local/bin` (already on `PATH` on macOS and most Linux systems; may ask for your password):

```bash
sudo ln -s "$HOME/sova/sova" /usr/local/bin/sova
```

Or, without `sudo`, into `~/.local/bin` (this folder must be on your `PATH`):

```bash
mkdir -p ~/.local/bin && ln -s "$HOME/sova/sova" ~/.local/bin/sova
```

**Option B: add the Sova folder to your `PATH`.** Add this line to `~/.zshrc` (macOS) or `~/.bashrc` (Linux, WSL):

```bash
export PATH="$HOME/sova:$PATH"
```

Then open a new terminal, or run `source ~/.zshrc` (or `source ~/.bashrc`).

Either way, check it works from another folder:

```bash
cd ~ && sova --brief ~/sova/examples/family.sova
```

If you later move the Sova folder, update the link or the `PATH` line.

### 5. Check the installation (optional)

The test suite runs every part of Sova. It takes a few minutes:

```bash
tests/run_all.sh
```

Without Python 3 or Node.js, the translation suites print `[SKIP]` rather than fail.

### Updating

```bash
git pull
```

Your work in `my-exercises/` is not tracked by Git, so updating doesn't touch it.

### Uninstalling

Delete the `sova` folder, and remove the `PATH` line or the `sova` link if you added one (`rm /usr/local/bin/sova` or `rm ~/.local/bin/sova`). The only other thing Sova writes is the `my-exercises/` folder that `--start` makes, and that holds your own work.

## User Manual

1. [Your first program](#your-first-program)
2. [Command-line reference](#command-line-reference)
3. [Language reference](#language-reference)
4. [How queries are answered](#how-queries-are-answered)
5. [Reading the output](#reading-the-output)
6. [Watching the search](#watching-the-search)
7. [Interactive prompt](#interactive-prompt)
8. [Translating to other languages](#translating-to-other-languages)
9. [Comparing paradigms](#comparing-paradigms)
10. [Exercises](#exercises)
11. [Debugging views](#debugging-views)
12. [Environment variables](#environment-variables)
13. [Troubleshooting](#troubleshooting)

### Your first program

A Sova program is a plain text file, usually ending in `.sova`. Create `pets.sova`:

```text
# Facts: things that are true
fact owns("Maya", "Rex")
fact owns("Leo", "Tom")
fact dog("Rex")
fact cat("Tom")

# A rule: someone is a dog owner if they own something that is a dog
rule dog_owner(person):
    owns(person, pet)
    AND dog(pet)

# Questions
ask dog_owner("Maya")
ask dog_owner("Leo")
ask dog_owner(who)
```

Run it:

```bash
./sova pets.sova
```

Sova answers each `ask` line in order:

- `dog_owner("Maya")` is `TRUE`, with a proof: Maya owns Rex, and Rex is a dog.
- `dog_owner("Leo")` is `FALSE`, with an explanation: Leo owns Tom, but `dog("Tom")` has no matching fact.
- `dog_owner(who)` has a variable, so Sova finds every value that makes it true: `who = "Maya"`.

Quoted text (`"Maya"`) and numbers are values. Bare names (`person`, `pet`, `who`) are variables. Next, try `./sova --brief pets.sova` for answers only, `./sova --trace pets.sova` to watch the search, or `./sova -i pets.sova` to ask your own questions. The [examples](examples) folder has more programs to read and run.

### Command-line reference

```text
./sova [--brief] [--trace] FILE
./sova -i [--brief] [--trace] [FILE]
./sova --pseudocode | --python | --functional | --javascript TARGET FILE
./sova --compare TARGET FILE
./sova --exercises | --start N | --check FILE
./sova --tokens | --ast | --kb FILE
```

| Command | What it does |
|---|---|
| `./sova FILE` | Answer every `ask` in FILE, with a proof for each answer and an explanation for each FALSE. |
| `./sova --brief FILE` | Answers only, without proofs or explanations. |
| `./sova --trace FILE` | Show the search step by step before each answer. See [Watching the search](#watching-the-search). |
| `./sova -i [FILE]` | Load FILE (optional) without running its `ask` lines, then open the [interactive prompt](#interactive-prompt). Works with `--brief` and `--trace`. |
| `./sova --pseudocode TARGET FILE` | Show TARGET's rules as language-independent pseudocode. |
| `./sova --python TARGET FILE` | Print a runnable Python 3 program for TARGET. |
| `./sova --functional TARGET FILE` | Print a Python program written with list comprehensions. |
| `./sova --javascript TARGET FILE` | Print a runnable Node.js program. `--js` is short for `--javascript`. |
| `./sova --compare TARGET FILE` | Show TARGET as logic, imperative, and functional code side by side. |
| `./sova --exercises` | List the exercises and your progress. |
| `./sova --start N` | Copy exercise N into `my-exercises/` to work on. |
| `./sova --check FILE` | Run FILE's `expect` checks and explain any that fail. |
| `./sova --tokens FILE` | Show the lexer's tokens. |
| `./sova --ast FILE` | Show the parsed syntax tree. |
| `./sova --kb FILE` | Show the facts and rules Sova loaded. |

**TARGET** is either a predicate name, such as `grandparent`, or a call, such as `'ancestor("Ada", who)'`. With a call, the values you give shape the generated functions: `ancestor("Ada", who)` makes a function that takes `x` and returns every `y`. Put a call in single quotes so the shell keeps the double quotes.

Sova exits with status `0` on success and `1` on errors such as a missing file or a syntax error.

### Language reference

A program is a list of `fact`, `rule`, `ask`, and `import` lines. `#` starts a comment.

```text
fact parent("Ada", "Ben")          # something that is true
rule grandparent(x, z):            # true when every goal below is
    parent(x, y)
    AND parent(y, z)
ask grandparent("Ada", who)        # a question; who is filled in
import "family.sova"               # add another file's facts and rules
```

| Values | |
|---|---|
| `"text"`, `42`, `-3`, `2.5` | constants: text, whole numbers, and decimals |
| `x`, `who` | variables: any name starting with a letter or `_` |
| `[]`, `[1, 2, 3]` | lists |
| `[head \| tail]`, `[a, b \| rest]` | a list's first item(s) and the rest |

| Goals in a rule body | |
|---|---|
| `parent(x, y)` | a call to a fact or rule |
| `AND`, `OR` | join goals; `OR` binds loosest |
| `NOT p(x)` | true when `p(x)` can't be proved |
| `a > 18`, `x + 1 <= y`, `x != "Bob"` | comparisons: `<` `>` `<=` `>=` `==` `!=` |
| `m = n - 1` | calculation: `+ - * / %` and parentheses. Gives `m` a value, or checks it if `m` already has one. With whole numbers, `/` and `%` round down. See [Decimals](#decimals). |
| `l = [h \| t]` | matching: takes a list apart, or builds one |
| `collect(c, parent(p, c), kids)` | `kids` is the list of `c` for every answer |
| `count(parent(p, c), n)` | `n` is the number of answers |
| `concat(a, b, c)` | `c` is text `a` followed by `b`; works backwards too |
| `text_length(t, n)` | `n` is the number of characters in `t` |
| `chars(t, l)` | `l` is the list of `t`'s characters, or `t` is `l` joined |
| `print(a, b, ...)` | writes the values on one line, separated by spaces; text appears without quotes |
| `read(line)` | reads one line of input as text; false when there is no more input |
| `read_number(n)` | reads one line of input as a number (`42` or `2.5`) |

A rule with no goals is written as a fact with variables: `fact member(x, [x | rest])`.

`import "FILE"` adds the facts and rules of another file at that point, as if they were written there. The file's own `ask`, `expect`, and `hint` lines are skipped, so a file can be a library and still run as a program of its own. A relative path is looked up from the folder of the file that has the `import`, not the folder you run `sova` from. Each file is read once, so two files may import each other. At the interactive prompt, `import` paths are relative to the file you loaded, or to the current folder if you didn't load one. See `examples/relatives.sova`.

#### Decimals

A number with a point, like `2.5` or `-0.75`, is a decimal. Sova works decimals out exactly, so `0.1 + 0.2` is `0.3`. A decimal needs a digit before the point (`0.5`, not `.5`).

- When either value is a decimal, the result is a decimal, written with at least one digit after the point: `2.5 * 2` is `5.0`.
- `/` with a decimal divides exactly, rounded to 10 decimal places: `1 / 4.0` is `0.25` and `1 / 3.0` is `0.3333333333`. With two whole numbers it still rounds down, as before: `7 / 2` is `3`. To divide whole numbers exactly, write one as a decimal: `7 / 2.0` is `3.5`.
- `%` gives what is left after rounding the quotient down: `7.5 % 2` is `1.5`.
- Comparisons go by value: `5 == 5.0`, `2.5 < 3`, and `10 = x * 2` (when `x` is `5.0`) are all true.
- In facts and rule heads, `5` and `5.0` are different values, so `size(5.0)` doesn't match `fact size(5)`. Compare them with `==` instead.
- A decimal can have up to 18 digits. A calculation that needs more is an error, and the answer is UNKNOWN.

See `examples/shop.sova`.

#### Input and output

`print`, `read`, and `read_number` let a rule talk to the person running it:

```text
rule greet(name):
    print("What's your name?")
    AND read(name)
    AND concat("Nice to meet you, ", name, message)
    AND print(message)
```

- Input comes from the terminal as you type it, or from a file: `./sova examples/greeter.sova < examples/greeter.input`. At the interactive prompt, `read` takes the next line you type.
- Printed lines appear right after the `ask` line, before the answer.
- They run each time the search reaches them. A goal that is tried again, for another answer or after a later goal fails, prints or reads again. Put `print` after the goals that pick an answer if you want it printed once per answer.
- `read` and `read_number` are false at the end of the input. `read_number` on a line that isn't a number is an error, and the answer is UNKNOWN.

See `examples/greeter.sova`.

The [examples](examples) folder shows each feature in use. See `math.sova` for factorial, Fibonacci, GCD, and Collatz, and `lists.sova` for length, append, reverse, sum, max, and insertion sort.

### How queries are answered

- A quoted string (`"Alex"`) or a number (`17`, `-3`, `2.5`) is a constant; a bare name (`who`, `x`) is a variable. Numbers are written in a standard form before matching, so `007` and `7` are the same, and so are `2.50` and `2.5`.
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

### Reading the output

Answers come out as `TRUE`, `FALSE`, or `UNKNOWN` (when Sova can't decide, for example because of an error). A question with variables lists every set of values that makes it true.

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

Output is colored when it goes to a terminal: `TRUE` in green, `FALSE` and errors in red, `UNKNOWN` and warnings in yellow. Piped or saved output stays plain, and translated programs are never colored. See [Environment variables](#environment-variables) to change this.

### Watching the search

An explanation shows the finished proof. `--trace` shows how Sova found it, step by step: each goal as Sova starts on it, the fact or rule it tries, what that matches, the dead ends, and each time it goes back to try another option. With these facts and the `grandparent` rule:

```text
fact parent("Sam", "Jamie")
fact parent("Sam", "Alex")
fact parent("Alex", "Ben")
```

`./sova --trace` prints this before the usual answer and explanation:

```text
ask grandparent("Sam", who)

Trace:
  [1] grandparent("Sam", who)
      Try rule grandparent(x, z) if parent(x, y) AND parent(y, z)
      matches, with x = "Sam", z = who
      [2] parent("Sam", y)
          2 options: 2 facts match
          Try fact parent("Sam", "Jamie"): matches, with y = "Jamie"
      [3] parent("Jamie", z)
          ✗ No matching fact exists.
      ↩ Back to [2] parent("Sam", y): option 2 of 2
          Try fact parent("Sam", "Alex"): matches, with y = "Alex"
      [4] parent("Alex", z)
          Try fact parent("Alex", "Ben"): matches, with z = "Ben"
  ✓ Answer 1: who = "Ben"
  Search finished: 1 answer, 4 goals tried.
```

Goals are numbered and indented by how deeply they sit inside rules. `NOT`, `collect`, and `count` show the search they run inside them. After an answer, the trace keeps going, because Sova goes back to look for more. A trace stops printing after 300 goals (set `SOVA_TRACE_LIMIT` for more), but the search itself finishes. At the prompt, type `trace` before a question.

### Interactive prompt

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

`ask` and a trailing `?` are optional. Put `trace` in front of a question to watch the search step by step. Type `pseudocode ancestor("Ada", who)` to see a rule as pseudocode, `python ancestor("Ada", who)`, `functional …` or `javascript …` for a program (or `translate ancestor to python`), `compare ancestor` to see three paradigms side by side, `facts` to see everything Sova knows, and `help` for the commands.

| Prompt command | What it does |
|---|---|
| `parent(who, "Sam")` | Ask a question. `ask` in front and `?` at the end are optional. |
| `trace parent(who, "Sam")` | Ask, showing each step of the search first. |
| `fact parent("A", "B")` | Add a fact. |
| `import "lib.sova"` | Add the facts and rules from another file. |
| `rule r(x):` | Add a rule. Type its body lines, then an empty line to finish. |
| `pseudocode ancestor` | Show a predicate as pseudocode. A call like `ancestor("Ada", who)` works too. |
| `python ancestor` | The same as a Python program. Also `translate ancestor to python`. |
| `javascript ancestor` | The same as a JavaScript program. Also `js ancestor`. |
| `functional ancestor` | The same as Python list comprehensions. |
| `compare ancestor` | Logic vs. imperative vs. functional code. |
| `facts` | Show everything Sova knows. |
| `help` | List these commands. |
| `quit` | Leave. |

What you add at the prompt is kept only for that session. To keep it, add the lines to your `.sova` file.

### Translating to other languages

Sova can show how a rule could be written in a conventional language:

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

Some built-ins need a helper in the generated program, which is written out above the functions:

- `read` and `read_number` become `read_line()` and `read_number()` (`readLine()` and `readNumber()` in JavaScript), which give `None` (`null`) at the end of the input.
- In a program with decimals, `/` becomes `divide(a, b)`, which rounds down for whole numbers and divides exactly otherwise.

Python and JavaScript use floating-point numbers rather than exact decimals, so `0.1 + 0.2` is `0.30000000000000004` there. JavaScript also has only one kind of number, so it prints `5.0` as `5`, and treats a value like `5.0` from a fact as a whole number when dividing.

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

### Exercises

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

### Debugging views

These show what Sova sees at each stage, which helps when a program doesn't behave as expected:

```bash
./sova --tokens examples/family.sova   # the words and symbols the lexer finds
./sova --ast examples/family.sova      # the parsed program: FACT, RULE, GOAL, ASK lines
./sova --kb examples/family.sova       # every fact and rule in the knowledge base
```

`--kb` is the quickest way to check that a fact was read the way you meant it. At the interactive prompt, `facts` does the same.

### Environment variables

| Variable | Default | Effect |
|---|---|---|
| `SOVA_MAX_DEPTH` | `200` | How deeply rules may nest before the search gives up with `UNKNOWN`. Raise it for deep recursion. |
| `SOVA_TRACE_LIMIT` | `300` | How many goals `--trace` prints before it stops printing. The search itself still finishes. |
| `SOVA_COLOR` | `auto` | `always` or `never` to force colored output on or off. `auto` colors only when writing to a terminal. |
| `NO_COLOR` | unset | Set to anything to turn color off. |
| `SOVA_EXERCISE_DIR` | `./my-exercises` | Where `--start` copies exercises and `--exercises` looks for your progress. |

Set one for a single run by putting it before the command:

```bash
SOVA_MAX_DEPTH=1000 ./sova examples/math.sova
```

### Troubleshooting

| You see | Cause and fix |
|---|---|
| `permission denied: ./sova` | The script isn't executable. Run `chmod +x sova`. |
| `src/color.sh: No such file or directory` | Sova can't find its `src/` folder. This happens if `sova` was copied out of its folder rather than linked, or if the Sova folder was moved after you made a link. Remove the copy or old link and link it again, as shown in [Installation](#4-run-sova-from-anywhere-optional). |
| `command not found: sova` | The Sova folder isn't on your `PATH`. Use `./sova` from the folder, or see [Installation](#4-run-sova-from-anywhere-optional). |
| `Missing file path` | Give a `.sova` file to run, such as `./sova examples/family.sova`. |
| `Syntax error on line N: …` | Line N doesn't parse. Check for a missing comma between arguments, a missing `:` after a rule head, or unclosed quotes. |
| `Syntax error in FILE, line N: …` | The same, in a file brought in by `import`. |
| `'read_number(n)' read "…", which isn't a number` | The input line wasn't a number. Numbers look like `42`, `-3`, or `2.5`. |
| The program waits and prints nothing | A rule is reading input. Type a line and press Enter, or give the input in a file with `< input.txt`. |
| `FALSE` with `There is no more input to read.` | `read` reached the end of the input. Give the program more lines. |
| A fact with `5` doesn't match `5.0` | In facts, a whole number and a decimal are different values. Use `==` to compare them by value. |
| `can't import 'FILE': no such file` | The path is looked up from the folder of the file with the `import` line. Check the spelling, and use `../` to go up a folder. |
| A warning that a predicate is used with different numbers of arguments | Something like `parent("A", "B")` in one place and `parent("A")` in another. Usually a typo. |
| `UNKNOWN` from a comparison, `NOT`, or a calculation | A variable had no value yet when it was needed. Move the goal that gives it a value earlier in the rule body. |
| `UNKNOWN` from a recursive rule | The rule nested more than 200 calls deep. Make sure it has a base case, or that the recursive call isn't the first goal. For deep but finite recursion, raise `SOVA_MAX_DEPTH`. |
| `FALSE` when you expected `TRUE` | Read the explanation: it shows the goal that failed. Check spelling and capitalization: `"alex"` and `"Alex"` are different values. |
| Translation tests print `[SKIP]` | `python3` or `node` isn't installed. That's fine unless you're working on the translators. |
| Escape codes like `[32m` in saved output | Color was forced on. Unset `SOVA_COLOR`, or set `SOVA_COLOR=never`. |

## Development

```bash
tests/run_all.sh                       # run every test suite (a few minutes)
tests/run_all.sh test_rules test_trace # run only some suites
shellcheck -x install.sh sova src/*.sh tests/*.sh # lint
```

CI runs ShellCheck and the full test suite on Ubuntu and on macOS with the system Bash 3.2 for every push and pull request. Set `SOVA_TEST_STRICT=1` to make the translation suites fail, rather than skip, when `python3` or `node` is missing.

## Architecture

Sova is designed around a modular interpreter architecture.

```text
Source Code ------> Lexer (--tokens view only)
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
              +----> Exercise Checker
              +----> Paradigm Comparator
```

The parser reads source text directly. The lexer is kept as a debugging and teaching view (`--tokens`) and is not part of the main pipeline.

## Technology

- **Bash:** Entire language implementation. It runs on Bash 3.2 (the version macOS ships), so it avoids associative arrays and other Bash 4 features.
- **ShellCheck:** Shell script analysis
- **Bash testing:** Automated interpreter tests. The translation tests also need `python3` and `node`; without them those suites print `[SKIP]`.
- **GitHub Actions:** Runs the tests and ShellCheck on every push and pull request (`.github/workflows/ci.yml`)

The project intentionally uses Bash to explore how much of a programming language implementation can be built using shell scripting.

## Project Structure

```text
sova/
├── sova              # the command-line entry point
├── readme.md
├── src/              # lexer, parser, knowledge base, inference, explanations,
│                     # trace, translators, exercise checker
├── examples/         # example programs and their expected output
├── exercises/        # the ten exercises (--start copies them to my-exercises/)
├── tests/            # test suites, run by tests/run_all.sh
├── docs/             # roadmap and design notes
└── .github/workflows # continuous integration
```

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
- [x] Step-by-step search trace (`--trace`)
- [x] Continuous integration (tests and ShellCheck on every push and pull request)
- [x] Regression and stress tests (deep recursion, large knowledge bases, repeated answers, backtracking)
- [x] Faster loading of large programs (3,000 facts load in about a second)
- [x] Importing other files (`import "family.sova"`)
- [x] Decimals (`2.5`), worked out exactly
- [x] Input and output from rules (`print`, `read`, `read_number`)

See [docs/next-steps.md](docs/next-steps.md) for the full history and plans.

## Design Principles

**Explainability:** Every logical conclusion should be traceable to its supporting facts and rules.

**Accessibility:** Syntax and explanations should be approachable to beginners without sacrificing the underlying computer science.

**Independence:** Learning features should help users understand and independently implement solutions, rather than simply copy generated code.

**Determinism:** The core inference and explanation engines should work without external AI APIs.

**Extensibility:** The architecture should support additional language features and translation targets over time.

---

Sova is an independent experimental project exploring programming languages, logic, and how people learn to reason about code.
