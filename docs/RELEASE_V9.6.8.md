# LFO v9.6.8 — Minimal epistemic provenance

**Type:** backwards-compatible Windows runtime update over immutable v9.6.7.
**Reference-host development acceptance:** 2026-11-27, Windows PowerShell 5.1, native Ollama, AMD Ryzen AI Max+ 395 / Radeon 8060S, 128 GB unified memory, Qwen 3.5 35B-A3B Q8, 16k context.

## Changes

- Runtime-owned `external_evidence_status` in existing L0 and trace rows; historical labels accompany recent and retrieved L0 context. NONE / REQUESTED / UNKNOWN are emitted; OBSERVED is reserved for instrumented external access. No truth certification.
- Dedicated interactive forced-LOCAL prompt and matching schema descriptions, without contradictory delegation instructions; deterministic guard remains authoritative. Silent ASCII epistemic rules for uncertainty, verification and recall. AUTO routing and benchmark runner mechanics unchanged.
- Separate `runtime_annotation` metadata from model context; retain the delivered answer in L0 and export. Filter the exact terminal standalone legacy LOCAL notice outside fenced code, without rewriting historical logs. L3 indexes clean context for new rows.
- Single-line chunk-driven stream heartbeat, using carriage return and newline cleanup before preview, thinking, completion or failure.
- Preserve L0–L4 semantics, L2/L3 SQLite schemas, SurrealDB, P1/P2 OFF, model configurations and tag-pinned CPU/GPU/UMA installers.

## Acceptance and evidence boundary

| Check | Result |
|---|---|
| L0 provenance LOCAL turns 46–57 | 12/12 NONE |
| Actual FRONTIER turn 58 | REQUESTED |
| Historical metadata visible in model reasoning | Observed |
| Forced-LOCAL policy, turns 59–70 | 12/12 LOCAL, zero answer recovery, complete responses in this sample |
| Explicit LOCAL web request, turn 74 | No adapter call; one wrapper notice |
| Explicit AUTO web request, turn 75 | Hard gate, Codex handoff and synthesis |
| Short implicit freshness request, turns 72–73 | Known limitation: gate missed, AUTO answered locally |
| Annotation separation and stream heartbeat | Deterministic Windows contract tests passed on development commits |
| Final heartbeat visual check / CPU and discrete-GPU live reinstall | Not independently confirmed during this cycle |

Sequential exploratory six-question diagnostics used shared persistent memory. Original v9.6.7 descriptive rubric: 9/12 (OFF) and 10/12 (ON); provenance-only: 8/10 (OFF, incomplete T6 excluded), 10/12 (ON); dedicated LOCAL plus ASCII guidance: 10/12 (OFF), 11/12 (ON). Recovery counts 2, 3, 0 across the respective twelve-turn series. These are nonvalidated descriptive scores, not causal evidence of improvement. Model errors remain possible: unsupported database claims, simulated verification, historical information represented as current, and premature structured output termination. The factual content of the external-search smoke test was not independently checked. No detector accuracy or debiasing efficacy is established. No new validator or intervention was added.

Legacy exact terminal literal examples may be indistinguishable from wrapper notices. Preview remains provisional; the heartbeat updates only when chunks arrive. No blanket reliability or performance claim. Historical releases and DOI metadata remain unchanged.

See [implementation boundaries](EPISTEMIC_PROVENANCE_V968.md), [v9.6.7](RELEASE_V9.6.7.md), and [UMA bootstrap](UMA_BOOTSTRAP.md).
