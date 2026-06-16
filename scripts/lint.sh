#!/usr/bin/env bash
# lint.sh - run ruff in check-only mode
set -euo pipefail

# If a virtualenv exists, try to use it
if [ -d ".venv" ]; then
  # shellcheck disable=SC1091
  source .venv/bin/activate
fi

# Run ruff in check-only mode
ruff check .

exit $? 
