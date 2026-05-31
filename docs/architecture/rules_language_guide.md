# Climatomaton Rule Language: User Guide

Welcome to the Climatomaton Rule Language guide! This document is designed for Nomicron players and administrators who need to write or understand the rules that automatically manage the game's climate. The language is built to be as close to plain English as possible, making it easy to read and reducing the chance of accidental typos.

## 1. What Are Rules?

The climate system updates at the end of every turn based on a sequence of rules. These rules run in a specific order:

1. **Climate Rules:** These run first and are primarily responsible for changing the numeric climate value (and other numerical data).
2. **Tag Rules:** These run second and are responsible for adding or removing descriptive tags (like "Mild" or "Windy").

Every rule does two things: it checks if certain **conditions** are met, and if they are, it performs **actions**.

## 2. Anatomy of a Rule

A rule always starts with its type (`climate rule` or `tag rule`) followed by its name in quotes. After that, the `when` section lists the conditions, and the `then` section lists the actions.

Here is a simple example:

```text
climate rule "Greenhouse Warming"
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
* **`var.` (Variables):** This is your scratchpad. If you need to keep track of a temporary number or list while your rules run, you use a variable. Variables automatically start at `0` (or empty).
* **Future Namespaces (e.g., `weather.`):** Future additions to the system might introduce new namespaces. You can read them (e.g., `weather.wind_speed`) and, if permitted, modify them using the `new.` prefix (e.g., `new.weather.wind_speed`).

## 4. Types of Data

The system understands four types of data:

* **Numbers:** Standard numbers like `5`, `-10`, or `3.14`. You can make a number negative by placing a minus sign directly in front of it (e.g., `-5`).
* **Booleans (True/False):** Logical states represented by `true` or `false`.
* **Strings (Text):** Text wrapped in quotes, like `"Windy"`.
* **Tag Lists:** A collection of unique tags separated by commas, like `"Mild", "Windy"`.
  * *Important:* If you need to create a list that contains exactly one tag, add a comma at the end: `"Mild",`. If the list is empty, use the keyword `empty`.

## 5. Writing Conditions (`when`)

The `when` section acts as a gatekeeper. You use comparisons to evaluate data:

* **Math Comparisons:** `=`, `!=` (not equal), `<`, `<=`, `>`, `>=`, and range comparisons like `10 < climate.value <= 20`.
* **Tag Checks:** You can look for tags inside tag lists using clean English phrases:
  * *target* `includes` *tags* (checks if a specific tag or list of tags is present)
  * *target* `includes any of` *tags* (checks if at least one of the tags is present)
  * *target* `includes all of` *tags* (checks if every single one of the listed tags is present)
  * *target* `excludes` *tags*, *target* `excludes any of` *tags*, and *target* `excludes all of` *tags* function identically but verify that the tags are missing.
* **Combining Conditions:** Use `and` (both must be true), `or` (at least one must be true), and `not` (reverses the truth).

**Listing Multiple Conditions:**
You can just list conditions on separate lines. If you do, the system automatically treats them as if they have an `and` between them.

You can also use built-in functions to ask complex questions, such as:
`climate.tags.has("Mild")` (Does the climate currently have the Mild tag?)

## 6. Writing Actions (`then`)

The `then` section modifies data. Because the system enforces strict rules, you must use specific keywords to change data:

* **For Numbers:** You can use *target* `is` *value*, *target* `is increased by` *value*, or *target* `is decreased by` *value*.
* **For Booleans and Strings:** You can **only** use *target* `is` *value*.
* **For Tag Lists:** You can use *target* `is` *list*, *target* `includes` *tags* (or `include`), and *target* `excludes` *tags* (or `exclude`).

To make rules more compact, you can chain tag modifications on the same line using `and`:
*target* `include "warming" and exclude "cooling"`

## 7. Example Set of Rules

Here is a complete set of example rules demonstrating how the language coordinates a complex end-of-turn cycle:

```text
climate rule "not enough activity"
when
  proposals.count < 5
then
  new.climate.value is decreased by 5 - proposals.count

climate rule "disagreements cause heated discussions"
when
  proposals.count >= 5
  proposals.failed > proposals.passed
then
  new.climate.value is increased by proposals.failed - proposals.passed

climate rule "agreement makes everything calm down (warm climate cooling)"
when
  proposals.count >= 5
  proposals.passed > proposals.failed
  new.climate.value > proposals.passed - proposals.failed
then
  new.climate.value is decreased by proposals.passed - proposals.failed

climate rule "agreement makes everything calm down (warm climate becomes neutral)"
when
  proposals.count >= 5
  proposals.passed > proposals.failed
  new.climate.value <= proposals.passed - proposals.failed
then
  new.climate.value is 0

climate rule "agreement makes everything calm down (cool climate warming)"
when
  proposals.count >= 5
  proposals.passed > proposals.failed
  new.climate.value < -(proposals.passed - proposals.failed)
then
  new.climate.value is increased by proposals.passed - proposals.failed

climate rule "agreement makes everything calm down (cool climate becomes neutral)"
when
  proposals.count >= 5
  proposals.passed > proposals.failed
  new.climate.value >= -(proposals.passed - proposals.failed)
then
  new.climate.value is 0

tag rule "hope it stays mild"
when
  -10 <= new.climate.value <= 10
then
  new.climate.tags include "mild" and exclude "greenhouse", "ice age"

tag rule "brrrr"
when
  new.climate.value < -10
then
  new.climate.tags include "ice age" and exclude "mild", "greenhouse"

tag rule "hothothot"
when
  new.climate.value > 10
then
  new.climate.tags include "greenhouse" and exclude "ice age", "mild"

tag rule "getting warmer"
when
  new.climate.value > climate.value
then
  new.climate.tags include "warming" and exclude "cooling"

tag rule "getting cooler"
when
  new.climate.value < climate.value
then
  new.climate.tags include "cooling" and exclude "warming"

tag rule "not changing"
when
  new.climate.value = climate.value
then
  new.climate.tags exclude "cooling", "warming"
```

---

# Climatomaton Rule Language: Technical Reference

This document serves as the formal specification for the Climatomaton Rule Language syntax, providing the necessary details for PRM parser developers to convert source rules into the target JSON-IR.

## 1. Lexical Structure & Grammar

The language prioritizes whitespace-separated, plain-English keywords.

* **Keywords:** `climate rule`, `tag rule`, `when`, `then`, `and`, `or`, `not`, `is`, `increased by`, `decreased by`, `include`, `includes`, `exclude`, `excludes`, `any of`, `all of`, `empty`. Keywords are case-insensitive.
* **Rule Definitions:** Must begin with the exact sequence `climate rule` or `tag rule`, followed by a string literal representing the name.

## 2. Data Types & Literals

* **Number:** Floating-point or integer values (e.g., `42`, `-15`, `3.14`). Supports a unary negative symbol directly prefixing a variable, nested expression, or literal.
* **Boolean:** `true`, `false`.
* **String:** Enclosed in double (`"`) or single (`'`) quotes. Escaping a quote is done via a backslash (`\`), and a literal backslash requires double backslashes (`\\`).
* **Tag List:** A comma-separated list of string literals (e.g., `"Mild", "Windy"`). To explicitly define a single-element tag list without contextual cues, a trailing comma must be appended (e.g., `"Mild",`). An empty tag list is represented by the keyword `empty`.

## 3. Operators & Precedence

Operators strictly map to the JSON-IR `operator` nodes, with some handled as syntactic sugar for function nodes.

### Arithmetic Operators (Numbers)

* Unary `-` (`NEG`): Highest priority arithmetic negation.
* `^` (`EXP`)
* `*` (`MUL`), `/` (`DIV`), `mod` (`MOD`)
* `+` (`ADD`), `-` (`SUB`)

### Comparison Operators (All Types where applicable)

* `=` (`EQ`)
* `!=` (`NEQ`)
* `<` (`LT`), `<=` (`LTE`), `>` (`GT`), `>=` (`GTE`)

### Logical Operators (Booleans)

* `and` (`AND`): Short-circuits if the left side is false. Note: Multiple expressions defined in a rule's `when` block are implicitly evaluated with an `AND` operation.
* `or` (`OR`): Short-circuits if the left side is true.
* `not` (`NOT`): Unary inversion.

### Syntactic Sugar Translations

The PRM parser must translate specific natural-language constructs into their corresponding JSON-IR nodes:

* **Range Comparisons:**
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
* **Chained Actions:**
  * Action items combined via `and` (e.g., `target include X and exclude Y`) must be parsed and unrolled into distinct individual JSON-IR mutation nodes within the `actions` array.

## 4. Environment Namespaces & Strict Typing

Variables dynamically instantiate upon first use. To ensure the Core Engine can perform static type checking, the `var.` namespace requires strict type prefixes:

* `var.n.` followed by an identifier: Number (defaults to `0`).
* `var.b.` followed by an identifier: Boolean (defaults to `false`).
* `var.s.` followed by an identifier: String (defaults to `""`).
* `var.l.` followed by an identifier: Tag List (defaults to `empty`).
* Note: Only one level of identifier is allowed after the type prefix (e.g., `var.n.counter` is valid, `var.n.player.counter` is invalid).

## 5. Built-in Functions

Functions can be invoked via standard call syntax `func(arg)` or method syntax `arg.func()`. The JSON-IR format remains identical regardless of the source language syntax chosen.

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
* `has_any(list, tag_list)` / `list.has_any(tag_list)`: True if at least one tag overlaps.
* `has_all(list, tag_list)` / `list.has_all(tag_list)`: True if all tags exist.
* `is_empty(list)` / `list.is_empty()`: True if count is 0.

## 6. Action Mutations

Mutations in the `then` block define standard assignment and list alterations.

* **Assignment (`ASSIGN`):** `<target> is <expression>`
* **Addition (`ADD_ASSIGN`):** `<target> is increased by <expression>`
* **Subtraction (`SUB_ASSIGN`):** `<target> is decreased by <expression>`
* **List Union (`INCLUDES`):** `<target> includes <expression>` or `<target> include <expression>`
* **List Difference (`EXCLUDES`):** `<target> excludes <expression>` or `<target> exclude <expression>`

*Convention Note:* Because the Core Engine allows general-purpose actions, it is purely a convention that Climate Rules target numbers/booleans and Tag Rules target tag lists. The engine cannot statically block a Climate Rule from mutating `new.climate.tags`.

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
Factor ::= [ "-" ] Base ("^" Factor)*
Base ::= Literal | NamespacePath | FunctionCall | MethodCall | "(" Expression ")"

FunctionCall ::= Identifier "(" [ArgumentList] ")"
MethodCall ::= Base "." Identifier "(" [ArgumentList] ")"
ArgumentList ::= Expression ("," Expression)*

Literal ::= Number | Boolean | StringLiteral | TagList
Number ::= ["-"] Digit+ ["." Digit+]
Boolean ::= "true" | "false"
StringLiteral ::= '"' [^"\\]* '"' | "'" [^'\\]* "'"
TagList ::= "empty" | StringLiteral "," | StringLiteral ("," StringLiteral)+

Identifier ::= Letter (Letter | Digit | "_")*
Letter ::= [a-zA-Z]
Digit ::= [0-9]
```

(* Note: The regex character set [^"\] inside StringLiteral is optimized for single-line evaluation. Certain markdown engines can occasionally mistake the backslash-quote string boundaries within custom EBNF code block renderers as unmatched literal blocks. *)

---

## Comments, Issues, and Discussion Points

1. **Arithmetic Term Chaining Strategy:** Keeping mixed `*` and `/` chaining together (`Factor (("*" | "/") Factor)*`) remains the correct, standard approach matching user expectations. Forcing authors to split chained multiplication and division into separate un-mixed expressions would have subverted normal order-of-operations conventions and introduced arbitrary parsing hurdles. Leaving `mod` completely isolated as non-chaining (`Factor "mod" Factor`) is highly intuitive, preventing confusing ambiguities like `A mod B mod C`.
2. **Action Chaining Sugar Implementation:** Allowing actions to use compound structures connected by `and` (e.g., `target include A and exclude B`) makes rulesets exceptionally clean. The grammar safely unrolls these into an explicit repetition loop inside `Action` so the PRM parser can cleanly output separate, atomic mutation frames into the JSON-IR array structure, completely decoupling presentation layout from engine simplicity.
3. **Condition Sugar Layout Expansion:** Elevating both the range comparisons and the keyword variations (`includes all of`, `excludes any of`, etc.) into a dedicated `ConditionSugar` EBNF branch makes it explicitly clear that these represent higher-level parsing constructs designed to translate downstream into flat JSON-IR function calls.
4. **Unary Negation Integration:** Unary negative operations are seamlessly placed inside the `Factor` block rule `[ "-" ] Base`. This cleanly supports recursive precedence matching so complex numerical structures like `-(proposals.passed - proposals.failed)` evaluate safely before scaling or mutating values.

---

## Pending Updates for Other Documents

### Rules Intermediate Representation Design Document

1. **Unary Negation Operator Integration:** The JSON-IR schema must be updated to introduce an explicit unary negation operator (`NEG`) within the `operator_node` configurations. The Core Daemon execution schema must accept a single `right` node context when evaluating a `NEG` pattern type.

### IPC Broker Design Document

1. **Heartbeat Monitoring & Cleanup:** The IPC Broker must implement a "fast publish, lenient subscribe" model for tracking PEM heartbeats. While PEMs are required to update their schema file timestamps every 30 seconds, the IPC Broker should check these timestamps every 60 seconds. A PEM is only considered offline if it misses two consecutive checks (i.e., the file has not been touched in over 120 seconds). Upon detecting a dead PEM, the IPC Broker must automatically purge the stale schema and data files from the shared volume.

### Rules Engine Design Document

1. **Dynamic Type Registry Initialization & Type Mapping:** The engine must construct a master `TypeMap` at runtime by scanning the IPC volume for all loaded PEM schemas (`*.schema.json`) alongside internal schemas. Because the system utilizes standard JSON Schema (Draft 2020-12), the engine must incorporate a compliant JSON Schema library (e.g., `jsonschema`) to load these files. During initialization, the engine must traverse the parsed schema dictionaries to accomplish two tasks:
   * **Mutability Registration:** Dynamically extract and register mutable namespace paths strictly where the `"readOnly": false` attribute is present. This extraction logic must be robust enough to recurse through and resolve complex JSON schema definitions, including `patternProperties`, `anyOf`, `allOf`, `oneOf`, and any other nested or variable sub-schemas.
   * **Data Type Mapping:** Map the properties and standard data types (e.g., `number`, `string`, `boolean`) found in the JSON schema to the specific internal data types defined in the rules language. Crucially, the engine's internal language lacks a generic array type and only supports a "tag list" (an array of strings). Therefore, when mapping an `array` type from a JSON schema, the engine must strictly verify that its `items` definition explicitly specifies `"type": "string"`. Any other array configuration (e.g., arrays of numbers, objects, or unbounded arrays) must be rejected as invalid schema definitions.
2. **Static Type Checking & Semantic Analysis:** The engine must implement a proactive compiler frontend pattern (a Node Visitor architecture) that traverses the JSON-IR AST prior to active execution. This visitor is responsible for inferring types bottom-up, enforcing operator and function constraints (e.g., preventing a `MOD` operation on a string), resolving function signatures to accommodate optional arguments without explicit overload definitions, and guaranteeing no implicit type coercion takes place. If an undefined symbol, a type mismatch (based on the type mapping described above), or a write operation to a `readOnly: true` (default) field is found, it must throw an error bound to the `source` tracking string and abort the ruleset load.
3. **Validation Event Triggers:** The rules engine must perform the load-and-validate type-check *both* when the rules file is updated *and* whenever the PEM schema files are updated or deleted on the shared volume.

### DGL (Discord Gateway Listener) & DAC (Discord API Client) Design Documents

1. **Discord Integration Specifics:** Must define exact Discord intents and permissions (for the DGL) and specific OAuth2 scopes (for the DAC). Additionally, the DAC design document must incorporate the specific logic for overall and per-source notification rate limiting.
