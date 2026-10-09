# v9.4-dev5 — architecture-first performance experiments

Status: **started; candidate A implemented; all five offline suites PASS on Windows CPU-only reference host; isolated live A/B pending** (2026-10-09).
Parent checkpoint: `v9.4-dev4-observability` — stage 1 and stage 2 functionally PASS on the reference CPU-only host.
Baseline `main` remains v9.3; nothing in this plan is a release/default-performance claim.

## Measurements motivating candidate A

The validated dev4 **L2-assisted read** case returned the right four current ORION facts from a synthetic, scoped, read-only SQLite store, with empty L0/L1. Its LOCAL model spent 189.9054 s in the Ollama call (104.3436 s prefill, 65.4042 s decode, 20.1576 s wall-minus-prefill/decode), reported 1588 prompt tokens and **294 output tokens**, and correctly answered the question. L2 retrieval took 0.7748 s and total context assembly 0.8566 s. **Qwen generated four `memory_ops[]` from the retrieved data, even though the deterministic dev4 persistence guard discarded all four.** The guard also prevents persistence of L1 notes in this LOCAL L2-read mode.

Observation: the full structured LOCAL response asks Qwen to generate `route`, `answer`, `memory_note` and `memory_ops`, but **only `route` and `answer` can be used** when the dev4 read-only guard is active. Requesting the unused outputs consumes model decoding and schema-constrained prompt traffic. This is a portable architecture issue, not a Lenovo-specific optimization.

The baseline dev4 read trace cannot identify precisely how many of the 294 generated tokens belong to useless fields. Nor can a single run establish which improvements will transfer to GPU/edge hosts. In earlier dev4 runs a warm correction used much less prefill time than an initial cold turn: treat cold-start, prefill, decode and overhead as separate measurements.

## Candidate A — conditional compact read response schema

Experimental branch: `v9.4-dev5-compact-read`, based on `v9.4-dev4-observability`.

- Config: `LocalGeneration.CompactReadSchemaEnabled = $false` by default, independently of `Memory.StructuredReadEnabled = $false`.
- Enable only if **all** are true: experimental flag explicitly on, L2 retrieval enabled, and the current pre-turn L2 snapshot actually contains at least one selected fact.
- On eligible turns, Qwen's Ollama JSON schema requires **exactly `route` and `answer`**. The system prompt receives a concise override explaining that L1/L2 memory output fields must not be produced. Full validated L2 extraction policy is retained unchanged in this first experiment; shortening it would be a *separate material variable* requiring its own regression.
- The existing LOCAL/FRONTIER route handling and JSON parser accept the two-field output; memory defaults to empty. The existing independent deterministic dev4 read/write guard remains enforced before persistence and **must not be removed or weakened**.
- All other turns (read flag off, no L2 hits, correction/declarative write, normal FRONTIER synthesis) retain the full validated four-field LOCAL or three-field synthesis schema.
- Trace adds `dev5_local_output_mode` (`full` or `compact-read`), and existing Ollama counters provide prompt/output token and timing comparisons.

Hypothesis, **not yet measured**: eliminating model generation of redundant `memory_ops[]` and `memory_note` will reduce output tokens and decode time on L2-assisted reads, without added inference, SQL or changes to stored facts.

## Offline checkpoint — 2026-10-09

The user recovered the OneDrive-hosted Git checkout from an interrupted automatic repack using `git fsck --connectivity-only --no-reflogs` (integrity PASS), then checked out `v9.4-dev5-compact-read` with Git auto-maintenance disabled for that switch. All five suites PASS, no production memory: `Test-Dev5CompactRead.ps1` (**full schema 1198 chars, compact 247 chars, 951 chars removed**; unchanged LOCAL/FRONTIER parser and full write fallback), `Test-Dev4L2Retrieval.ps1` (four scoped facts, 336 L2 context chars, four echoed model ops suppressed, singleton valid/rejected suppression, zero SQLite writes), `Test-Dev4Observability.ps1`, `Test-PromptPolicyOptimization.ps1`, and `Test-LfoMemoryStore.ps1` (SQLite 3.51.1 / schema 3). Working tree clean; branch tracking correct. These are structural/semantic unit tests, **not live performance measurements**.

## Acceptance gates

1. Run `tests/Test-Dev5CompactRead.ps1` (no Ollama or production files): default full schema, two-field schema, unchanged parser and routing, full fallback with no L2 hits/disabled feature/disabled L2 read, unchanged provenance policy text, and character count difference.
2. Run existing `Test-Dev4L2Retrieval.ps1`, `Test-Dev4Observability.ps1`, `Test-PromptPolicyOptimization.ps1`, `Test-LfoMemoryStore.ps1` unchanged. These preserve dev3/dev4 semantics and isolation.
3. Compare **dev4 full schema** against **dev5 candidate A** on independently seeded, identical TEMP-only L2-read fixtures (identical prompts, Qwen model, context length and answer correctness). For every trial record schema mode, Ollama prefill/decode/generation counts, turn wall time, L2 retrieval, context assembly, route, actual answer, write-guard counters, and SQLite row counts. Distinguish cold and warm Ollama runs; alternate conditions when repeats are feasible to avoid systematically favoring one ordering.
4. Reject if route, answer, scoped facts, read-only protection, unchanged L1/L2 persistence or fallback semantics regress. A measurable reduction in schema characters is merely an offline proxy; promotion requires a **reproducible end-to-end** latency gain greater than variance. A single A/B pair is exploratory only.
5. Assess eventual **steady-state full-stack performance** against the same workload on dev3, inclusive of permanent dev4 observability overhead and any dev5 overhead. The cumulative architectural savings must exceed persistent observability costs. Optional diagnostic logging can be separately budgeted; no change to hardware-specific tuning in shared orchestration code.

## Later experiments, not implemented

- **B — prompt traffic**: conditionally omit redundant write-side L2 policy on protected read-only turns *after* candidate A semantic validation, without weakening the actual persistence guard. Benchmark prefill and prompt counts separately.
- **C — stable-prefix / context traffic**: evaluate prompt-prefix reuse and bounded changes to volatile context placement, ensuring evidence precedence, memory scope and safe guard semantics. Consider actual Ollama prompt-eval cache behavior before assumptions.
- **D — scheduling/redundant work**: evaluate whether compaction can leave the interactive critical path, and whether repeated history access, inference or serialization can be eliminated.
- Keep host-specific thread, affinity, accelerators and quantization in runtime profiles; they are secondary comparisons, not the expected reason for architectural speedups.

## Reporting and dissemination

Preserve negative findings, host profile assumptions (without publishing private host identity), sample size, cold/warm status, model context, valid fixtures, CPU/GPU hardware class and any observed semantic regressions. At dev5 completion, prepare the previously agreed short replication/transferability note and send through the verified public contact route recorded in `docs/ROADMAP.md` rather than guessing personal addresses.
