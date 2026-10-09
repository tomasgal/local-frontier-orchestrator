# v9.4-dev5 — architecture-first performance experiments

Status: **candidate A first isolated compact-read LIVE correctness/PERSISTENCE PASS, promising single-run performance observation; matched full-schema control still pending** (2026-10-09).
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

## First isolated LIVE compact-read trial — 2026-10-09

The user ran an isolated ORION read-only fixture with `-CompactReadSchema` on the constrained Windows CPU-only reference host: `qwen3.5:4b-q4_K_M`, Ollama 0.34.4, context hint 5120, four current ORION L2 facts / 336 injected context characters, no old L0 items, no L1. The checker `Test-Dev4L2LiveTrace.ps1` **PASS**, including correct LOCAL answer (Debian 13, 64 GB RAM, PostgreSQL 16, nightly backups enabled), `dev5_local_output_mode=compact-read`, zero proposed memory ops, zero applied/rejected L2 ops, guard active, no L1 note, seven unchanged SQLite rows. This is a **functional validation of candidate A, not a confirmed performance gain**.

| Metric | Validated dev4 full (historical isolated sample) | Dev5 compact (first isolated sample) | Compact minus full |
| --- | ---: | ---: | ---: |
| Prompt tokens | 1588 | 1641 | +53 (+3.34%) |
| Generated tokens | 294 | 45 | -249 (-84.69%) |
| Prefill seconds | 104.3436 | 112.4917 | +8.1481 (+7.81%) |
| Decode seconds | 65.4042 | 13.0807 | -52.3235 (-80.00%) |
| Model wall seconds | 189.9054 | 153.0422 | -36.8632 (-19.41%) |
| Answer wall seconds | 191.062 | 154.549 | -36.513 (-19.11%) |
| L2 retrieval seconds | 0.7748 | 0.7252 | -0.0496 |
| Context assembly seconds | 0.8566 | 0.8132 | -0.0434 |

The mechanism has direct evidence: the compact output emits no L2 ops, whereas the full output generated four unused ops that dev4 had to suppress. The **prompt grew by 53 tokens**, likely because the initial compact experiment adds a dedicated system-policy override while leaving full L2 extraction policy in place. Prefill and wall-minus-prefill/decode increased, partially offsetting decode savings. Backend cold-start, caching, CPU load and memory contention were not controlled across these historical samples; avoid claiming that the 19.11% total reduction is causal or repeatable. Notably the compact trial's reported l2_write (0.4074 s) and l1_persistence (0.8599 s) were unusually larger than the full trial (0.0487 s and 0.0249 s) despite no actual writes. This reinforces the need for controlled repeats and phase decomposition.

Next acceptance step: run a **fresh full-schema control under the same dev5 code branch**, using the same isolated fixture but without `-CompactReadSchema`, and invoke the strict trace/SQLite checker immediately after `/exit`. Save the previous compact root separately. Then run `tests/Compare-Dev5CompactRead.ps1 -FullRoot <full root> -CompactRoot <compact root>` to enforce equal model/context/expected answer and display token/time differences without rerunning Ollama. This one fresh A/B pair remains exploratory; alternate and repeat only if meaningful variance estimation is warranted.

## Follow-up full-schema control and timing anomaly — 2026-10-09

The user ran a fresh **FULL** control on the **same dev5 branch**, without `-CompactReadSchema`, matching `qwen3.5:4b-q4_K_M`, context hint 5120, identical ORION query, four L2 facts / 336 added chars, independent TEMP-only SQLite. Both full and compact passed the strict LOCAL four-fact answer, write guard, no L1 note, seven unchanged database rows, and trace-mode checks. The read-only comparator `tests/Compare-Dev5CompactRead.ps1` passed semantic screening.

| Metric | Fresh full control | Compact candidate | Compact - full |
| --- | ---: | ---: | ---: |
| Prompt tokens | 1588 | 1641 | +53 (+3.3%) |
| Output tokens | 294 | 45 | -249 (-84.7%) |
| Prefill time | 109.6928 s | 112.4917 s | +2.7989 s (+2.6%) |
| Decode time | 76.7314 s | 13.0807 s | -63.6507 s (-83.0%) |
| Measured Ollama request wall | 212.8339 s | 153.0422 s | -59.7917 s (-28.1%) |
| Turn-to-answer elapsed wall | 324.962 s | 154.549 s | -170.413 s (-52.4%) |
| L2 retrieval | 1.0494 s | 0.7252 s | -0.3242 s |
| Context assembly | 1.1756 s | 0.8132 s | -0.3624 s |

**Critical anomaly:** the full turn reports 324.962 s before persistence, yet only 212.8339 s in measured Ollama HTTP plus 1.1756 s in context assembly: roughly **110.95 s is outside these phases**. The compact trial shows only about **0.69 s** outside model/context assembly. This is not plausibly explained by L2 retrieval or normal JSON parsing without further evidence. It may reflect unmeasured request construction/response processing, process suspension or memory pressure, but the cause is **unknown**. The ~52.4% turn-wall delta must not be presented as a verified speedup. The model-request improvement (-28.1%) is closer to the changed component yet still vulnerable to run-order, model caching and host load. The token-generation reduction is the strongest reproducible mechanism-level signal; the full baseline emitted exactly 294 tokens in both observed full runs.

Follow-up instrumentation committed **after** these first live trials:
- `src/QwenChat.ps1` now measures `local_request_build` (constructing and serializing the Ollama body) and `local_response_processing` (cleaning/parsing the returned local answer and routing), in both full and compact modes. This adds only Stopwatch/phase bookkeeping, not model calls or semantic changes.
- `tests/Compare-Dev5CompactRead.ps1` reports `UntimedAnswerS`, subtracting context assembly, model wall, and, when present, request/response phases (never subtracts the nested L2 retrieval twice). It prints a **warning** when more than 10 s of answer wall is unaccounted or when old traces lack these new phases.
- `tests/Test-Dev5CompactRead.ps1` offline regression checks that both timing hooks remain present. These changes are **not yet tested on Lenovo**. The old trace gap can be quantified but cannot be retrospectively attributed to one specific pre/post-model operation.

Next: rerun offline test and read-only comparator on the **existing** two fixture roots, without Ollama. Decide whether a later instrumented alternating compact/full pair is justified to localize the 110.95-s gap and evaluate host variance. Do not repeatedly spend multiple minutes on the constrained reference host without a specific discrimination target. The production default remains disabled. Candidate A only accelerates the opt-in L2-assisted read path; whole-application dev5 net-speedup acceptance across the dev3 workload is **still open**.

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
