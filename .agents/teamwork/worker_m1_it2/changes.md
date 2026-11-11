# Changes Implemented: Multi-Tier SHA-256 Regex & SemVer 2.0.0 Version Normalization

**Agent**: Worker M1 Iteration 2  
**Date**: 2026-11-10  
**Target File**: `FluentFlyoutWPF/Classes/Services/UpdateCheckerService.cs`  
**Milestone**: M1 - Auto-Updater Refactoring & Hardening (Iteration 2)  

---

## 1. Summary of Modifications

In `FluentFlyoutWPF/Classes/Services/UpdateCheckerService.cs`:

### Change 1: 4-Tier Checksum Regex Hierarchy (Lines 40–54)
- Replaced the previous single, vulnerable `Sha256Regex` with a prioritized 4-tier hierarchy:
  1. `Sha256WorkflowRegex`: Strict, line-scoped regex matching CI workflow lines (`(?im)^[^\r\n]*?\bgithub\s+release\s+x64\b[^\r\n]*?\b([0-9a-fA-F]{64})\b`).
  2. `Sha256X64Regex`: Line-scoped regex matching mentions of `\bx64\b` alongside checksum keywords (`checksum`, `sha-?256`, `hash`, `digest`) or delimiters (`:`, `|`) with Markdown compatibility (`(?im)^[^\r\n]*?\bx64\b[^\r\n]*?(?:checksum|sha-?256|hash|digest|[|:])[^\r\n]*?\b([0-9a-fA-F]{64})\b`).
  3. `Sha256FallbackRegex`: Fallback line-scoped regex for single-arch releases (`(?im)^[^\r\n]*?\b(?:sha-?256|checksum)\b[^\r\n]*?\b([0-9a-fA-F]{64})\b`).
  4. `Sha256GenericRegex`: Static compiled generic 64-hex fallback (`\b([0-9a-fA-F]{64})\b`).
- **Defects Eliminated**:
  - Eliminated multi-architecture checksum collision where an ARM64 checksum preceding an x64 checksum was mistakenly captured.
  - Eliminated 65+ character truncation vulnerability by enforcing word boundaries (`\b([0-9a-fA-F]{64})\b`).
  - Supported Markdown decorators (backticks, bold headers, tables) without multiline spanning across changelog text.

### Change 2: Asset Parsing Priority Update in `ParseInstallerAsset` (Lines 243–268)
- Updated `ParseInstallerAsset` to evaluate the 4 tiers sequentially (`Sha256WorkflowRegex` -> `Sha256X64Regex` -> `Sha256FallbackRegex` -> `Sha256GenericRegex`).
- Preserves explicit x64 installer asset matching and robust digest extraction.

### Change 3: SemVer 2.0.0 Delimiter Handling (`CleanVersionString`) (Lines 320–330)
- Replaced `v.IndexOf('-')` with `v.IndexOfAny(['-', '+'])` followed by trimming.
- Build metadata (e.g. `+build123`) is stripped properly along with prerelease identifiers for base version extraction, avoiding parsing failures in `System.Version`.

### Change 4: Strict 4-Part Normalization (`NormalizeVersion`) (Lines 400–419)
- Implemented `NormalizeVersion(string cleaned, out Version version)` supporting 1 to 4 parts.
- Enforces strict numeric validation on every token (`int.TryParse(parts[i], out nums[i]) && nums[i] >= 0`). Invalid strings such as `"invalid"` fail immediately and return `false` rather than defaulting to `0.0.0.0`.
- Missing parts default to `0`, ensuring `2.16`, `2.16.0`, and `2.16.0.0` all produce `Version(2, 16, 0, 0)` with revision `0` instead of `-1`.

### Change 5: SemVer 2.0.0 Prerelease Extraction and Comparison (`ExtractPrerelease` & `ComparePrerelease`) (Lines 332–398)
- Added `ExtractPrerelease` to isolate the prerelease tag while discarding build metadata.
- Implemented `ComparePrerelease` conforming to SemVer 2.0.0 §11:
  - Dot-separated identifiers compared left-to-right.
  - Numeric identifiers compared numerically via `long.TryParse`.
  - Non-numeric identifiers compared lexically (case-insensitive ASCII).
  - Numeric identifiers have lower precedence than non-numeric identifiers.
  - Identifier count breaks ties.

### Change 6: Upgraded `IsNewerVersion` Semantics (Lines 287–318)
- Guards against null or whitespace remote versions.
- Evaluates base versions via `NormalizeVersion`.
- Handles base version matches:
  - Prerelease to stable (`v2.16.0-beta.1` -> `v2.16.0`) evaluates to `true`.
  - Stable to prerelease (`v2.16.0` -> `v2.16.0-beta.1`) evaluates to `false`.
  - Prerelease to newer prerelease (`v2.16.0-beta.1` -> `v2.16.0-beta.2`) evaluates to `true`.
  - Stable to identical stable (`2.16.0` vs `2.16.0.0`) evaluates to `false`.

---

## 2. Verification Summary

1. **Compilation**:
   `dotnet build E:\Programacion\FluentFlyout\FluentFlyoutWPF\FluentFlyout.csproj -c "GitHub Release" -p:Platform=x64`
   - Result: Succeeded (Exit code 0, 0 errors, 0 warnings in `UpdateCheckerService.cs`).

2. **Challenger 1 Adversarial Harness**:
   `pwsh -File "E:\Programacion\FluentFlyout\.agents\teamwork\challenger_m1_1\test_harness.ps1"`
   - Result: **52/52 Tests PASSED (100% Pass Rate, 0 Failures)**:
     - Area 1 (Regex & Asset Parsing): 19/19 PASS
     - Area 2 (Version Comparison & SemVer): 25/25 PASS
     - Area 3 (Cryptographic SHA-256 Integrity): 6/6 PASS
     - Area 4 (Decoupled Script Generation & Syntax): 2/2 PASS
