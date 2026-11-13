# LFO v9.6.4 — Security hardening

**Release date:** 2026-11-13  
**Type:** backwards-compatible security maintenance release  
**Runtime:** accepted L0–L4 behaviors and Windows inference/experiment semantics inherited from v9.6.3.

## Changes

- **Verified Codex installer:** on bootstrap, when Codex is missing, download the PowerShell installer from a pinned upstream `openai/codex` commit, calculate SHA-256 and refuse execution on a digest mismatch.
- **Hardened GitHub Actions dependency:** pin `actions/checkout` v6.0.3 to its exact commit SHA, set `contents: read` for the syntax workflow and disable persisted checkout credentials.
- **Targeted security regression test:** add `tests/Test-LfoCodexInstallerGuard.ps1`, exercising the real bootstrap's integrity block under mocked network/process operations, including rejection, success and cleanup.
- **Document research exceptions:** raw conversation, memory and trace logging remain enabled intentionally; LOCAL → FRONTIER cloud delegation remains unchanged. These are research choices, not privacy/security guarantees.
- **Future security QA:** document optional manually triggered static analysis and related checks; no per-commit security scanning added.
- **Release/version metadata:** label newly checked-out/bootstrapped sources as v9.6.4. Existing working v9.6.3 installations do not require reinstall or migration.

## Validation evidence (2026-11-13)

- Windows PowerShell syntax workflow: **PASS** (manually dispatched on the security branch before release metadata changes).
- Upstream installer SHA-256 downloaded independently on Windows: **MATCH**.
- Isolated dry-run wrong-digest rejection: **PASS**.
- Actual installer `try/finally` block run with mocks: **3/3 PASS** (reject wrong digest before process execution; allow matching digest to reach mocked process; remove temporary payload).
- The release-specific workflow rechecks the PowerShell syntax and integrity-guard regression immediately before publication.

**Boundaries:** No full fresh Windows bootstrap, real reinstall of Codex CLI or end-to-end v9.6.4 runtime experiment has been performed. The hash protects the bootstrap-downloaded installer script, not every binary subsequently fetched by the upstream script or the original one-line LFO bootstrap download. Static scanner findings involving `related_key` test fixture references were established as false positives.

## Upgrade behavior

Existing v9.6.3 installations can continue running without bootstrap, migration or model re-download. The new installer verification takes effect only when the v9.6.4 bootstrap is executed and Codex CLI is absent. The installed version string changes only after adopting the new source.

For technical detail and decisions see [security hardening notes](SECURITY_HARDENING_V964.md).

## Immutability

The `v9.6.4` annotated tag should resolve to the exact release-closure commit on `main`. To obtain **actual immutable GitHub Release protection**, enable **Settings → General → Releases → Enable release immutability** *before* publishing. A named or annotated tag without that setting is not inherently immutable. The manual release workflow checks whether the resulting published release reports `isImmutable=true` and rolls back a mutable release where permitted.
