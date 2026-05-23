# Custom DSL Parser & AST Interpreter Design Document

This document defines how the Core Engine ingests raw `.rules` files, builds an executable Abstract Syntax Tree (AST), handles sorting priorities, and safely executes calculations against the dynamic memory graph.

## 1. Formal DSL Grammar (Updated EBNF)

*Note: The EBNF grammar below establishes the definitive structural rules for the DSL, updated to support recursive conditional expressions and native function calls. The `contains` operator has been removed in favor of native function invocations.*

```ebnf
File            ::= ( ClimateRule | TagRule )*
ClimateRule     ::= "climate" "rule" String "when" ConditionalExpr "then" ClimateActions "end"
TagRule         ::= "tag" "rule" String "when" ConditionalExpr "then" TagActions "end"

ConditionalExpr ::= LogicalOr
LogicalOr       ::= LogicalAnd ( "or" LogicalAnd )*
LogicalAnd      ::= Inversion ( "and" Inversion )*
Inversion       ::= [ "not" ] Relational
Relational      ::= ArithExpr RelOp ArithExpr [ RelOp ArithExpr ]               
                  | FunctionCall
                  | "(" ConditionalExpr ")"

ArithExpr       ::= Term ( ( "+" | "-" ) Term )*
Term            ::= Factor ( ( "*" | "/" ) Factor )*
Factor          ::= Number | NamespacePath | FunctionCall | "(" ArithExpr ")"

FunctionCall    ::= NamespacePath "(" [ ArgumentList ] ")"
ArgumentList    ::= Argument ( "," Argument )*
Argument        ::= ConditionalExpr | ArithExpr | String

NamespacePath   ::= Identifier ( "." Identifier )*
RelOp           ::= "==" | "!=" | ">" | "<" | ">=" | "<="

ClimateActions  ::= ( NamespacePath ( "+=" | "-=" | "=" ) ArithExpr ";" )+
TagActions      ::= ( ( "include" | "exclude" ) TagList ";" )+
TagList         ::= String ( "," String )*
```

---

## 2. Lexer / Tokenizer Specification

The lexer is responsible for breaking down the raw text of the `.rules` files into a stream of actionable tokens for the parser.

| Token Name | Literal Match / Description |
| --- | --- |
| `TOKEN_CLIMATE` | `"climate"` |
| `TOKEN_TAG` | `"tag"` |
| `TOKEN_RULE` | `"rule"` |
| `TOKEN_WHEN` | `"when"` |
| `TOKEN_THEN` | `"then"` |
| `TOKEN_END` | `"end"` |
| `TOKEN_AND` | `"and"` |
| `TOKEN_OR` | `"or"` |
| `TOKEN_NOT` | `"not"` |
| `TOKEN_INCLUDE` | `"include"` |
| `TOKEN_EXCLUDE` | `"exclude"` |
| `TOKEN_IDENTIFIER` | Alphanumeric string starting with a letter (used in namespace paths) |
| `TOKEN_STRING` | Text enclosed in double quotes. Supports standard escape sequences (e.g., `\"`, `\\`, `\n`, `\t`, `\r`) and Unicode hex escapes (e.g., `\uXXXX`). |
| `TOKEN_NUMBER` | Integer or floating-point numerical values |
| `TOKEN_PLUS` | `+` |
| `TOKEN_MINUS` | `-` |
| `TOKEN_STAR` | `*` |
| `TOKEN_SLASH` | `/` |
| `TOKEN_ASSIGN` | `=` |
| `TOKEN_PLUS_ASSIGN` | `+=` |
| `TOKEN_MINUS_ASSIGN` | `-=` |
| `TOKEN_EQ` | `==` |
| `TOKEN_NEQ` | `!=` |
| `TOKEN_GT` | `>` |
| `TOKEN_LT` | `<` |
| `TOKEN_GTE` | `>=` |
| `TOKEN_LTE` | `<=` |
| `TOKEN_LPAREN` | `(` |
| `TOKEN_RPAREN` | `)` |
| `TOKEN_COMMA` | `,` |
| `TOKEN_SEMICOLON` | `;` |
| `TOKEN_DOT` | `.` |

* **Token Positional Metadata:** In addition to the token type and literal string value, the lexer must attach spatial metadata to every generated token, specifically `LineNumber` and `ColumnNumber`. This spatial data acts in tandem with the active `CompilationContext` to guarantee precise, file-specific error tracebacks during compilation or runtime failures.

---

## 3. Parser Architecture & AST Schema

The system utilizes a recursive descent parser that maps the token stream into an Abstract Syntax Tree (AST). The AST is an in-memory, hierarchical data structure representing the fully parsed ruleset, allowing for safe, isolated evaluation against the runtime state.

* **Root Nodes (`RuleNode`):** The top level of the AST consists of distinct objects for each parsed rule (e.g., `ClimateRuleNode`, `TagRuleNode`). Each root node stores its assigned `Rule ID` and string identifier.
* **Evaluation Trees (`ConditionalNode`):** The `when` clause of a rule is stored as a binary expression tree. Internal nodes represent logical operations (`AndNode`, `OrNode`, `NotNode`) and relational comparisons (`RelationalNode`).
* **Arithmetic Trees (`ArithExprNode`):** Mathematical operations (`+`, `-`, `*`, `/`) are represented by internal arithmetic nodes (e.g., `AdditionNode`, `MultiplicationNode`). These nodes recursively resolve to dynamic floating-point values during execution.
* **Function Nodes (`FunctionCallNode`):** Represent invocations of native or global functions. These nodes capture a target `NamespacePathNode` to identify the function and recursively evaluate their `ArgumentList` prior to executing the underlying engine function.
* **Execution Blocks (`ActionNode`):** The `then` clause of a rule is stored as an ordered list of executable statement nodes (e.g., `AssignmentNode`, `SetMutationNode`), ensuring actions are strictly deferred until the `ConditionalNode` resolves to true.
* **Leaf Nodes:** The terminal ends of the evaluation and action trees consist of literal primitives (`StringNode`, `NumberNode`) and dynamic state pointers (`NamespacePathNode`) mapping directly to the EBNF `NamespacePath`.

---

## 4. Built-In & Environment Functions

Because the grammar supports `FunctionCall` syntax inside arithmetic factors and relational checks, the Core Engine maps specific `NamespacePath` invocations to native interpreter functions.

### Native Environment Functions

These functions are directly attached to the baseline memory graphs and provide context-aware data extraction:

* **`climate.hasTag(String)`**: Returns a boolean (`ConditionalExpr` compatible) evaluating to true if the specified string exists within the active `climate.tags` array.

### Global Standard Functions

These built-in math and logic utilities are evaluated in the global namespace (no prefix required) to safely mutate numerical parameters within rules:

* **`max(...ArithExpr)`**: Variadic function. Returns the largest value from a comma-separated list of arguments.
* **`min(...ArithExpr)`**: Variadic function. Returns the smallest value from a comma-separated list of arguments.
* **`round(ArithExpr)`**: Returns the float rounded to the nearest whole integer. For values with a fractional part exactly equal to `0.5`, the function rounds "half away from zero" (e.g., `2.5` becomes `3`, and `-2.5` becomes `-3`).
* **`abs(ArithExpr)`**: Returns the absolute value of the provided float or integer.

---

## 5. Collation, Sorting, and Rule ID Indexer Engine

Because rules can be distributed across multiple physical `.rules` files, the parser engine enforces a strict multi-file merging and deterministic sorting algorithm.

* **Primary Grouping:** The engine groups and sorts all active `.rules` files in ascending order based on their parsed integer `FileNumber` prefix.
* **Secondary Tie-Breaking:** If multiple rule files share the exact same numeric prefix, the engine sorts those files lexicographically by their full physical filename.
* **The Stateful Compilation Context:** To bridge the gap between physical files on disk and the stateless token stream consumed by the parser, the sorting engine acts as an Orchestrator. As it iterates through the sorted files, it injects a stateful `CompilationContext` object into the parser. This context securely tracks both the parsed `FileNumber` (used for rule ID generation) and the full physical `FileName` (used to trace syntax exceptions and runtime crashes).
* **Continuous Counter Initialization:** Two independent sequential counters are initialized at `1` for the two separate execution scopes: Climate Rules and Tag Rules.
* **Stateful AST ID Allocation:** As the recursive descent parser resolves a `ClimateRule` or `TagRule` block, it requests a new ID from the `CompilationContext`, explicitly passing the resolved rule's scope (`Climate` or `Tag`) as an argument. The Context increments the appropriate scope's dedicated counter and returns the permanent identifier formatted as `FileNumber-RuleIndex`. The context strictly resets both counters to `1` only when it detects a transition to a new numeric `FileNumber` prefix.

---

## 6. Syntax Discovery & Validation Pipeline

The parser operates as a strict, isolated validation phase during the dynamic rule and environment synchronization lifecycle.

* **Atomic Presence Verification:** Before allowing a directory swap, the engine parses all `.rules` files to ensure they pass syntax checks.
* **Dynamic Dependency Scanning:** The AST is scanned for references to any `NamespacePath` (including `FunctionCall` namespaces) to dynamically compile the Required Modules List.
* **Compiler Exceptions:** If any invalid syntax, malformed expressions, or broken grammar rules are encountered, the parser throws a compiler exception to abort the transaction immediately, explicitly before active memory pointers are modified.

---

## 7. Runtime AST Interpreter & Transaction Safety

Once loaded into active memory, the runtime AST interpreter safely executes rules against the dynamic environment graph.

* **Dual-State Evaluation Context:** To guarantee mathematical consistency and eliminate user error, the AST strictly partitions how memory pointers are resolved during a batch:
  * **Within `when` blocks (`ConditionalNode`):** All `NamespacePathNode` references evaluate against the **frozen, pre-batch state**. This ensures that conditional logic is based on the settled environment from the start of the phase.
  * **Within `then` blocks (`ActionNode`):** All `NamespacePathNode` references evaluate against the **live, mutating state**. This allows calculations (e.g., `climate.value += proposals.passed`) to utilize the continuously updated temporary values processed by preceding rules in the execution sequence.
* **Atomic Transaction Boundary:** The core engine treats every rule evaluation cycle triggered by a proposal report as a single atomic transaction.
* **Immediate Abort & Rollback:** If any rule execution fails (e.g., an unresolvable `NamespacePath` variable or a missing function signature), the active cycle halts immediately. The active in-memory state is completely rolled back, ensuring no partial mutations write to `climate.value` or `climate.tags`.
* **Dual-Delivery Error Logging:** A global failure triggers the engine's dual-delivery log pipeline, printing to both the local process terminal and the optionally configured Discord logging target. The emitted failure log must explicitly detail:
  * The unresolvable path or syntax error traceback.
  * The exact physical **`FileName`** (pulled from the AST node's attached context) and the crashed **Rule ID**.
  * The raw proposal report metadata (Message ID and content) that triggered the transaction.
