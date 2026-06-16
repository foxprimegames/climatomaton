# Climatomaton

Purpose
-------
Climatomaton is a monorepo that hosts the components, libraries, tools, and deployment manifests for the Climatomaton project. This repository contains the source and orchestration artifacts used to build, test, and run the system described in the docs/architecture/ folder.

Contents
--------
- apps/     — top-level runnable applications
- libs/     — reusable libraries shared across apps
- tools/    — developer tooling and helper scripts
- deploy/   — deployment and orchestration manifests (docker-compose templates)
- docs/     — architecture, design documents, and developer guide

High-level architecture
-----------------------
- No inbound network ports are exposed by services inside this repository (see docs/architecture/ for details).
- All containers communicate via a shared IPC volume when deployed; this repository includes a base compose template that enforces that policy.

For full details see docs/architecture/architecture.md — the system is stateless, does not expose inbound ports, and uses file-based IPC over a shared volume for component communication.

Quick start
-----------
See docs/DEVELOPER_GUIDE.md for developer setup, environment prerequisites, and detailed workflow instructions.

Contributing
------------
Please consult docs/DEVELOPER_GUIDE.md for contribution guidelines, code standards, and the commit checklist used by the project.
