This design document outlines the synchronization protocol for the Climatomaton shared volume, defining the operational workflows for the Pluggable Rules Module (PRM), Pluggable Environment Modules (PEMs), and the Core Engine.

---

### 1. Shared Volume Layout and Manifest Specification

The shared volume serves as the primary communication medium for the engine. The Core Engine and all modules coordinate their activities via a deterministic versioned directory structure.

```text
/ (Shared Volume Root)
├── rules.commit                    # Atomic pointer file
└── rules-YYYYMMDD-HHMMSS/          # Active versioned directory
    ├── [FileNumber]-[Descriptor].rules
    └── [namespace].json            # Pluggable environment module data

```

### `rules.commit` File Format:

The `rules.commit` file acts as the system's "source of truth" pointer. Its format consists of a single-line, plain ASCII string containing the relative path to the currently active rules directory within the shared volume (e.g., `rules-20260520-225718`), terminated by a newline character.

### "Atomic" File Update Protocol

To ensure the Core Engine never reads a partially written file, all modules (PRM and PEMs) must adhere to the following file update sequence:

1. **Serialize**: Write the new content to a temporary file (e.g., `.filename.tmp`) within the target directory.
2. **Flush**: Call `fsync()` (or equivalent system call) on the temporary file to ensure the data is fully flushed from OS buffers to physical storage.
3. **Rename**: Perform an OS-level `rename()` operation to replace the target file with the temporary file (e.g., `.filename.tmp` -> `filename`).

#### File System Assumption for Atomic File Updates

The integrity of this synchronization protocol relies on the foundational assumption that the host OS `rename()` operation is atomic. This atomicity guarantees that "reader" processes (the Core Engine) never observe a file in a partially written state; they will always see either the previous file or the successfully updated file, never a corrupted transition. If the underlying host file system does not support atomic renames, this protocol cannot guarantee state consistency.

---

### 2. PRM Operational Workflow

The Pluggable Rules Module (PRM) acts as the system clock; it creates the staging environment and promotes it.

1. **Generation**: Create a new, uniquely named directory (e.g., `rules-YYYYMMDD-HHMMSS/`).
2. **Compilation**: Write all validated `.rules` files into the new directory.
3. **Commitment**: Use the **"Atomic" File Update Protocol** defined in Section 1 to write the new directory path to `rules.commit` at the root of the shared volume.

---

### 3. PEM Operational Workflow

Pluggable Environment Modules (PEMs) are reactive components that inject environment objects. They must update state without disrupting the Core Engine’s active transaction.

1. **Observation**: The PEM continuously monitors `rules.commit` to identify the *currently active* directory.
2. **Atomic Write Protocol**: To inject or update an Environment Object, the PEM must use the **"Atomic" File Update Protocol** (defined in Section 1):
   * Write the object to `[namespace].json.tmp` inside the active directory.
   * Perform the flush and rename to `[namespace].json`.
3. **Constraint**: The `[namespace]` identifier must consist only of alphanumeric characters and must begin with a letter. This restriction ensures that `[namespace]` is a valid identifier that can be referenced by a rule within the DSL.
4. **Asynchronous Nature**: PEMs may perform this protocol at any time the environment changes, not just during system directory rotations.

---

### 4. Core Engine Operational Workflow

The Core Engine is the final consumer. It validates the state before activating it.

1. **Trigger**: Detect a change in the `rules.commit` pointer.
2. **Syntax Discovery**: Scan all `.rules` files in the target directory and parse them. If syntax errors occur, **Abort**.
3. **Dependency Extraction**: Use parsed rules to compile a `RequiredModulesList` of all `NamespacePath` tokens.
4. **Ingestion & Validation**:
   * Poll the directory for all files in the `RequiredModulesList`.
   * If a file appears, parse the JSON. If a **JSON parsing error** occurs, **Abort**.
   * Continue waiting until all files are present or `T_MAX` (e.g., 5s) expires.
5. **Atomic Swap**: If all validations pass, update the internal memory pointer to the new directory.
6. **Garbage Collection**: Recursively delete any directories not pointed to by the current `rules.commit`.
7. **Failure Logic (Abort-and-Report)**:
   * If an error occurs (syntax/parse failure or timeout), the engine executes the following rollback sequence **immediately**:
     1. **Rollback Pointer**: Use the **"Atomic" File Update Protocol** to write the *previous* directory path (the "last known good" state) back into `rules.commit`.
     2. **Abort**: Halt the current transition and discard all staged data.
     3. **Mandatory Logging**: Log the failure to `stdout/stderr` and the Discord logging target, explicitly naming the missing or malformed files (e.g., `Error: JSON parse error in economy.json`).
     4. **Deferred Cleanup**: Only *after* the `rules.commit` file has been reverted may the engine proceed to potential garbage collection or diagnostic cleanup.

---

### 5. Summary of Interactions

| Role | Operation Trigger | Protocol Used |
| --- | --- | --- |
| **PRM** | New Rules Compiled | Atomic File Update Protocol (`rules.commit`) |
| **PEM** | Env Data Mutation | Atomic File Update Protocol (`[ns].json`) |
| **Core Engine** | `rules.commit` update | Validate -> Wait -> Swap |
