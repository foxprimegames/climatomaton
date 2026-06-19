Understood. I will ensure the complete, consolidated plan is provided in every iteration so you always have the full picture in one place.

I have incorporated the AST Node contracts into Issue 1 to guarantee parallel development is unblocked. I left them defined generically as Python classes, but we can easily specify `dataclasses` later if you prefer.

Here is the complete implementation plan for the Parser Library milestone, formatted with strict flat hierarchies to keep everything clean.

---

# Milestone: Parser Library Implementation

**Description:** End-to-end implementation of the decoupled Clime parsing library, from raw string ingestion to strict JSON-IR emission.

---

## Issue 1: Library Foundation & Interface Contracts

**Description:** Establish the workspace, set up `pytest`, and strictly define the data schemas and enumerations that will serve as the immutable contract between the lexer, parser, and emitter components. *This issue must be completed before Issues 2, 3, or 4 can begin parallel development.*

### Sub-Issue 1.1: Initialize `comp/parser_library` workspace & testing framework

**Description:** Create the dedicated parser library package. Configure `pytest` within the workspace. Expose the primary functions as empty stubs, strictly defining `__all__ = ["parse_clime"]` at the module level so `tokenize`, `parse`, and `emit` require explicit imports.
**Unit Tests:** Verify module import behavior and `__all__` visibility restrictions.
**Labels:** `comp/build system`, `comp/parser_library`, `type/architecture`, `type/test`

### Sub-Issue 1.2: Define `TokenType` Enumeration and `Token` data structure

**Description:** Create an exhaustive `Enum` of all valid token types defined by the EBNF grammar (e.g., keywords, operators, literals, identifiers). Implement the `Token` class to pair these enum types with their exact string values and specific line/column coordinates. Implement `__str__` and `__repr__` for debugging.
**Unit Tests:** Verify instantiation and string representation formats.
**Labels:** `comp/parser_library`, `type/architecture`, `type/test`

### Sub-Issue 1.3: Define parsing Result schemas

**Description:** Implement `BaseResult`, `ASTResult`, and `IRResult` classes. These must support the policy of accumulating errors (logging failures to abort processing of a specific rule) without throwing standard exceptions that would crash the pipeline. Implement boolean `success` flags and `__str__`/`__repr__` methods.
**Unit Tests:** Verify error accumulation logic and boolean flag behavior.
**Labels:** `comp/parser_library`, `type/architecture`, `type/test`

### Sub-Issue 1.4: Define AST Node Contracts

**Description:** Define the base `ASTNode` class and all specific sub-classes required by the Clime grammar (e.g., `RuleNode`, `ConditionNode`, `BinaryOpNode`, `LiteralNode`). Explicitly define the attributes for each node (e.g., a `BinaryOpNode` must have `left: ASTNode`, `right: ASTNode`, and `op: TokenType`). This forms the immutable contract between the Parser and Emitter.
**Unit Tests:** Test object instantiation and attribute assignment.
**Labels:** `comp/parser_library`, `type/architecture`, `type/test`

---

## Issue 2: Lexical Analyzer (Lexer)

**Description:** Build the state machine responsible for processing the raw text of `.rules` files into a discrete stream of `Token` objects.

### Sub-Issue 2.1: Implement Trie-based character buffer & state machine

**Description:** Build the lexer to accept an `Iterator[str]`. Implement a prefix tree (Trie) to process tokens using the maximal munch principle. Map matched strings directly to the `TokenType` enums established in Sub-Issue 1.2. Ensure the lexer accurately captures dot-separated identifier syntax for `NamespacePath` extraction.
**Unit Tests:** `pytest.mark.parametrize` tests for keyword, identifier, and operator extraction. Test ingestion of fragmented string chunks.
**Labels:** `comp/parser_library`, `type/feature`, `type/test`

### Sub-Issue 2.2: Implement comment stripping and whitespace handling

**Description:** Add logic to identify and discard all `[ ... ]` comments and insignificant whitespace at the lexer level.
**Unit Tests:** Verify comments at various positions are dropped without affecting surrounding tokens.
**Labels:** `comp/parser_library`, `type/feature`, `type/test`

### Sub-Issue 2.3: Implement lexical error accumulation

**Description:** Register structured lexical errors with exact coordinates in the `errors` list upon encountering illegal character sequences, skip to the next safe boundary, and resume.
**Unit Tests:** Feed illegal characters and verify coordinate accuracy and resumption logic.
**Labels:** `comp/parser_library`, `type/bug` (Handling), `type/feature`, `type/test`

### Sub-Issue 2.4: Integration Test - Token Stream Validation

**Description:** Feed complete Clime rule strings (valid and invalid) into `tokenize` and assert the exact sequence of the returned `Token` objects.
**Labels:** `comp/parser_library`, `type/test`

---

## Issue 3: Abstract Syntax Tree (AST) & Parser

**Description:** Construct the recursive descent parser to consume the token stream and build the AST in accordance with the Clime EBNF grammar.

### Sub-Issue 3.1: Implement recursive descent expression parsing

**Description:** Build the parser logic to evaluate the `TokenType` stream and instantiate the pre-defined `ASTNode` classes from Sub-Issue 1.4, strictly enforcing operator precedence for mathematical and logical expressions.
**Unit Tests:** Parameterized tests asserting the correct hierarchical tree shape for complex equations.
**Labels:** `comp/parser_library`, `type/feature`, `type/test`

### Sub-Issue 3.2: Parse Clime syntactic sugar constructs

**Description:** Implement logic to capture natural language shortcuts (e.g., `x < N < y`, `includes any of`) into specific AST nodes flagged for downstream unrolling.
**Unit Tests:** Verify sugar sequences resolve to specific, flagged node types.
**Labels:** `comp/parser_library`, `type/feature`, `type/test`

### Sub-Issue 3.3: Implement rule-boundary error synchronization

**Description:** Enforce the error policy. If syntax errors occur within a rule, register the failure, discard the branch, and synchronize at the next `climate rule` or `tag rule` token to abort that specific rule while saving the rest.
**Unit Tests:** Feed malformed tokens and verify the bad rule is dropped while subsequent rules succeed.
**Labels:** `comp/parser_library`, `type/feature`, `type/test`

### Sub-Issue 3.4: Integration Test - AST Construction Validation

**Description:** Pipe raw strings through `tokenize` and `parse`, asserting the final AST structure.
**Labels:** `comp/parser_library`, `type/test`

---

## Issue 4: JSON-IR Emitter

**Description:** Build the pipeline to translate the validated AST into the strict JSON-IR dictionary structure required by the Core Daemon.

### Sub-Issue 4.1: Build AST-to-Dictionary traversal engine

**Description:** Implement `emit()` to recursively traverse the AST and generate the native Python dictionary output, injecting explicit `"kind"` and `"datatype"` identifiers.
**Unit Tests:** Feed isolated nodes into the emitter and verify the output strictly matches the JSON-IR schema structure.
**Labels:** `comp/parser_library`, `type/architecture`, `type/feature`, `type/test`

### Sub-Issue 4.2: Map operators to strict JSON-IR codes

**Description:** Map standard AST operators to their standardized JSON-IR string codes (e.g., `+` to `"ADD"`, `not` to `"NOT"`).
**Unit Tests:** Exhaustively test the mapping of every operator.
**Labels:** `comp/parser_library`, `type/feature`, `type/test`

### Sub-Issue 4.3: Implement syntactic sugar unrolling

**Description:** Expand the flagged sugar nodes during emission into distinct, atomic JSON-IR nodes.
**Unit Tests:** Verify that a single sugar AST node correctly expands into an array of distinct JSON-IR dictionaries.
**Labels:** `comp/parser_library`, `type/feature`, `type/test`

### Sub-Issue 4.4: Integration Test - Full JSON-IR Compilation

**Description:** Feed complete source strings into `parse_clime()` and assert that the final output perfectly matches a predefined, valid JSON-IR dictionary structure.
**Labels:** `comp/parser_library`, `type/test`

---

Would you like to build out the implementation plan for the CLI Tooling next, or is there anything else in this library plan you'd like to adjust first?