# Clime Language Reference: Rules language specification for the Nomicron climate system

This Clime Language Reference serves as the formal specification for the syntax of the rules used to manage the Nomicron climate, providing the necessary details for PRM parser developers to convert `.rules` source files into the target intermediate representation.

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
