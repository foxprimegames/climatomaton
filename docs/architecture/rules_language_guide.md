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
  and proposals.passed >= 3
then
  add 2 to new.climate.value
```

## 3. Environments: Where Data Lives

Rules read and change data. To keep things organized, data is grouped into "namespaces" (think of them as folders).

* **`climate.` (Read-Only):** This is the state of the climate *before* any rules run this turn. You can look at `climate.value` or `climate.tags`, but you cannot change them directly.
* **`proposals.` (Read-Only):** This contains information about the end-of-turn report, such as `proposals.count`, `proposals.passed`, and `proposals.failed`.
* **`new.` (Mutable):** This is the data you *can* change. When you want to update the climate, you apply your changes to `new.climate.value` or `new.climate.tags`.
* **`var.` (Variables):** This is your scratchpad. If you need to keep track of a temporary number or list while your rules run, you use a variable. Variables automatically start at `0` (or empty).
* **External Namespaces (e.g., `weather.`):** Other modules (PEMs) might provide extra data. You can read them (e.g., `weather.wind_speed`) and, if permitted, modify them using the `new.` prefix (e.g., `new.weather.wind_speed`).

## 4. Types of Data

The system understands four types of data:

* **Numbers:** Standard numbers like `5`, `-10`, or `3.14`.
* **Booleans (True/False):** Logical states represented by `true` or `false`.
* **Strings (Text):** Text wrapped in quotes, like `"Windy"`.
* **Tag Lists:** A collection of unique tags wrapped in brackets, like `["Mild", "Windy"]`.

## 5. Writing Conditions (`when`)

The `when` section acts as a gatekeeper. You use comparisons to evaluate data:

* **Math Comparisons:** `=`, `!=` (not equal), `<`, `<=`, `>`, `>=`.
* **Combining Conditions:** Use `and` (both must be true), `or` (at least one must be true), and `not` (reverses the truth).

You can also use built-in functions to ask complex questions, such as:
`climate.value.within(10, 20)` (Is the value between 10 and 20?)

## 6. Writing Actions (`then`)

The `then` section modifies data. Because the system enforces strict rules, you must use specific keywords to change data:

* **For Numbers:** You can `set <target> to <value>`, `add <value> to <target>`, or `subtract <value> from <target>`.
* **For Tag Lists:** You can `set <target> to <list>`, or use `<target> includes <tags>` to add tags, and `<target> excludes <tags>` to remove them.

**Example of a Tag Rule:**

```text
tag rule "Extreme Heat Tagging"
when
  new.climate.value > 20
then
  new.climate.tags includes "Extreme Heat"
  new.climate.tags excludes "Mild"
```

---

# Climatomaton Rule Language: Technical Reference

This document serves as the formal specification for the Climatomaton Rule Language syntax, providing the necessary details for PRM parser developers to convert source rules into the target JSON-IR.

## 1. Lexical Structure & Grammar

The language prioritizes whitespace-separated, plain-English keywords.

* **Keywords:** `climate rule`, `tag rule`, `when`, `then`, `and`, `or`, `not`, `set`, `to`, `add`, `subtract`, `from`, `includes`, `excludes`. Keywords are case-insensitive.
* **Rule Definitions:** Must begin with the exact sequence `climate rule` or `tag rule`, followed by a string literal representing the name.

## 2. Data Types & Literals

* **Number:** Floating-point or integer values (e.g., `42`, `-15`, `3.14`).
* **Boolean:** `true`, `false`.
* **String:** Enclosed in double (`"`) or single (`'`) quotes. Escaping a quote is done via a backslash (`\`), and a literal backslash requires double backslashes (`\\`).
* **Tag List:** A comma-separated list of string literals enclosed in square brackets (e.g., `["Mild", "Windy"]`, `[]`).

## 3. Operators & Precedence

Operators strictly map to the JSON-IR `operator` nodes.

### Arithmetic Operators (Numbers)

* `+` (`ADD`)
* `-` (`SUB`)
* `*` (`MUL`)
* `/` (`DIV`)
* `mod` (`MOD`)
* `^` (`EXP`)

### Comparison Operators (All Types where applicable)

* `=` (`EQ`)
* `!=` (`NEQ`)
* `<` (`LT`), `<=` (`LTE`), `>` (`GT`), `>=` (`GTE`)

### Logical Operators (Booleans)

* `and` (`AND`): Short-circuits if the left side is false.
* `or` (`OR`): Short-circuits if the left side is true.
* `not` (`NOT`): Unary inversion.

## 4. Environment Namespaces & Strict Typing

Variables dynamically instantiate upon first use. To ensure the Core Engine can perform static type checking, the `var.` namespace requires strict type prefixes:

* `var.n.` followed by an identifier: Number (defaults to `0`).
* `var.b.` followed by an identifier: Boolean (defaults to `false`).
* `var.s.` followed by an identifier: String (defaults to `""`).
* `var.l.` followed by an identifier: Tag List (defaults to `[]`).
* Note: Only one level of identifier is allowed after the type prefix (e.g., `var.n.counter` is valid, `var.n.player.counter` is invalid).

## 5. Built-in Functions

Functions can be invoked via standard call syntax `func(arg)` or method syntax `arg.func()`.

### Number Functions

* `abs(n)`: Absolute value.
* `round(n, [precision])`: Rounds to the nearest integer or `precision` decimal places.
* `min(n1, n2, ...)`: Lowest value.
* `max(n1, n2, ...)`: Highest value.
* `clamp(n, min_val, max_val)`: Constrains `n`.
* `within(n, lo, hi, [bounds])`: Checks range. `bounds` accepts `"[]"`, `"()"`, `"[)"`, or `"(]"`.
* `to_string(n)`: Converts to a string.

### String Functions

* `length(s)`: Character count.
* `contains(s, substring)`: Exact substring match.
* `starts_with(s, prefix)`: Prefix check.
* `ends_with(s, suffix)`: Suffix check.
* `to_number(s)`: Parses string to number.

### Tag List Functions

* `length(list)`: Count of unique tags.
* `has(list, tag)`: True if `tag` exists.
* `has_any(list, tag_list)`: True if at least one tag overlaps.
* `has_all(list, tag_list)`: True if all tags exist.
* `is_empty(list)`: True if count is 0.

## 6. Action Mutations

Mutations in the `then` block define standard assignment and list alterations.

* **Assignment (`ASSIGN`):** `set <target> to <expression>`
* **Addition (`ADD_ASSIGN`):** `add <expression> to <target>`
* **Subtraction (`SUB_ASSIGN`):** `subtract <expression> from <target>`
* **List Union (`INCLUDES`):** `<target> includes <expression>`
* **List Difference (`EXCLUDES`):** `<target> excludes <expression>`

*Convention Note:* Because the Core Engine allows general-purpose actions, it is purely a convention that Climate Rules target numbers/booleans and Tag Rules target tag lists. The engine cannot statically block a Climate Rule from mutating `new.climate.tags`.

---

## Comments, Issues, and Discussion Points

1. **Typo Reduction via Syntax:** By opting for a clean, English-like syntax without strict punctuation (like semicolons or braces) and utilizing descriptive keywords (`set`, `add`, `includes`), we drastically reduce the syntactic surface area where non-technical users commonly make errors.
2. **Double Asterisks & Exponentiation:** The architecture prompt discussions had repeated trouble rendering exponentiation and double asterisks. To resolve this cleanly in the language itself, I defined exponentiation using the standard caret operator (`^`) rather than ``*` `*``. This avoids any markup parsing issues while remaining mathematically standard.
3. **Implicit vs Explicit Arrays:** As highlighted in the schema restrictions, the internal language *only* supports "Tag Lists" (arrays of strings), not generic arrays. Therefore, no generic array functions (like mapping/reducing numbers) were included in the language reference.
4. **Keyword Spacing:** Per the architecture constraints, keywords like `climate rule` strictly require spaces.

---

## Pending Updates for Other Documents

### IPC Broker Design Document

1. **Heartbeat Monitoring & Cleanup:** The IPC Broker must implement a "fast publish, lenient subscribe" model for tracking PEM heartbeats. While PEMs are required to update their schema file timestamps every 30 seconds, the IPC Broker should check these timestamps every 60 seconds. A PEM is only considered offline if it misses two consecutive checks (i.e., the file has not been touched in over 120 seconds). Upon detecting a dead PEM, the IPC Broker must automatically purge the stale schema and data files from the shared volume.

### Rules Engine Design Document

1. **Dynamic Type Registry Initialization & Type Mapping:** The engine must construct a master `TypeMap` at runtime by scanning the IPC volume for all loaded PEM schemas (`*.schema.json`) alongside internal schemas. Because the system utilizes standard JSON Schema (Draft 2020-12), the engine must incorporate a compliant JSON Schema library (e.g., `jsonschema` in Python) to load these files. During initialization, the engine must traverse the parsed schema dictionaries to accomplish two tasks:
   * **Mutability Registration:** Dynamically extract and register mutable namespace paths strictly where the `"readOnly": false` attribute is present. This extraction logic must be robust enough to recurse through and resolve complex JSON schema definitions, including `patternProperties`, `anyOf`, `allOf`, `oneOf`, and any other nested or variable sub-schemas.
   * **Data Type Mapping:** Map the properties and standard data types (e.g., `number`, `string`, `boolean`) found in the JSON schema to the specific internal data types defined in the rules language. Crucially, the engine's internal language lacks a generic array type and only supports a "tag list" (an array of strings). Therefore, when mapping an `array` type from a JSON schema, the engine must strictly verify that its `items` definition explicitly specifies `"type": "string"`. Any other array configuration (e.g., arrays of numbers, objects, or unbounded arrays) must be rejected as invalid schema definitions.
2. **Static Type Checking & Semantic Analysis:** The engine must implement a proactive compiler frontend pattern (a Node Visitor architecture) that traverses the JSON-IR AST prior to active execution. This visitor is responsible for inferring types bottom-up, enforcing operator and function constraints (e.g., preventing a `MOD` operation on a string), resolving function signatures to accommodate optional arguments without explicit overload definitions, and guaranteeing no implicit type coercion takes place. If an undefined symbol, a type mismatch (based on the type mapping described above), or a write operation to a `readOnly: true` (default) field is found, it must throw an error bound to the `source` tracking string and abort the ruleset load.
3. **Validation Event Triggers:** The rules engine must perform the load-and-validate type-check *both* when the rules file is updated *and* whenever the PEM schema files are updated or deleted on the shared volume.

### DGL (Discord Gateway Listener) & DAC (Discord API Client) Design Documents

1. **Discord Integration specifics:** Must define exact Discord intents and permissions (for the DGL) and specific OAuth2 scopes (for the DAC). Additionally, the DAC design document must incorporate the specific logic for overall and per-source notification rate limiting.

### PEM Design Document

1. **PEM Schema Exchange & Wildcards:** The PEM design document must fully define the structure, syntax, and semantics of the `{pem_namespace}.schema.json` file. It must explicitly include a mechanism allowing a PEM to declare which pattern matching format it uses for dynamic properties (e.g., specifying if it utilizes glob-style matching or standard regular expressions), which the Rules Engine will translate internally into standard regex patterns.
