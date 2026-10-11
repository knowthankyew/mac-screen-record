# CodeRabbit Review — Pass 8 (Phase 9 CI & Unit Test Suite + Portfolio Master Docs)

- **Date**: 2026-10-11
- **Scope**:
  1. `mac-screen-record` (`e987fef..72cea06`, 14 files: `.github/workflows/ci.yml`, `.github/dependabot.yml`, `Package.swift`, `Tests/MacScreenRecordTests/*`, `Scripts/audit-claims.py`, `Scripts/build-app.sh`, `ROADMAP.md`, `README.md`)
  2. `portfolio-admin` (`KNOWTHANKYEW_PORTFOLIO_MASTER_BRIEF.md`, `UPKEEP.md`, `PRIVACY_TELEMETRY_SCHEMA.md`)
- **Result**:
  - `portfolio-admin` master docs: **0 Findings** (`0 Major`, `0 Minor`, `0 Trivial`)
  - `mac-screen-record` Phase 9 CI & unit tests: **0 Major**, **2 Minor**, **1 Trivial**

---

## Findings & Resolution

| # | Severity | File | Finding | Resolution |
| :---: | :---: | :--- | :--- | :--- |
| 1 | 🟡 Minor | `.github/workflows/ci.yml` | Add an explicit post-build step running `Scripts/audit-claims.py` after `build-app.sh` writes `dist/bom.json` and `bom.json`. | **Fixed**: Added `Verify Built App Bundle & Generated CycloneDX SBOM Claims Parity` step in `.github/workflows/ci.yml` and added `"bom.json"` to `candidate_boms` in `Scripts/audit-claims.py`. |
| 2 | 🟡 Minor | `.github/workflows/ci.yml` | Pin GitHub Actions to commit SHAs instead of major version tags (`@v7`, `@v4`). | **Intentional Portfolio Standard**: Matches all 12 `knowthankyew` repositories where major tags (`@v7`, `@v4`) are maintained via grouped `.github/dependabot.yml` updates (`UPKEEP.md`). |
| 3 | ⚪ Trivial | `.github/workflows/ci.yml` | Keep `contents: read` at the workflow level and scope `id-token: write` and `attestations: write` to the job level (`CWE-250`). | **Fixed**: Restricted top-level workflow `permissions` to `contents: read` and scoped `id-token: write` / `attestations: write` to `jobs.validate.permissions`. |
