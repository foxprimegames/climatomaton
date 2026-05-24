# PRM (Git-Fetch) Design Document

This document defines the architecture, configuration, and operational lifecycle of the Git-Fetch Pluggable Rules Module (PRM). The Git-Fetch PRM operates as an automated version-control fetcher and directory coordinator to act as the system's operational clock. It is responsible for safely retrieving rulesets from a designated Git repository and safely deploying them to the shared volume without disrupting the active game state.

## 1. System Authority & Activation Bound

Exactly one pluggable rules module must be active and operational within the system landscape at any given time.

The Git-Fetch PRM serves as the **exclusive deployment conduit** for rulesets. It acts as an autonomous observer and controller that bridges the gap between a specific directory within an external Git repository and the local system. By mirroring only the targeted rules files from the designated branch—the authoritative source of game logic—the Git-Fetch PRM ensures that rules are updated in a synchronized, version-controlled manner, operating independently of the external game environment that reports events to the system.

## 2. Git Operations & Authentication Configuration

The Git-Fetch PRM must dynamically target specific rule sources. All operational parameters are injected at runtime via process environment variables to maintain container isolation.

* **`GIT_REPO_URL`**: The complete URL of the external source repository.
* **`GIT_BRANCH`**: The specific branch name to track and fetch updates from.
* **`GIT_TARGET_FOLDER`**: The specific directory path within the targeted Git branch that contains the active rules files.
* **Authentication**: The system must securely load access credentials required to authenticate with the external Git repository.

## 3. Native Sync Polling Logic & Deployment Lifecycle

To maintain strict process isolation, guarantee vendor agnosticism, and eliminate filesystem bloat, it is strongly recommended that the Git-Fetch PRM strictly utilize a native-language Git library binding rather than shelling out to a host OS binary. The PRM should operate entirely on bare Git object databases to avoid unnecessary disk I/O and working directory checkouts.

The Git-Fetch PRM manages the synchronization lifecycle through a continuous monitor-fetch-update cycle divided into three logical phases:

### Phase 0: System Bootstrap (State Initialization)

Upon container startup, the Git-Fetch PRM establishes its operational baseline.

* **Client Initialization**: The PRM initializes its native Git client structure, identifying the remote `GIT_REPO_URL` and preparing the local environment to maintain a bare Git object database.
* **State Priming**: The previously deployed commit hash is explicitly initialized to an **invalid hash (e.g., null or an empty string)**. This guarantees that the very first execution of the polling loop will detect a state mismatch and naturally trigger the initial rules deployment.

### Phase 1: The Autonomous Polling Loop

Once bootstrapped, the Git-Fetch PRM transitions into its continuous monitoring phase, acting as the operational system clock.

* **Head Resolution**: On a defined interval, the PRM queries the remote repository to retrieve the latest commit hash specifically for the target `GIT_BRANCH`.
* **State Comparison**: The PRM compares the remote commit hash against its previously deployed commit hash. This allows the system to detect upstream changes transparently over the network without requiring disk reads or procedurally modifying any rulesets.

### Phase 2: Retrieval & Direct-to-Volume Deployment

If a hash mismatch is detected—whether during the initial cold start or a subsequent upstream update—the Git-Fetch PRM dictates that a new ruleset is required and executes the deployment pipeline.

* **Secure Fetch**: The PRM executes a fetch operation against the repository, pulling down the updated tree and blob objects required to satisfy the new branch head into its isolated, bare-database memory space.
* **Direct-to-Volume Extraction**: Bypassing a standard filesystem checkout, the PRM traverses the updated in-memory tree specifically to the `GIT_TARGET_FOLDER`. It creates the next versioned staging directory (`rules-YYYYMMDD-HHMMSS/`) relative to the root of the shared volume. The PRM then streams *only* the `.rules` file payloads located within that targeted directory directly from the Git objects into the new staging directory.
* **Commitment & Update**: The PRM executes the Atomic Promotion Protocol to write the new directory path (relative to the shared volume root) to the `rules.commit` manifest. Finally, it updates its previously deployed commit hash to match the newly deployed state, completing the cycle and resuming the polling loop.
