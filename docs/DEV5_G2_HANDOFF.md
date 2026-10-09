# G2 handoff — v9.4-dev5-compact-read

**Checkpoint:** 2026-10-09 · **Status:** PAUSED by user after first dev3/dev5 live pilot and trace diagnosis. No feature promotion. This document is the starting point for the next session; do not restart the validation journey or silently run costly Ollama calls.

## 1. Scope, frozen evidence and boundaries

- Work **only** on the experimental branch `v9.4-dev5-compact-read` when resuming. Never modify `main`, `v9.4-dev4-observability`, or real user memory as a side effect of a benchmark.
- Dev3 baseline source pin: `a34658b81742596520da844618b5bb39f3329279`.
- Dev5 source pin used for the recent live pilot: `1f57ec16f8b4eff5bede6659762e188112d96c9c`. The current docs/handoff commits will be newer; keep **the pilot pin** in reports rather than relabeling old observations.
- Shared local environment for the two-turn pilot: Lenovo constrained CPU-only Windows host, Windows PowerShell, Ollama `0.34.4`, model `qwen3.5:4b-q4_K_M`, `think=false`, context length hint 5120. Exact model *digest*, host warm state, background load and runtime thread profile were not fully controlled/proven by the `ollama show --verbose` output.
- Two independent archived source trees, isolated config files and per-variant TEMP memory roots were prepared by `tests/Prepare-Dev3Dev5Pilot.ps1`; preflight returned `PASS=True`, two stores, four seeded synthetic facts per variant, no model calls and no production-memory access. The work used synthetic `BENCH_SERVER`, **not** the user's real hardware. Do not commit raw local trace, paths, host identity or logs.
- Latest user-reported working-tree HEAD at pilot time was `1f57ec1`; do not assume later documentation HEAD means those traces ran on the newer code.

## 2. Original question and expected architectural benefit

Dev3 delivered L2 typed factual writes, source-turn provenance, scoped history, deterministic correction and transactional writes. Dev4 added phase observability and selective L2 retrieval. Dev5's research hypothesis is **architecture-level net savings**: removing unused generated memory operations (A), redundant write-policy prompt traffic (B), repeated scans/inference and other critical-path work must save more full-turn time than any permanent dev4 observability/retrieval and dev5 coordination overhead.

This is **not** a requirement for perfect deterministic prompt heuristics. The important operational properties are (a) bounded cost of a wrong routing/optimization decision, (b) no unjustified persistent state mutation, and (c) an explanatory trace that attributes costs and failures. Avoid an expanding regex exception list just to force benchmark prompts onto an optimized path. Configuration knobs must remain host-portable; hardware-specific optimization is secondary and isolated to runtime profiles.

Research transfer context: the project's roadmap names Daniel Correa Villa's paper *Pushing Four Raspberry Pis to the Memory Wall* (DOI `10.5281/zenodo.20357376`). Treat the Raspberry Pi/edge analogy as a **motivating hypothesis**, not a reproduced result or evidence of numerical speedups on RPi5; the source title explicitly says *Four*, while earlier discussion referred informally to `5x RPi5`. Hardware/node counts, methodology and performance figures from that external paper have **not been independently verified for this checkpoint**. LFO has **not** reproduced that paper's hardware setup or measured energy, power draw, throughput-per-watt, bandwidth saturation, CPU/GPU/NPU transfer or multi-node scaling. The defensible transfer is the general principle: on constrained systems, eliminate unnecessary work and data movement first, then measure the full loop and its overhead.

## 3. Confirmed functional and measured evidence

### Dev3 / dev4 correctness
- Dev3 write-side validation passed across two Windows host classes: multi-fact typed write, correction/supersession, aliases/scopes, restart continuity and FRONTIER-derived synthesis under the guarded contract.
- Dev4 stage 1 observability, stage 2 selective L2 reads, read-only guard and scope/provenance checks passed targeted offline and isolated Qwen live cases; defaults remain OFF for L2 retrieval.

### Dev5 A/B/C and provenance mechanism
- Candidate A (opt-in compact schema) removed unused read-only output fields: one synthetic ORION trial reduced output from **294 to 45 tokens** (-84.7%); decode from 65.40 s to 13.08 s in the historical comparison. Other fresh full controls also emitted 294 tokens. This supports the mechanism, **not** a statistically repeatable full-loop speedup.
- Candidate B (separate opt-in lean-read policy, requiring A) reduced one ORION read prompt **1641 → 1042 tokens** (-36.5%). Observed A-only vs A+B answer wall **154.549 → 111.614 s**, one uncontrolled sample. Correct four-fact answer, no new L1/L2, seven unchanged SQLite rows in the tested protected read.
- Candidate C (lower-priority presentation of retrieved L2 content) passed isolated adverse-text tests, but matched C-OFF and C-ON both ignored the malicious `ALPHA` token. No incremental attack-resistance advantage has been demonstrated. C added 67 input tokens in that trial; keep OFF.
- Narrow opt-in mixed current-user evidence path passed a real Qwen turn, source-span verification and RAM64→96 history preservation across scopes; it is **not** a generalized natural-language memory extractor. Mixed unsupported statements fail closed.
- **G2 hardening 9/9 offline Windows suites PASS:** `Test-Dev5SqliteAtomicity.ps1`, `Test-Dev5MixedRuntimePersistence.ps1`, `Test-Dev5CompactRead.ps1`, `Test-LfoMemoryStore.ps1`, `Test-Dev5MixedUserProvenance.ps1`, `Test-Dev5SemanticReadBoundary.ps1`, `Test-Dev4L2Retrieval.ps1`, `Test-Dev4Observability.ps1`, `Test-PromptPolicyOptimization.ps1`. Scope/alias authorization for validated mixed writes is inside SQLite `BEGIN IMMEDIATE`; duplicate replays count as zero writes; SQL-trigger/late-failure rollback, writer lock and alias race tested. This is bounded single-store correctness, **not** a distributed transaction across L0 JSONL and SQLite.
- `Test-Dev5VsDev3Comparator.ps1` Windows synthetic-only contract self-test PASS (5 scenarios, 3 synthetic repetitions, 8 negative cases, zero real model calls). Its results are NOT performance observations.

### Measured OFFLINE component performance

`Measure-Dev5VsDev3Offline.ps1 -Repetitions 4` PASS on pinned dev3 `a34658b...` and dev5 `75e0b4b806d2016bb28571049e20712718be66aa`, separate processes/snapshots/TEMP SQLite in AB/BA order. Medians, milliseconds:

| Operation | dev3 | dev5 | median ratio change |
|---|---:|---:|---:|
| Plain-local intent | 0.3431 | 0.3854 | +12.34% |
| Preference-only intent | 0.2477 | 0.2450 | -1.09% |
| Dense operation parse | 1.0512 | 1.2255 | +16.57% |
| Four-fact write | 19.4648 | 22.6453 | +16.34% |
| Correction write | 5.5386 | 6.2618 | +13.06% |
| Four-attribute scoped read | 12.4703 | 14.0784 | +12.90% |

Separate dev5-only three-phase telemetry median **0.8116 ms**, not comparable to nonexistent dev3 telemetry. Follow-up `Analyze-Dev5VsDev3OfflineVariance.ps1` PASS reported **no operation with stable sign across all four paired observations**: slower dev5 pairs [2/4, 1/4, 2/4, 3/4, 2/4, 3/4] respectively; paired delta ranges [-18.02,+16.19], [-23.52,+3.93], [-30.34,+103.49], [-11.40,+87.43], [-8.37,+59.31], [-7.42,+36.28] percent. Hence the apparent 12–17% median micro-regressions are **noisy/inconclusive**, not proven permanent overhead, and millisecond-size next to CPU model inference. No whole-turn extrapolation.

### First two live dev3/dev5 pilot turns — exploratory, **NOT a valid A+B benchmark**

- One natural-ish, but poorly selected imperative prompt in each variant: `State BENCH_SERVER operating system, RAM in GB, disk in GB and CPU count. Reply in one short sentence.`
- Both returned the correct four synthetic values, LOCAL, `think=false`.
- **dev3:** 184.84 s answer, 1508 input tokens, 298 output tokens, 4.57 tok/s, 4 applied L2 operations (0.933 s), no L1 note.
- **dev5:** 130.54 s answer, 1517 input tokens, 234 output tokens, 4.46 tok/s, 1 applied L2 operation (0.403 s), no L1 note. Observed **-54.30 s / -29.4% answer wall**, and -64 output tokens (-21.5%), but **a single sequential pair with uncontrolled run/load cannot prove a net benefit**.
- Independent dev5 trace diagnosis: `dev4_context.l2_read_status=write_only_turn`, `l2_read_items=0`, `dev5_local_output_mode=full`, `dev5_read_policy_mode=full`, `l2_read_write_guard_active=False`, `l2_write_source=model-unmodified`, `l2_ops_model_valid_count=4`, `l2_applied_count=1`, `l2_rejected_count=0`, `l2_ops_suppressed_valid_count=0`. The pure classifier `Test-DeclarativeStateUpdatePrompt` interprets an unrecognized imperative lacking a final question mark as a declarative write. It therefore **skips actual L2 retrieval and never activates A or B**. The model emitted `SET_TEXT operating_system=Synthetic OS 13`, `SET_INTEGER ram_gb=96`, `disk_gb=512`, `cpu_count=8`; one mutation was reported applied. Exact persisted row/delta in SQLite **not yet independently audited**, so do not assert which predicate was written or falsely declare all four duplicate. The model's answer was correct but a purely read-oriented user request had an unintended model-origin mutation, contrary to the intended failure-containment goal.
- The common short L1 text was intentionally seeded in both variants and dev5 additionally had scoped L2 facts, but L2 was *not actually retrieved* in this turn. This is neither an A+B causal experiment nor a valid five-workload net comparison. Do not fix the benchmark by hand-tuning prompts until the classifier picks A+B; doing so tests a curated trigger, not real-world routing or failure costs.
- Observability succeeded: the single trace explained the decision and model-sourced write without rerunning inference. **Failure containment is incomplete** because the false read/write interpretation authorized at least one persisted operation.

## 4. What is NOT established

1. Statistically repeatable or multi-host **dev5-over-dev3 full-loop net latency gain**, including always-on dev4 telemetry overhead. This is the primary acceptance criterion.
2. General probability of A+B eligibility on natural requests; miss rates, unnecessary generation and cost of heuristic mistakes. The last live pilot unexpectedly took the fallback path.
3. Whether the observed single new L2 mutation is semantically harmless, a duplicate under a second predicate (`operating_system` vs `os`), or a provenance error; must inspect SQLite before claiming.
4. General safe write-authority under arbitrary mixed requests/uncertain paraphrases; existing rules are deliberately narrow. Prompt injection resistance beyond the bounded TITAN single-pair sample.
5. Reproducibility across host classes, order/cold-warm strata, model digests, different quantizations or heterogeneous RPi5 nodes. No power/energy and no 5x-RPi5 scaling result.
6. Representative workload frequencies or real weights for the five-case `Compare-Dev5VsDev3Workload.ps1` comparator; any unweighted/equal-weight aggregate is illustrative.
7. The source of an older `110.953s` unattributed full-schema timing anomaly. A later instrumented run did not reproduce it.
8. Universal transactional integrity across append-only L0 logs and SQLite L2; they are separate stores with warning/trace on partial failure.

## 5. Working agreement for restart

**Priority:** benchmark the *system*, not perfection of regex decisions. A+B may be measured separately on an eligible, controlled scoped-read cohort for mechanism attribution; dev3-versus-dev5 needs natural, predeclared scenarios that are not rewritten to force a path. Record whether optimization triggered; when it did not, record extra tokens, latency, persistence and error trace. Distinguish optimizer misroute (allowed cost) from unauthorized persistence (must be bounded/visible).

Suggested work order, stopping after each hard gate:

1. No inference: inspect the seeded dev5 pilot SQLite rows and the trace for the lone applied operation and source-turn history; design a cheap regression for `State BENCH_SERVER...` as a **read-request intent**, or an authorization boundary that rejects model-origin writes unless anchored in current-user asserted facts. Avoid an ad hoc new regex just for this phrase.
2. Freeze v1 **natural-language five-scenario suite** and correctness/persistence/cost rubrics before seeing model outputs; include at least one classifier-misroute case. Decide which variants have genuinely comparable evidence access; dev5-only L2 capabilities are separate functional tests.
3. Separate (a) A+B mechanistic *eligible read* attribution with identical dev5 full/compact conditions from (b) dev3/dev5 net full-loop evaluation with opt-in states disclosed. Audit `think=false`, exact Ollama model digest, context and warm/cold behavior, host load, output tokens and missing timing phases.
4. Start with one correctness-gated paired pilot on newly prepared TEMP sources; do not automatically launch thirty CPU-bound model calls. Use `tests/Compare-Dev5VsDev3Workload.ps1` only on true matched `measured` inputs and the five specified cases, not offline component reports or the misrouted single pair.
5. Keep all dev5 feature flags OFF by default; never edit production history, merge to main or claim broad acceptance based on these experiments. A negative/ambiguous finding is a valid research result, including documented non-promotion.
6. At an appropriate final dev5 checkpoint, prepare the agreed technical transferability note to the paper's author/contact listed in `docs/ROADMAP.md`, clearly noting which edge hardware was and was not used.

**Short conclusion:** dev5's architecture-first *idea* is technically credible and supported by real reductions of superfluous output and input tokens on an eligible path. A functional, observable, bounded opt-in implementation exists. The **overall performance, natural-prompt applicability, resilience to intent errors and transfer of Raspberry Pi multi-node results remain unproven**. G2 offline transactional guards work in their tested boundary; misclassified live read-request persistence highlights a distinct unmet correctness/cost gate. No additional inferencing is needed to resume work from this handoff.
