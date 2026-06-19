That `__all__` restriction is a great detail. It enforces a clean public API while still allowing you to import the internal pipeline steps for testing or advanced debugging. I'll incorporate that directly into the initialization task.

I agree with adding a specific label for tests. Using `type/test` aligns perfectly with your existing `type/feature` and `type/bug` ontology.

Here is the revised implementation plan, utilizing `pytest` as the testing framework, with unit tests embedded into every feature task and a dedicated integration-level test task capping off each milestone.

### Milestone 1: Library Foundation & Interface Contracts

**Description:** Establish the parsing library within the `uv` workspace, set up `pytest`, define the public API contracts, and lay down the base data structures.

* **Task: Initialize `comp/parser_library` workspace & testing framework**
  * **Description:** Create the dedicated parser library package. Configure `pytest` within the workspace. Expose the primary functions as empty stubs, strictly defining `__all__ = ["parse_clime"]` at the module level so `tokenize`, `parse`, and `emit` require explicit imports.
  * **Unit Tests:** Verify module import behavior and `__all__` restrictions.
  * **Labels:** `comp/build system`, `comp/parser_library`, `type/architecture`, `type/test`
* **Task: Define parsing Result and Token schemas**
  * **Description:** Implement the `BaseResult`, `ASTResult`, and `IRResult` classes to handle error accumulation. Implement the `__str__` and `__repr__` magic methods.
  * **Unit Tests:** Verify error accumulation logic, boolean `success` flag behavior, and string representation outputs.
  * **Labels:** `comp/parser_library`, `type/architecture`, `type/test`
* **Task: Milestone 1 Integration Test - Pipeline Skeleton**
  * **Description:** Write a skeletal end-to-end `pytest` script that explicitly imports and pipes data through the stubbed `tokenize` -> `parse` -> `emit` functions to validate the overall data flow architecture before the internals are built.
  * **Labels:** `comp/parser_library`, `type/test`

### Milestone 2: Lexical Analyzer (Lexer)

**Description:** Build the state machine responsible for processing the raw text of `.rules` files into a discrete stream of tokens.

* **Task: Implement Trie-based character buffer & state machine**
  * **Description:** Build the lexer to accept an `Iterator[str]`. Implement a prefix tree (Trie) to process tokens using the maximal munch principle, safely handling split chunks and dot-separated identifier syntax for `NamespacePath` resolution.
  * **Unit Tests:** `pytest.mark.parametrize` tests for individual keyword, identifier, and operator extraction. Test ingestion of fragmented string chunks.
  * **Labels:** `comp/parser_library`, `type/feature`, `type/test`
* **Task: Implement comment stripping and whitespace handling**
  * **Description:** Add logic to identify and discard all `[ ... ]` comments and insignificant whitespace at the lexer level.
  * **Unit Tests:** Verify comments at various positions (start, middle, end of string) are dropped without affecting surrounding tokens.
  * **Labels:** `comp/parser_library`, `type/feature`, `type/test`
* **Task: Implement lexical error accumulation**
  * **Description:** Register structured lexical errors with line/column coordinates in the `errors` list upon encountering illegal character sequences, then skip to the next safe boundary to resume.
  * **Unit Tests:** Feed illegal characters and verify the exact line/column coordinates in the resulting error objects, and assert that lexing resumes correctly.
  * **Labels:** `comp/parser_library`, `type/bug` (Handling), `type/feature`, `type/test`
* **Task: Milestone 2 Integration Test - Token Stream Validation**
  * **Description:** Write integration tests that feed complete, multi-line Clime rule strings (both valid and invalid) into `tokenize` and assert the exact sequence and type of the complete returned token stream.
  * **Labels:** `comp/parser_library`, `type/test`

### Milestone 3: Abstract Syntax Tree (AST) & Parser

**Description:** Construct the recursive descent parser to consume the token stream and build the AST in accordance with the Clime EBNF grammar.

* **Task: Define AST Python node classes**
  * **Description:** Create Python classes representing the exact EBNF grammar nodes (e.g., `Rule`, `Condition`, `Action`, `Expression`).
  * **Unit Tests:** Test the instantiation and attribute validation of each isolated AST node class.
  * **Labels:** `comp/parser_library`, `type/architecture`, `type/test`
* **Task: Implement recursive descent expression parsing**
  * **Description:** Build the parser logic to handle standard mathematical and logical expressions, strictly enforcing operator precedence.
  * **Unit Tests:** `pytest.mark.parametrize` tests feeding small, manually constructed token lists representing complex equations and asserting the correct hierarchical tree shape.
  * **Labels:** `comp/parser_library`, `type/feature`, `type/test`
* **Task: Parse Clime syntactic sugar constructs**
  * **Description:** Implement parsing logic to capture natural language shortcuts (e.g., `x < N < y`, `includes any of`) into specific AST nodes.
  * **Unit Tests:** Verify that syntactic sugar token sequences resolve to their specific, flagged AST node types.
  * **Labels:** `comp/parser_library`, `type/feature`, `type/test`
* **Task: Implement rule-boundary error synchronization**
  * **Description:** Implement error recovery. If syntax errors occur within a rule, record the error, discard the branch, and synchronize at the next `climate rule` or `tag rule` keyword.
  * **Unit Tests:** Feed malformed rule tokens and verify that the error is recorded, the bad rule is dropped, but subsequent valid rules are successfully parsed.
  * **Labels:** `comp/parser_library`, `type/feature`, `type/test`
* **Task: Milestone 3 Integration Test - AST Construction Validation**
  * **Description:** Write tests that pipe raw strings through `tokenize` and `parse`, asserting the final, complete AST structure accurately reflects full rule definitions.
  * **Labels:** `comp/parser_library`, `type/test`

### Milestone 4: JSON-IR Emitter

**Description:** Build the Emitter pipeline to translate the validated AST into the strict JSON-IR dictionary structure required by the Core Daemon.

* **Task: Build AST-to-Dictionary traversal engine**
  * **Description:** Implement the `emit()` function to recursively traverse the AST and generate the native Python dictionary output, injecting explicit `"kind"` and `"datatype"` identifiers.
  * **Unit Tests:** Feed isolated AST nodes into the emitter and verify the output dictionary strictly matches the JSON-IR schema structure for that specific node type.
  * **Labels:** `comp/parser_library`, `type/architecture`, `type/feature`, `type/test`
* **Task: Map operators to strict JSON-IR codes**
  * **Description:** Map standard AST operators to their standardized JSON-IR string codes (e.g., `+` to `"ADD"`, `not` to `"NOT"`).
  * **Unit Tests:** Exhaustively test the mapping of every defined operator.
  * **Labels:** `comp/parser_library`, `type/feature`, `type/test`
* **Task: Implement syntactic sugar unrolling**
  * **Description:** Expand the flagged sugar nodes during emission into distinct, atomic JSON-IR nodes.
  * **Unit Tests:** Verify that a single sugar AST node correctly expands into the expected array of distinct JSON-IR dictionaries.
  * **Labels:** `comp/parser_library`, `type/feature`, `type/test`
* **Task: Milestone 4 Integration Test - Full JSON-IR Compilation**
  * **Description:** The ultimate validation. Feed complete Clime source strings into the public `parse_clime()` function and assert that the final output perfectly matches a predefined, valid JSON-IR dictionary structure.
  * **Labels:** `comp/parser_library`, `type/test`

---

Would you like me to draft the exact text for the first GitHub issue so you can drop it directly into your tracker, or are we ready to move on to planning the CLI tooling?