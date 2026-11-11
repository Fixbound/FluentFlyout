# E2E Test Infra: FluentFlyout Auto-Updater & CI

## Test Philosophy
- Opaque-box, requirement-driven, offline-first. No network dependency during local runs.
- Methodology: Category-Partition + Boundary Value Analysis + Pairwise + Real-World Workload Testing.

## Feature Inventory
| # | Feature | Source (requirement) | Tier 1 | Tier 2 | Tier 3 |
|---|---------|---------------------|:------:|:------:|:------:|
| 1 | GitHub Fork Endpoint Configuration | ORIGINAL_REQUEST §R1 | 5 | 5 | ✓ |
| 2 | Robust SHA-256 Regex Extraction | ORIGINAL_REQUEST §R2 | 5 | 5 | ✓ |
| 3 | Managed Async Download & Hash Check | ORIGINAL_REQUEST §R2 | 5 | 5 | ✓ |
| 4 | Decoupled Installer Script Execution | ORIGINAL_REQUEST §R2 | 5 | 5 | ✓ |
| 5 | MSIX Packaging & Manifest Compliance | ORIGINAL_REQUEST §R4 | 5 | 5 | ✓ |
| 6 | CI Workflow Syntax & Steps | ORIGINAL_REQUEST §R3 | 5 | 5 | ✓ |

## Test Architecture
- Test runner: Automated xUnit or PowerShell test harnesses in `tests/` or standalone verification scripts.
- Test case format:
  * Unit/Integration tests verifying parsing, hashing, zip extraction, and script generation.
  * Schema & syntax validation for GitHub Actions workflow YAML.
  * Build command validation (`dotnet build FluentFlyoutWPF/FluentFlyout.csproj -c "GitHub Release" -p:Platform=x64`).
- Directory layout:
  * `tests/FluentFlyout.Tests/`: Unit tests for updater services, regex parsing, SHA-256 validation.
  * `tests/e2e/`: Simulation scripts for installer launch, zip verification, and CI workflow validation.

## Real-World Application Scenarios (Tier 4)
| # | Scenario | Features Exercised | Complexity |
|---|----------|--------------------|------------|
| 1 | Normal Update Flow: Check update -> Download zip -> Verify SHA-256 -> Extract -> Generate apply.ps1 -> Verify script | F1, F2, F3, F4 | High |
| 2 | Corrupted Download Recovery: Check update -> Download invalid zip -> Hash mismatch detected -> Staging cleaned -> Error logged | F2, F3 | Medium |
| 3 | Upstream Isolation: Network error / GitHub failure -> Ensure no fallback to upstream fluentflyout.com under GitHub Release | F1 | Medium |
| 4 | Custom/Fringe Release Notes Formats: SHA-256 with variations (uppercase, with 'sha256:', with parenthesized notes) | F2 | Medium |
| 5 | CI Pipeline Validation: Validate build-msix.yml against GitHub Actions schema, verify step order, cert logic, zip structure | F5, F6 | Medium |

## Coverage Thresholds
- Tier 1: ≥5 per feature (Total ≥ 30)
- Tier 2: ≥5 per feature (Total ≥ 30)
- Tier 3: pairwise coverage of major feature interactions (Total ≥ 10)
- Tier 4: ≥5 realistic application scenarios
