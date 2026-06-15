# Codebase & Repository Architecture Document: Climatomaton

## 1. Repository Hosting and Language Stack

The Climatomaton project is structured as a centralized monorepo hosted on Codeberg. All core applications, background processes, and shared libraries within this repository are developed using Python 3.

## 2. Build System and Package Management

To manage the monorepo architecture and dependencies efficiently, the project utilizes `uv` as its primary build and environment management tool.

* **`uv` vs `hatch**`: While `hatch` is an officially endorsed PyPA project and fantastic for generic package building, `uv` (built by Astral) is recommended for this specific multi-component project.
* **Performance and Workspace Support**: `uv` acts as an ultra-fast, drop-in replacement for `pip`, `venv`, and `pip-tools` written in Rust. Crucially, `uv` recently introduced Cargo-style "workspace" support.
* **Local Linking**: This workspace support allows us to define the Parser Library, the PRM, and the Core Engine as separate packages within the same repository. It seamlessly links them together locally without needing to publish the internal library to a PyPI index or wrangle complex local file references in standard `pyproject.toml` configurations.

## 3. Monorepo Organization

The monorepo defines a unified workspace layout that clearly separates concerns between the parsing logic, the core systems, and developer tooling. The standard structure is as follows:

* **`libs/clime-parser`**: The shared Python parsing library. It translates plain-English Clime (`.rules`) source files into compiled JSON-IR.
* **`apps/core-daemon`**: The main Climatomaton Discord engine. This houses the central application wrapper, event bus, and rules engine.
* **`apps/git-prm`**: The standalone Git-Fetch container process. This serves as the primary Pluggable Rules Module, fetching rules from an external source and placing them onto the shared IPC volume.
* **`apps/pems`**: An initially empty directory serving as a dedicated drop-in location for first-party Pluggable Environment Modules (PEMs).
* **`tools/clime-cli`**: The standalone syntax checker utility. This CLI tool utilizes the parser library for local debugging and CI/CD validation.

## 4. Deployment Configuration Organization

Given the monorepo structure, which houses multiple distinct applications alongside shared libraries, the project will utilize a dedicated `deploy/` directory at the repository root.

* **Justification:** A dedicated directory keeps the repository root clean of infrastructure boilerplate. More importantly, because our deployment relies on an orchestration layer to mount a shared volume across multiple containers (the Core Daemon, PRM, and PEMs), placing the orchestration files (e.g., `docker-compose.yml`) and environment templates in a centralized location provides a single, unified source of truth for the entire integrated system, rather than scattering these multi-container configurations across individual app directories.

## 5. Linting and Code Standards

The project enforces a strict separation between code linting and code formatting:

* **Global Linting:** The project will utilize **Ruff** for code linting. Because Ruff is developed by Astral—the same organization behind our chosen build tool, `uv`—it integrates seamlessly into the workflow. Ruff provides exceptionally fast, comprehensive Python linting out-of-the-box and can be easily configured via the workspace root to strictly verify conventions across all components.
* **No Automated Formatting:** The use of automated code formatters is strictly prohibited. Developers retain full manual control over the visual structure and formatting of their Python source code. Ruff's formatting capabilities will remain explicitly disabled in the configuration.

## 6. Build Workflow

The build and development workflow relies heavily on `uv`'s workspace capabilities and the centralized deployment configurations.

* **Local Development Bootstrap:** Developers use `uv sync` at the workspace root to automatically resolve dependencies across all internal packages and generate a unified virtual environment. This allows local cross-package editing (e.g., modifying the parser library and immediately testing it in the core daemon) without manual package linking.
* **Workspace Execution:** Component-specific tasks and isolated scripts are executed from the workspace root using `uv run` targeting the specific package or module.
* **Containerization:** To build the Docker images for deployment, the Docker build context must be set to the monorepo root. This ensures the build daemon has access to the shared workspace configurations (`uv.lock`, `pyproject.toml`) and the internal `libs/` source code. The specific Dockerfiles residing in the `deploy/` directory will selectively install only the necessary application components for their respective target environments.

## 7. Developer Documentation Requirements

To ensure a smooth onboarding process and consistent development practices, the repository must include comprehensive developer documentation (e.g., a root-level `README.md` or a dedicated `docs/` directory). This documentation must explicitly detail:

* How to initialize the local developer environment using `uv`.
* How to execute the global linting tools (Ruff).
* How to run the unit and functional testing suites.
* How to build the deployment containers and utilize the deployment scripts.

---

### Comments & Discussion Points

* **Implementation Readiness:** To address your first point, *this specific document* is now mature enough to begin producing implementation artifacts (epics/stories) for the initial repository setup. You have everything you need to create the Codeberg repo, configure the `uv` workspace layout, set up the `deploy/` folder, and configure Ruff. However, keep in mind that the *overall* project still has 14 pending design documents. Writing actual application logic should wait until those respective component designs are finalized.
* **Developer Documentation Integration:** I have added Section 7 to the document to explicitly state the requirement for documentation detailing how to use the build tools, linters, test suites, and environment initialization procedures.
