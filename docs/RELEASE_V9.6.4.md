# LFO v9.6.4 — security maintenance candidate

**Prepared:** 2026-11-13  
**Status:** proposed, NOT a tagged or published release. Review and acceptance
are required before moving or publishing any release reference. The v9.6.3
immutable tag and release validation remain untouched.

## Implemented changes

### 1. Installer and supply-chain integrity

- The optional Codex CLI auto-installer now downloads the official OpenAI
  Windows PowerShell installer script from pinned upstream Git commit
  `69231e119bfca0b14453515e97d99688ce1c47c9`.
- The script is verified **before execution** using the existing
  `Download-Verified` SHA-256 checking function. Expected digest:
  `9c7ec5ecb7c90718808d3ab1fc8b285f51f8c28f90c1505aadf333f96645c706`.
  A mismatch aborts without executing the downloaded script.
- The pinned script itself selects Codex releases, whose asset digests are
  independently checked by its upstream logic. LFO does not lock the Codex
  binary version in this patch.
- The already-existing SHA-256 verification of Ollama and SurrealDB binaries
  is unchanged.
- Source installs using Git can use `-SourceRef <40-character-commit-SHA>`
  and optionally `-ExpectedSourceCommit <same-commit-SHA>`. A mismatch
  aborts before source checkout. A mutable `-SourceRef main` remains the
  default *development* behavior and now issues an explicit warning; it
  is **not** a fully supply-chain-pinned installation.
- Without Git, the ZIP source fallback now requires both an immutable
  full commit SHA as `-SourceRef` and an independently trusted digest as
  `-SourceArchiveSHA256`. Downloaded archives are checked before
  extraction, and missing or mismatched expected values fail closed.
  This intentionally tightens the former no-Git bootstrap path.

### 2. GitHub Actions

`actions/checkout@v6` is replaced by commit-SHA pin
`d23441a48e516b6c34aea4fa41551a30e30af803` (`# v6`).
Existing workflow events/branches remain unchanged.

### 3. Deliberately unchanged research behavior

- Full conversation/trace logging, raw text and memory snapshot defaults stay
  enabled for research reproducibility.
- `/clear` continues to reset an epoch rather than deleting previous L0/L2/L3/L4
  evidence, conversation logs and trace files.
- Automatic LOCAL -> FRONTIER routing stays enabled. Codex read-only mode
  constrains writes but is not a promise that delegated prompts stay local.
- These behaviors are now made explicit in the README and implementation comments.

### 4. CI security checks — future option only

Potential manually triggered or release-candidate checks: PSScriptAnalyzer,
secret detection and prompt-injection/security regression tests. No always-on
per-push security suite is introduced.

## Deployment and version semantics

There is **no need to re-bootstrap an already working v9.6.3 installation**
for these changes: this patch changes only installer code, GitHub workflow,
configuration comments, process wrapper comments and documentation.
Existing services, model aliases, DPAPI credentials, datastore and the
operational v9.6.3 L0-L4 runtime contract remain unchanged.

The proposed `v9.6.4` label refers to a security-maintenance repository
release, not a newly installed runtime. The current installation does not
automatically become v9.6.4 simply because the source repository is updated.
For new installations after release, use the updated installation entrypoint.

## Required validation before release

1. Independently recompute SHA-256 of the immutable upstream installer file.
2. Simulate a modified installer script and prove it is rejected before execution.
3. Check `-ExpectedSourceCommit` rejects an unexpected resolved Git commit.
4. Check no-Git ZIP fallback rejects mutable refs, missing SHA-256 and altered ZIPs.
5. Check pinned `actions/checkout` commit matches the intended official upstream action.
6. Run existing Windows PowerShell 5.1 parse checks and a fresh-install smoke test.
7. Verify L0-L4 and LOCAL/FRONTIER behavioral regression boundaries.
8. Only after reviewing the PR and satisfactory tests, merge and create immutable
   `v9.6.4` tag. Do not alter the earlier `v9.6.3` tag.

**Tests above have not been executed in a Windows runtime by this change.**
