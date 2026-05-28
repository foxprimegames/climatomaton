# Rule Language Design Specification: Climatomaton

## 1. Core Requirements & Logic Constraints

This section outlines the foundational requirements for the rule execution language, dictating how the Abstract Syntax Tree (AST) will be structured and evaluated within the Climatomaton Core Daemon.

### 1.1 Rule Types and Execution Order

The update process executes in a strict, two-phase sequence:

* **Climate Rules:** An ordered set of rules evaluated first to determine how the numeric climate value changes.
* **Tag Rules:** An ordered set of rules evaluated second to identify which text tags are included in or excluded from the final climate description.

### 1.2 Rule Structure

Both climate and tag rules share a unified base structure containing three distinct components:

* **Name:** A string identifier for the rule.
* **Conditions:** A set of boolean expressions where *all* conditions must be met (logical AND) for the rule to activate.
* **Actions:** The specific mutations that occur as a result of the rule activating.

### 1.3 Execution Environments

Rules execute against structured, identifier-value data sets accessed via `.`-separated namespace paths. There are three distinct environments:

* **Climate Environment:** A read-only snapshot of the state prior to rule execution. It includes the existing climate data , a summary of the end-of-turn proposals (e.g., `proposals.count`, `proposals.passed`) , and any dynamically registered Pluggable Environment Module (PEM) namespaces.
* **Transaction Environment:** A mutable environment, strictly accessed via the `new.` prefix. It is initialized from the read-only climate environment and captures all state mutations intended for persistence.
* **Variable Environment:** A flat, ephemeral set of mutable numeric variables accessed via the `var.` prefix. Variables auto-initialize to `0` upon first reference within an expression or action.
* **Failure Policy:** If at any point an expression attempts to resolve a namespace path that does not exist or fails validation (excluding uninitialized `var.` fields), all rule processing must immediately abort. The failure is logged, and no default values are assumed.

### 1.4 Conditions and Expressions

Conditions evaluate boolean expressions to determine rule activation.

* **Boolean Expressions:** Support standard boolean operators (AND, OR, NOT), grouping for precedence, and standard comparison operations against arithmetic expressions. They must also support a concise syntax for determining if a value falls within a specific range.
* **Function Evaluation:** Expressions must support a defined set of functions that accept boolean or arithmetic arguments and return boolean values.

### 1.5 Actions and Operations

Actions define mutations against a target namespace identifier located strictly within the transaction (`new.`) or variable (`var.`) environments.

* **Numeric Mutations (Climate Rules):** Utilize mutate operators (`=`, `+=`, `-=`) paired with an arithmetic expression.
* **Arithmetic Expressions:** Support standard operators (addition, subtraction, multiplication, division, modulo, and potentially exponentiation), literal values, namespace path references, function evaluations, and grouping.
* **List Mutations (Tag Rules):** Utilize list operators (`includes`, `excludes`) paired with a list expression or literal string tag.

---

### Discussion & Next Steps

This initial section formalizes the constraints into a specification ready for schema mapping. Before we draft the actual JSON Schema definitions (e.g., deciding whether to use a heavily nested AST structure like LISP in JSON, or a flatter, more human-readable rule format that gets compiled later), we should establish how you want the JSON structure to handle expressions.

Do you prefer the schema to define a strict AST object tree for arithmetic and boolean logic (which is safer to parse but very verbose to write), or a string-based expression format that the rules engine will parse internally (e.g., `"condition": "climate.value >= 10 and new.weather.temp < 5"`)?
