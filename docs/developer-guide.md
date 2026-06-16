# Developer Guide

This document describes how to set up a local development environment for the Climatomaton monorepo, how to run linting and basic checks, and the recommended workflows for using `uv` and other development tooling.

Prerequisites
-------------
- Git
- Python 3.11 or later (3.11+ recommended)
- Docker (optional, required only for validating deployment templates)
- PowerShell (Windows) or a POSIX shell (Linux/macOS)

Recommended local environment (reproducible)
-------------------------------------------
We recommend creating a project-local virtual environment and installing pinned dev dependencies via `dev-requirements.txt`.

Example (PowerShell):

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
pip install -r dev-requirements.txt
```

`dev-requirements.txt` contains the development CLI tools used by contributors (uv, ruff, etc.). See the repository root for the file.

Installing `uv`
----------------
Only one supported installation method is documented here: install `uv` into the project-local virtual environment using pip and pin the version in `dev-requirements.txt`.

Project-local (required for this repository):

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
pip install -r dev-requirements.txt
```

Recommendation: use the project virtual environment and `dev-requirements.txt` so that all developers and CI share the same tool versions.

High-level `uv` usage (placeholder)
-----------------------------------
This repository defers workspace initialization to the repository owner. Do not run `uv workspace init` here unless instructed.

When components are ready to be linked, the supported workflow for synchronizing or linking components will use `uv sync` (or the project-specific `uv` command sequence). Replace this placeholder with the exact `uv sync` invocation and any required arguments after the workspace has been initialized by the repository owner.

Record the exact output from your `uv sync` run in this document so the team can standardize the workflow.

Linting and code quality
------------------------
We use `ruff` as the repository linter. Important policy: DO NOT run any ruff formatting commands that modify source files (for example `ruff format` or `ruff --fix`). The repository enforces check-only linting.

Run lint checks locally with the provided scripts. Use the PowerShell script on Windows and the bash script from a POSIX shell, git-bash, or inside containers.

PowerShell:

```powershell
.\scripts\lint.ps1
```

Bash / POSIX (git-bash, Linux, macOS, or inside containers):

```bash
./scripts/lint.sh
```

Both scripts will activate `.venv` (if present) and run `ruff check .`. They return a non-zero exit code on failure and do not modify files.

Pre-commit and CI
-----------------
CI must run `ruff check .` and fail on any diagnostics. Do not run `ruff format` or `ruff --fix` in CI.

Optional: Install a local Git hook that runs `ruff check .` prior to commit. If you add such a hook, ensure it only runs `ruff check` and that it fails the commit when diagnostics are present. Consider also validating that no tracked files changed after checks complete (to detect accidental formatting).

Linting enforcement notes
------------------------
Ruff does not provide a configuration setting that disables its formatting subcommands; therefore the repository relies on policy and CI enforcement. Recommended controls:

- Provide scripts for common operations (scripts/lint.ps1) and document their use.
- Use CI to run `ruff check .` and fail builds on issues.
- Optionally provide a Git pre-commit hook or a `.pre-commit-config.yaml` that runs ruff in check-only mode.

Build and deploy validation
---------------------------
Deployment manifests live in `deploy/`. The repository enforces a no-inbound-ports policy; all services should avoid `ports:` entries and communicate via the shared IPC volume.

You can validate the base compose file if Docker is available:

```powershell
docker compose -f deploy/docker-compose.yml config
```

Commit checklist
----------------

Before committing, run:

1. Activate .venv and install dev requirements (if needed)
2. .\scripts\lint.ps1  # ruff check (or ./scripts/lint.sh from a POSIX shell)
3. Run tests (when present)
4. Ensure git status is clean

If CI is configured, ensure your branch passes the CI pipeline before opening a merge/pull request.

Notes and future updates
------------------------
This guide will be updated after the first successful `uv workspace init` run so the exact workspace metadata filenames are recorded. If your `uv` installation behaves differently, please add notes here.
