# Clime User Guide: How to write rules for the Nomicron climate system

Welcome to the Clime User Guide! This document is designed for Nomicron players and administrators who need to write or understand the rules that automatically manage the game's climate. The language is built to be as close to plain English as possible, making it easy to read and reducing the chance of accidental typos. Source files for the language use the `.rules` extension.

## 1. What Are Rules?

The climate system updates at the end of every turn based on a sequence of rules. These rules run in a specific order:

1. **Climate Rules:** These run first and are primarily responsible for changing the numeric climate value (and other numerical data).
2. **Tag Rules:** These run second and are responsible for adding or removing descriptive tags (like "Mild" or "Windy").

Every rule does two things: it checks if certain **conditions** are met, and if they are, it performs **actions**.

## 2. Anatomy of a Rule

A rule always starts with its type (`climate rule` or `tag rule`) followed by its name in quotes. After that, the `when` section lists the conditions, and the `then` section lists the actions.

You can also add **comments** anywhere in your rules (except in the middle of multi-word keywords) by wrapping them in square brackets `[ like this ]`. The system completely ignores comments, so they are a great way to explain what a rule is doing. Note that while the examples in this guide often show comments on their own lines for readability, they can also appear anywhere within a line.

Here is a simple example:

```text
climate rule "Greenhouse Warming"
[ This rule triggers when the greenhouse effect is active ]
when
  climate.tags includes "Greenhouse Effect"
  proposals.passed >= 3
then
  new.climate.value is increased by 2
```

## 3. Environments: Where Data Lives

Rules read and change data. To keep things organized, data is grouped into "namespaces" (think of them as folders).

* **`climate.` (Read-Only):** This is the state of the climate *before* any rules run this turn. You can look at `climate.value` or `climate.tags`, but you cannot change them directly.
* **`proposals.` (Read-Only):** This contains information about the end-of-turn report, such as `proposals.count`, `proposals.passed`, and `proposals.failed`.
* **`new.` (Changeable):** This is the data you *can* change. When you want to update the climate, you apply your changes to `new.climate.value` or `new.climate.tags`.
* **`var.` (Variables):** This is your scratchpad. If you need to keep track of a temporary value while your rules run, you use a variable. Variables automatically start at `0` (or empty), but you must tell the system what type of data the variable holds by starting its name with a specific prefix:
  * `var.n.` for a number (e.g., `var.n.counter`)
  * `var.b.` for a true/false boolean (e.g., `var.b.is_active`)
  * `var.s.` for a string of text (e.g., `var.s.message`)
  * `var.l.` for a tag list (e.g., `var.l.temp_tags`)
* **Future Namespaces (e.g., `weather.`):** Future additions to the system might introduce new namespaces. You can read them (e.g., `weather.wind_speed`) and, if permitted, modify them using the `new.` prefix (e.g., `new.weather.wind_speed`).

## 4. Types of Data

The system understands four types of data:

* **Numbers:** Standard numbers like `5`, `-10`, or `3.14`.
* **Booleans (True/False):** Logical states represented by `true` or `false`.
* **Strings (Text):** Text wrapped in quotes, like `"Windy"`.
* **Tag Lists:** A collection of unique tags separated by commas, like `"Mild", "Windy"`.
  * *Important:* If you need to create a list that contains exactly one tag, add a comma at the end: `"Mild",`. If the list is empty, use the keyword `empty`.

## 5. Writing Conditions (`when`)

The `when` section acts as a gatekeeper. You use comparisons to evaluate data:

* **Math Comparisons:** `=`, `!=` (not equal), `<`, `<=`, `>`, `>=`, and range comparisons like `10 < climate.value <= 20`.
* **Tag Checks:** You can look for tags inside tag lists using clean English phrases:
  * *target* `includes` *tag* (checks if a **single** tag is present)
  * *target* `includes any of` *list* (checks if at least one tag from a **tag list** is present)
  * *target* `includes all of` *list* (checks if every single tag from a **tag list** is present)
  * *target* `excludes` *tag*, *target* `excludes any of` *list*, and *target* `excludes all of` *list* function identically but verify that the tags are missing.
* **Function Checks:** You can also ask more complex questions using functions, such as: `climate.tags.has("Mild")` (Does the climate currently have the Mild tag?)
* **Combining Conditions:** Use `and` (both must be true), `or` (at least one must be true), and `not` (reverses the truth).

**Listing Multiple Conditions:**
You can just list conditions on separate lines. If you do, the system automatically treats them as if they have an `and` between them.

## 6. Writing Actions (`then`)

The `then` section modifies data. To ensure the system always knows exactly what type of data you are updating, each data type requires specific phrasing:

* **For Numbers:** You can use *target* `is` *value*, *target* `is increased by` *value*, or *target* `is decreased by` *value*.
* **For Booleans and Strings:** You can **only** use *target* `is` *value*.
* **For Tag Lists:** You can use *target* `is` *list*, *target* `includes` *tags* (or `include`), and *target* `excludes` *tags* (or `exclude`).
  * To make rules more compact, you can chain tag list modifications on the same line using `and`: *target* `includes "warming" and excludes "cooling"`

## 7. Example Set of Rules

Here is a complete set of example rules demonstrating how the language coordinates a complex end-of-turn cycle:

```text
climate rule "not enough activity"
when
  proposals.count < 5
  [ If there are very few proposals... ]
then
  [ ...the climate drops based on the shortfall. ]
  new.climate.value is decreased by 5 - proposals.count

climate rule "disagreements cause heated discussions"
when
  proposals.count >= 5
  [ If there are plenty of proposals... ]
  proposals.failed > proposals.passed
  [ ...but more failed than passed... ]
then
  [ ...the climate heats up from the arguments. ]
  new.climate.value is increased by proposals.failed - proposals.passed

climate rule "agreement makes everything calm down (warm climate cooling)"
when
  proposals.count >= 5
  proposals.passed > proposals.failed
  [ If more proposals pass than fail... ]
  new.climate.value > proposals.passed - proposals.failed
  [ ...and the climate is currently very warm... ]
then
  [ ...the climate cools down toward zero. ]
  new.climate.value is decreased by proposals.passed - proposals.failed

climate rule "agreement makes everything calm down (warm climate becomes neutral)"
when
  proposals.count >= 5
  proposals.passed > proposals.failed
  new.climate.value <= proposals.passed - proposals.failed
  [ ...and the climate is only slightly warm... ]
then
  [ ...it settles perfectly at neutral zero. ]
  new.climate.value is 0

climate rule "agreement makes everything calm down (cool climate warming)"
when
  proposals.count >= 5
  proposals.passed > proposals.failed
  new.climate.value < -(proposals.passed - proposals.failed)
  [ ...and the climate is currently very cold... ]
then
  [ ...the climate warms up toward zero. ]
  new.climate.value is increased by proposals.passed - proposals.failed

climate rule "agreement makes everything calm down (cool climate becomes neutral)"
when
  proposals.count >= 5
  proposals.passed > proposals.failed
  new.climate.value >= -(proposals.passed - proposals.failed)
  [ ...and the climate is only slightly cold... ]
then
  [ ...it settles perfectly at neutral zero. ]
  new.climate.value is 0

tag rule "hope it stays mild"
when
  -10 <= new.climate.value <= 10
  [ If the climate value is balanced near zero... ]
then
  [ ...apply the mild tag and remove extreme tags. ]
  new.climate.tags includes "mild" and excludes "greenhouse", "ice age"

tag rule "brrrr"
when
  new.climate.value < -10
  [ If the climate drops significantly below zero... ]
then
  [ ...it triggers an ice age. ]
  new.climate.tags includes "ice age" and excludes "mild", "greenhouse"

tag rule "hothothot"
when
  new.climate.value > 10
  [ If the climate rises significantly above zero... ]
then
  [ ...it triggers the greenhouse effect. ]
  new.climate.tags includes "greenhouse" and excludes "ice age", "mild"

tag rule "getting warmer"
when
  new.climate.value > climate.value
  [ If the new value is higher than the previous turn's value... ]
then
  [ ...show that the trend is warming. ]
  new.climate.tags includes "warming" and excludes "cooling"

tag rule "getting cooler"
when
  new.climate.value < climate.value
  [ If the new value is lower than the previous turn's value... ]
then
  [ ...show that the trend is cooling. ]
  new.climate.tags includes "cooling" and excludes "warming"

tag rule "not changing"
when
  new.climate.value = climate.value
  [ If the value stayed exactly the same... ]
then
  [ ...remove all trend tags. ]
  new.climate.tags excludes "cooling", "warming"
```

---

# Clime Language Reference: Rules language specification for the Nomicron climate system

This Clime Language Reference serves as the formal specification for the Clime Rule Language syntax, providing the necessary details for PRM parser developers to convert `.rules` source files into the target intermediate representation.

## 1. Lexical Structure & Grammar

The language prioritizes whitespace-separated, plain-English keywords.

* **Keywords:** `climate rule`, `tag rule`, `when`, `then`, `and`, `or`, `not`, `is`, `increased by`, `decreased by`, `include`, `includes`, `exclude`, `excludes`, `any of`, `all of`, `empty`. Keywords are case-insensitive.
* **Rule Definitions:** Must begin with the exact sequence `climate rule` or `tag rule`, followed by a string literal representing the name.
* **Comments:** Text enclosed in square brackets `[ ... ]` are comments. They may appear anywhere in the source file except inside multi-word keywords (e.g., between "climate" and "rule") and are explicitly ignored by the lexer/parser.

## 2. Data Types & Literals

* **Number:** Floating-point or integer values (e.g., `42`, `-15`, `3.14`). Supports a unary negative symbol directly prefixing a variable, nested expression, or literal.
* **Boolean:** `true`, `false`.
* **String:** Enclosed in double (`"`) or single (`'`) quotes. Escaping a quote is done via a backslash (`\`), and a literal backslash requires double backslashes (`\\`).
* **Tag List:** A comma-separated list of string literals (e.g., `"Mild", "Windy"`). To explicitly define a single-element tag list without contextual cues, a trailing comma must be appended (e.g., `"Mild",`). An empty tag list is represented by the keyword `empty`.

## 3. Operators & Precedence

Operators strictly map to standard evaluation node structures, with some handled as syntactic sugar for function nodes.

### Arithmetic Operators (Numbers)

* Unary `-`: Highest priority arithmetic negation.
* `^`
* `*`, `/`, `mod`
* `+`, `-`

### Comparison Operators (All Types where applicable)

* `=`
* `!=`
* `<`, `<=`, `>`, `>=`

### Logical Operators (Booleans)

* `and`: Short-circuits if the left side is false. Note: Multiple expressions defined in a rule's `when` block are implicitly evaluated with an `AND` operation.
* `or`: Short-circuits if the left side is true.
* `not`: Unary inversion.

### Syntactic Sugar

The parser must translate specific natural-language constructs into their underlying function calls or explicit mutation actions:

* **Numeric Range Comparisons:**
  * `x < N < y` translates to `within(N, x, y, "()")`
  * `x <= N <= y` translates to `within(N, x, y, "[]")`
  * `x < N <= y` translates to `within(N, x, y, "(]")`
  * `x <= N < y` translates to `within(N, x, y, "[)")`
* **Condition List sugar Expressions:**
  * `<target> includes <expr>` translates to `has(<target>, <expr>)`
  * `<target> includes any of <expr>` translates to `has_any(<target>, <expr>)`
  * `<target> includes all of <expr>` translates to `has_all(<target>, <expr>)`
  * `<target> excludes <expr>` translates to `not(has(<target>, <expr>))`
  * `<target> excludes any of <expr>` translates to `not(has_any(<target>, <expr>))`
  * `<target> excludes all of <expr>` translates to `not(has_all(<target>, <expr>))`
* **Chained Tag-List Actions:**
  * Tag-list action items combined via `and` (e.g., `target includes X and excludes Y`) must be parsed and unrolled into multiple, separate actions against the same target.

## 4. Environment Namespaces & Strict Typing

Variables dynamically instantiate upon first use. To ensure the Core Engine can perform static type checking, the `var.` namespace requires strict type prefixes:

* `var.n.` followed by an identifier: Number (defaults to `0`).
* `var.b.` followed by an identifier: Boolean (defaults to `false`).
* `var.s.` followed by an identifier: String (defaults to `""`).
* `var.l.` followed by an identifier: Tag List (defaults to `empty`).
* Note: Only one level of identifier is allowed after the type prefix (e.g., `var.n.counter` is valid, `var.n.player.counter` is invalid).

## 5. Built-in Functions

Functions can be invoked via standard call syntax `func(arg)` or method syntax `arg.func()`. The underlying representation remains identical regardless of the source language syntax chosen.

### Number Functions

* `abs(n)` / `n.abs()`: Absolute value.
* `round(n, [precision])` / `n.round([precision])`: Rounds to the nearest integer or `precision` decimal places.
* `min(n1, n2, ...)` / `n1.min(n2, ...)`: Lowest value.
* `max(n1, n2, ...)` / `n1.max(n2, ...)`: Highest value.
* `clamp(n, min_val, max_val)` / `n.clamp(min_val, max_val)`: Constrains `n`.
* `within(n, lo, hi, [bounds])` / `n.within(lo, hi, [bounds])`: Checks range. `bounds` accepts `"[]"`, `"()"`, `"[)"`, or `"(]"`.
* `to_string(n)` / `n.to_string()`: Converts to a string.

### String Functions

* `length(s)` / `s.length()`: Character count.
* `contains(s, substring)` / `s.contains(substring)`: Exact substring match.
* `starts_with(s, prefix)` / `s.starts_with(prefix)`: Prefix check.
* `ends_with(s, suffix)` / `s.ends_with(suffix)`: Suffix check.
* `to_number(s)` / `s.to_number()`: Parses string to number.

### Tag List Functions

* `length(list)` / `list.length()`: Count of unique tags.
* `has(list, tag)` / `list.has(tag)`: True if `tag` exists.
* `has_any(list, tag_list)` / `list.has_any(tag_list)`: True if at least one tag from `tag_list` exists in `list`.
* `has_all(list, tag_list)` / `list.has_all(tag_list)`: True if all tags from `tag_list` exist in `list`.
* `is_empty(list)` / `list.is_empty()`: True if count is 0.

## 6. Action Mutations

Mutations in the `then` block define standard assignment and list alterations.

* **Assignment:** `<target> is <expression>`
* **Addition Assignment:** `<target> is increased by <expression>`
* **Subtraction Assignment:** `<target> is decreased by <expression>`
* **Set Union:** `<target> includes <expression>` or `<target> include <expression>`
* **Set Difference:** `<target> excludes <expression>` or `<target> exclude <expression>`

*Convention Note:* The engine cannot statically block a Climate Rule from mutating `new.climate.tags` purely through syntax without also precluding the valid use of dynamic tag list variables (e.g., `var.l.my_tags`). Thus, the separation of concerns (Climate Rules for numbers/booleans, Tag Rules for tag lists) remains a convention.

## 7. Extended Backus-Naur Form (EBNF) Grammar

```ebnf
RuleSet ::= Rule+
Rule ::= RuleType StringLiteral "when" Conditions "then" Actions
RuleType ::= "climate rule" | "tag rule"
Conditions ::= Expression+
Actions ::= Action+

Action ::= Target "is" Expression
         | Target "is increased by" Expression
         | Target "is decreased by" Expression
         | Target MutateOp Expression ( "and" MutateOp Expression )*
MutateOp ::= "include" | "includes" | "exclude" | "excludes"

Target ::= NamespacePath
NamespacePath ::= Identifier ("." Identifier)*

Expression ::= LogicOr
LogicOr ::= LogicAnd ("or" LogicAnd)*
LogicAnd ::= LogicNot ("and" LogicNot)*
LogicNot ::= "not" LogicNot | ConditionSugar | Comparison

ConditionSugar ::= Target SugarOp Expression
                 | RangeComparison
SugarOp ::= "includes" | "includes any of" | "includes all of"
          | "excludes" | "excludes any of" | "excludes all of"

Comparison ::= Arithmetic [ CompOp Arithmetic ]
CompOp ::= "=" | "!=" | "<" | "<=" | ">" | ">="
RangeComparison ::= Arithmetic ("<" | "<=") Arithmetic ("<" | "<=") Arithmetic

Arithmetic ::= Term (("+" | "-") Term)*
Term ::= Factor (("*" | "/") Factor)* | Factor "mod" Factor
Factor ::= [ "-" ] Base [ "^" Factor ]
Base ::= Literal | NamespacePath | FunctionCall | MethodCall | "(" Expression ")"

FunctionCall ::= Identifier "(" [ArgumentList] ")"
MethodCall ::= Base "." Identifier "(" [ArgumentList] ")"
ArgumentList ::= Expression ("," Expression)*

Literal ::= Number | Boolean | StringLiteral | TagList
Number ::= ["-"] Digit+ ["." Digit+]
Boolean ::= "true" | "false"
StringLiteral ::= '"' [^"\\]* '"' # keep rendering engines happy: '
                | "'" [^'\\]* "'" # keep rendering engines happy: "
TagList ::= "empty" | StringLiteral "," | StringLiteral ("," StringLiteral)+

Identifier ::= Letter (Letter | Digit | "_")*
Letter ::= [a-zA-Z]
Digit ::= [0-9]
Comment ::= "[" [^\]]* "]"
```

Note: `Comment` is handled at the lexer level and may interleave between any valid tokens.

---

### Implementation Notes

* **Titles and Referencing:** The files have been explicitly titled and referenced internally as the "Clime User Guide" and "Clime Language Reference" as requested.
* **Markdown Formatting Correction:** The typo in Section 6 of the Language Reference was corrected, changing `*Convention Note:` to `*Convention Note:*`.
* **Restoring Details:** The explicit instruction detailing that `Comment` is handled at the lexer level was preserved at the end of Section 7 of the Language Reference.
* **Spacing & Asterisks:** All lines end cleanly without trailing whitespace, and no independent, single-spaced double asterisks were required in code formatting, fulfilling all stylistic specifications.
