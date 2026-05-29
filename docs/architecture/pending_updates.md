### Pending Updates for Other Documents

#### Climatomaton Architecture Specification

The following items reflect architecture modifications driven by ongoing language updates that must be synchronized into the main **Climatomaton Architecture Specification**:

1. **Core Daemon Immediate Validation Pass:** Update Section 4.1 to specify that the Core Daemon must actively monitor the rules folder and the schemas folder. It must proactively parse and type-check incoming JSON-IR files immediately upon modification of the rules file, or whenever a PEM schema is added, updated, or deleted.
2. **Validation Error Recovery Policy:** Update the architecture to reflect the exact fallback strategies:
   * **LKG Fallback:** If a newly watched JSON-IR file fails semantic/static verification, the Core Daemon discards it, retains the prior working version, logs the trace, and issues an admin alert.
   * **PAUSED Fallback:** If an environment change (like a PEM deletion) renders the active rules invalid, there is no "last-known-good" ruleset to fall back to. The Core Daemon must immediately drop into a **PAUSED** state, halt EOT reporting, and notify the administrators.
3. **PEM Schema Exchange & Registration Cadence:** Establish an initialization file contract (updating Section 4.2) where every registered PEM must write a static schema description file (e.g., `{pem_namespace}.schema.json`) to the shared IPC volume. The Core Daemon reads these files on startup and during dynamic reloads to successfully construct the type-checking reference map required for validating JSON-IR expressions. The specific structure, syntax, and semantics of these schema files are defined in the **Pluggable Environment Module (PEM) Design Document**.

#### Pluggable Environment Module (PEM) Design Document

The following items reflect the required plugin specifications that must be detailed in the upcoming **Pluggable Environment Module Design Document**:

1. **Schema File Syntax & Semantics:** Define the exact JSON structure, syntax, and semantics of the `{pem_namespace}.schema.json` file. This includes standardizing how namespace paths are mapped to primitive types and explicitly defining how the pattern matching format (e.g., Glob or Regex declarations) is passed along to the Core Engine for parsing.

#### Rules Engine Design Document

The following items reflect the required internal compiler and execution logic that must be detailed in the upcoming **Rules Engine Design Document**:

1. **Dynamic Type Registry Initialization:** The engine must construct a master `TypeMap` at runtime by scanning and flattening the IPC volume for all loaded PEM schemas (`*.schema.json`) alongside internal schemas. The exact parsing and translation logic depends entirely on the schema definition provided in the PEM Design Document, which will dictate how paths and pattern matching formats are declared and subsequently translated into resolving regex patterns within the registry.
2. **Static Type Checking & Semantic Analysis (Visitor Pattern):** The engine must implement a proactive compiler frontend pattern (a Node Visitor architecture) that traverses the JSON-IR AST prior to active execution. This visitor infers types bottom-up, enforces operator and function constraints (e.g., preventing a `MOD` operation on a string), and guarantees no implicit type coercion is taking place. If an undefined symbol or type mismatch is found, it throws an error bound to the `source` tracking string and aborts the ruleset load.
