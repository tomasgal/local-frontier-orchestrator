# LFO v9.6.4 — security hardening candidate

Date: 2026-11-13

Status: **PRE-RELEASE CANDIDATE** on `security/v9.6.4-prep`. Do not treat as an accepted or immutable `v9.6.4` release until review, tests, merge and release/tag closure. The latest accepted operational runtime remains v9.6.3.

## Scope and decisions

This is a deliberately narrow supply-chain and documentation-only patch. There is no intended change to L0–L4 semantics, normal Qwen inference, FRONTIER routing, local database formats, or installed service behavior.

### 1. Codex installer integrity (implemented)

When Codex CLI is missing, `install/Install-LFO.ps1` now downloads the **upstream installer script from a specific OpenAI Codex Git commit**, rather than a moving `chatgpt.com` endpoint. Before executing the script, the bootstrap compares its SHA-256 with an expected hardcoded digest and **fails closed** on mismatch.

- Upstream: `openai/codex`
- Installer path: `scripts/install/install.ps1`
- Pinned source commit: `69231e119bfca0b14453515e97d99688ce1c47c9`
- Expected SHA-256: `9c7ec5ecb7c90718808d3ab1fc8b285f51f8c28f90c1505aadf333f96645c706`
- The script is verified *before* execution. A mismatched download is rejected; temporary installer cleanup remains in `finally`.
- Version maintenance: inspect upstream source, intentionally update both commit and digest, run a fresh Windows bootstrap test. Never silently retry with an unpinned endpoint or ignore a hash mismatch.

**Threat-model limitation:** The digest verifies the downloaded PowerShell installer script. It does not by itself attest the Codex executable subsequently fetched by that installer, its release metadata, or the original LFO bootstrap script downloaded by the README's one-line command. For full release integrity, distribute a pinned/reviewed LFO entrypoint (and consider a separately approved `Codex -Release` version and artifact verification).

### 2. GitHub Actions dependency pin (implemented)

The existing `windows-bootstrap-parse.yml` workflow retains its existing trigger policy; no always-on security scanning is added.

- `actions/checkout@v6` changed to immutable commit `df4cb1c069e1874edd31b4311f1884172cec0e10` (v6.0.3).
- `permissions: contents: read` limits the workflow token.
- `persist-credentials: false` avoids retaining checkout credentials beyond the action.
- Upgrading the action requires reviewing the new commit and updating the pinned SHA, with the version kept as a human-readable comment.

### 3. Research log and memory policy (intentionally unchanged)

L0 and trace logs may retain raw dialogue, routing, intermediate output and memory snapshots. The default research profile intentionally keeps `ResearchLogging.Enabled = true`, `IncludeRawText = true`, and `IncludeMemorySnapshots = true` for reproducibility, provenance and investigation of cognitive biases. `/clear` changes the active conversation epoch and **does not erase** historical logs or persisted L2–L4 data.

This is an explicit research trade-off. Operators should limit access to the local data directory and avoid treating `/clear` as secure deletion. No change to automatic retention, encryption or recording defaults is in this patch.

### 4. LOCAL → FRONTIER boundary (intentionally unchanged)

The existing read-only, bounded Codex invocation remains. Local LFO routing may delegate a user prompt and relevant memory/context to a remote frontier provider. Read-only sandboxing governs tool execution, **not confidentiality** of data forwarded off-device. This documented boundary is intentionally unchanged for current research, without inserting additional consent or redaction steps into the experiment.

### 5. Future security checks (documentation only)

A **manual/on-demand** security QA feature may add PowerShell-specific static analysis (`PSScriptAnalyzer`), test-fixture-aware secret scanning, dependency/SBOM checks, and targeted prompt-injection and data-flow tests. Do **not** run these on each CI execution under the current policy. Any future job should be separate and explicitly dispatched, after evaluation of false-positive rates and performance/cost.

### 6. AI Scan finding triage

AI Scan's nine alleged secrets are `related_key` references to existing `key` entries within `tests/fixtures/l4-a1-observatory/annotation-plan.json` and `tests/fixtures/l4-r2-seed/annotation-plan.json`. These are test fixture references, not credentials; preserve them and classify the findings as false positives. Checkout tag pinning is the only actionable AI Scan finding in this change set.

## Bootstrap, deployment and release policy

**No fresh bootstrap is required for an existing, working v9.6.3 installation to keep functioning.** The functional LFO runtime remains v9.6.3. The new Codex installer-integrity check applies only when the patched bootstrap is executed and the installer needs to provision Codex. It cannot retroactively secure a previously completed installation.

A fresh bootstrap or reinstall is required **only if you intend to run the revised installation workflow or deploy on a new machine**. To distribute the candidate safely, review and promote a pinned commit/tag and verify the entrypoint itself before running it. Do not relabel existing installed runtime binaries as independently validated v9.6.4.

## Acceptance criteria before release/tag

1. Review the upstream commit and recompute the expected hash from exact downloaded bytes.
2. On a Windows host with Codex absent, verify the checked script is accepted and the install proceeds.
3. Force a checksum mismatch in an isolated test and confirm the script is never executed.
4. Confirm an existing Codex installation bypasses the installer download without regression.
5. Manually dispatch the existing Windows parse workflow on the branch and confirm it passes.
6. Confirm no functional changes to default research logging or FRONTIER delegation.
7. Merge only after acceptance; then close release notes and create the **immutable** v9.6.4 tag from the accepted commit, without changing v9.6.3.

No Windows integration tests were claimed as performed by this documentation-only change.
