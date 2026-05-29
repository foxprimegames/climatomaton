### Pending Updates for Other Documents

#### Pluggable Environment Module (PEM) Design Document

1. **Schema File Syntax & Semantics:** Must rigorously define the JSON structure, syntax, and semantics of the `{pem_namespace}.schema.json` file. This includes standardizing how namespace paths are mapped to primitive types, and explicitly specifying which namespace paths are mutable; any namespace paths not so specified will be treated as read-only. It must also define how namespace paths with wildcards are to be treated by the rules parser.
2. **Environment File Syntax & Semantics:** Must rigorously define the JSON structure of the `{pem_namespace}.json` file, specifying how the structured environment data is mapped omitting the PEM's namespace prefix.
3. **Transaction & Acknowledgment Formats:** Must define the precise JSON structure and expected key-value pairs for the transaction diff file (`req_{tx_id}_{namespace}.json`) and the subsequent acknowledgment file (`ack_{tx_id}_{namespace}.json`).

#### Rules Engine Design Document

1. **Dynamic Type Registry Initialization:** The engine must be designed to construct a master `TypeMap` at runtime by scanning and flattening the IPC volume for all loaded PEM schemas (`*.schema.json`) alongside internal schemas. Parsing and translation logic will depend on the PEM Design Document's specifications for translating path patterns and wildcards into resolving regex patterns within the registry.
2. **Static Type Checking & Semantic Analysis:** The engine must implement a proactive compiler frontend pattern (a Node Visitor architecture) that traverses the JSON-IR AST prior to active execution. This visitor is responsible for inferring types bottom-up, enforcing operator and function constraints (e.g., preventing a `MOD` operation on a string), and guaranteeing no implicit type coercion takes place. If an undefined symbol or type mismatch is found, it must throw an error bound to the `source` tracking string and abort the ruleset load.

#### DGL (Discord Gateway Listener) & DAC (Discord API Client) Design Documents

1. **Discord Integration specifics:** Must define exact Discord intents and permissions (for the DGL) and specific OAuth2 scopes (for the DAC). Additionally, the DAC design document must incorporate the specific logic for overall and per-source notification rate limiting.
