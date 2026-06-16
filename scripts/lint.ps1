param(
	[switch]$Ci
)

if (Test-Path .venv) {
	Write-Host "Activating .venv..."
	. .\.venv\Scripts\Activate.ps1
} else {
	Write-Host "No .venv found. Ensure ruff is installed and on PATH or create a .venv and install dev-requirements.txt"
}

# Run ruff in check-only mode. Do NOT run ruff format or ruff --fix.
ruff check .

exit $LASTEXITCODE
