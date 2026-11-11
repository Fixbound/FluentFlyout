import yaml
import subprocess
import sys

workflow_path = r"E:\Programacion\FluentFlyout\.github\workflows\build-msix.yml"

with open(workflow_path, "r", encoding="utf-8") as f:
    data = yaml.safe_load(f)

print("1. YAML syntax: VALID")

# Verify Triggers
on_block = data[True] if True in data else data.get("on", {})
assert "workflow_dispatch" in on_block, "workflow_dispatch missing"
assert "push" in on_block, "push trigger missing"
assert "master" in on_block["push"]["branches"], "master branch missing from push"
assert "v*" in on_block["push"]["tags"], "v* tag missing from push"
print("2. Triggers: VALID (workflow_dispatch, push master, push tags 'v*')")

# Verify Setup .NET SDK step
steps = data["jobs"]["build"]["steps"]
dotnet_step = next((s for s in steps if s.get("name") == "Setup .NET SDK"), None)
assert dotnet_step is not None, "Setup .NET SDK step missing"
assert dotnet_step.get("uses") == "actions/setup-dotnet@v5", f"Unexpected setup-dotnet version: {dotnet_step.get('uses')}"
assert dotnet_step.get("with", {}).get("dotnet-version") == "10.0.x", "dotnet-version 10.0.x missing"
print("3. .NET 10 SDK setup: VALID (actions/setup-dotnet@v5 with 10.0.x)")

# Verify MSBuild setup
msbuild_step = next((s for s in steps if s.get("name") == "Setup MSBuild"), None)
assert msbuild_step is not None, "Setup MSBuild step missing"
assert msbuild_step.get("uses") == "microsoft/setup-msbuild@v3", "Setup MSBuild uses microsoft/setup-msbuild@v3"
print("4. MSBuild setup: VALID (microsoft/setup-msbuild@v3)")

# Verify PowerShell syntax of all run blocks using PowerShell AST Parser
ast_check_script = r"""
param([string]$code)
$errors = $null
$tokens = $null
$ast = [System.Management.Automation.Language.Parser]::ParseInput($code, [ref]$tokens, [ref]$errors)
if ($errors.Count -gt 0) {
    foreach ($err in $errors) {
        Write-Error "Line $($err.Extent.StartLineNumber): $($err.Message)"
    }
    exit 1
}
exit 0
"""

import re

for step in steps:
    name = step.get("name")
    run_code = step.get("run")
    if run_code:
        # Simulate GitHub Actions template engine replacing ${{ ... }} before shell execution
        simulated_run_code = re.sub(r"\$\{\{\s*.*?\s*\}\}", "mock_value", run_code)
        proc = subprocess.run(
            ["pwsh", "-NoProfile", "-Command", ast_check_script, "-code", simulated_run_code],
            capture_output=True,
            text=True
        )
        if proc.returncode != 0:
            print(f"PowerShell AST syntax error in step '{name}':")
            print(proc.stderr)
            sys.exit(1)
        else:
            print(f"5. Step '{name}' PowerShell AST syntax: VALID")

print("\nALL WORKFLOW CHECKS PASSED SUCCESSFULLY!")
