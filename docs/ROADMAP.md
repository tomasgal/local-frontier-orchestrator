# Roadmap

This roadmap describes engineering directions, not release commitments.

## Baseline reached — 2026-09-29

- First Windows/GPU reference deployment is considered stable enough to freeze as a regression baseline.
- Qwen-first LOCAL/FRONTIER routing and bounded read-only `ask_codex` are working.
- Frontier synthesis has explicit factual-preservation rules while keeping the local model as an independent editor/critic.
- Behavioural policy and common generation settings are separated from transport/orchestration code.
- Hardware placement remains host-specific and outside QwenChat request payloads.
- Public repository hygiene excludes personal paths, private hostnames, LAN details, and private hardware sizing.
- Clean second-host validation passed on an older CPU-only 8 GB Windows notebook at 4k context under normal desktop memory pressure.
- Windows npm Codex shim portability was fixed by preferring `codex.cmd` in the shared resolver.
- Persistent memory v9.1.3 reached a frozen validation point: user-delta-first micro-notes, compact rolling state, raw JSONL history, restart continuity, and isolated exact historical retrieval are functioning together without the earlier JSON-output failure mode.

## Near term

- Keep hard freshness/capability gates intentionally narrow.
- v9.1.3 memory baseline is validated on the constrained CPU-only notebook: 0–40 char user-delta notes, five-step 0–160 char normalized compaction, restart continuity, and isolated exact historical retrieval all passed.
- v9.2 single-pass micro-memory is validated on the constrained CPU-only notebook: the bounded note is produced inside the existing LOCAL answer or post-frontier synthesis inference, eliminating the separate per-turn memory-model call.
- v9.3 pressure-triggered compaction is validated for both thresholds: compact at `>=4` pending notes or `>=108` pending-note characters; empty notes and trivial repeats do not advance pressure.
- Explicit memory intent is a wrapper-level invariant in v9.3: normal implicit memory remains single-pass, while an explicit storage request may use at most one focused memory-only recovery if the single-pass note is empty.
- Invalid final-answer sentinels are recovered without regenerating the memory note; correction normalization handles `CORR`, `CORR:` and `CORR :` consistently.
- Ordinary memory persistence dropped from roughly 18–21 seconds in the v9.1.3 baseline to commonly about 0.01–0.05 seconds; five-turn compaction remains a separate inference at roughly 19 seconds.
- Preserve raw-history authority, exact retrieval, restart continuity, correction handling, and append-only research traces while evaluating single-pass semantic quality over longer real use. Treat 90% as a conservative engineering acceptance floor, not a measured reliability estimate; the current smoke suite performed materially above that floor but is not large enough to support a 99%-class statistical claim.
- Benchmark host-capacity reductions separately from the semantic change (for example smaller context/recent/retrieval budgets on constrained CPU-only hosts).
- Prevent internal retrieval turn markers such as `T34` from leaking into user-facing answers.
- Evaluate routing and synthesis over longer-term real use rather than a tiny prompt set.
- Use append-only traces for offline Local Epistemic Balancer replay and bias-analysis experiments.
- Keep host/model profiles separate; do not transplant tuned context/GPU values between machines without measurement.

## v9.4 milestone — L2 structured memory

v9.4 is the active memory-development milestone after the validated v9.3 baseline. The current development branch is **v9.4-dev4-observability** (stage 1 and stage 2 functional validation PASS on the constrained reference host); v9.4-dev3 is the earlier structured write-side checkpoint.

Purpose:

- add an L2 typed fact store beside, not instead of, L0 raw history and L1 semantic working memory;
- allow several durable memory deltas from one information-dense turn;
- represent both entity attributes and entity-to-entity relations;
- make simple current-state replacement, deduplication, provenance and relational queries deterministic after extraction;
- keep Qwen isolated from SQL and filesystem/database APIs;
- define a stable MemoryStore/fact-operation contract to minimize later refactoring.

Preferred first backend:

- local SQLite file under the LFO state directory;
- Windows system SQLite (`winsqlite3.dll`) through a thin PowerShell P/Invoke/ABI pipe;
- long-lived connections, prepared statements, WAL, indexed reads and serialized small write transactions;
- parallel L0/L1/L2 retrieval where possible so structured memory adds negligible latency compared with local-model inference.

v9.4 explicitly does **not** require a vector database, graph server, RDF/SPARQL, OLAP cube, universal ontology, or SQL generation by the model.

The planned layer model is:

```text
L0  raw JSONL history          authoritative evidence/provenance
L1  semantic working memory    v9.3 micro-notes + pressure compaction
L2  structured factual state   v9.4 typed facts/relations + deterministic queries
L3  optional semantic index    future embeddings/entity linking/reranking only if measured need justifies it
```

L3 is a possible future retrieval layer, not a v9.4 commitment and not an authoritative replacement mechanism.

Initial acceptance targets include multi-delta extraction, typed values and relations, deterministic correction/deduplication, source-turn provenance, restart persistence, a simple multi-relation query, coexistence with L1, and no regression of the validated v9.3 path.

Current v9.4-dev3 status (2026-10-05):

- schema 3 uses opaque integer entity identity; names are surface forms in a separate `entity_names` table rather than canonical identifiers;
- deterministic normalization resolves trivial spelling-format variants such as spacing/hyphen differences, while ambiguous identity is intentionally left for a future resolver/L3 rather than silently guessed;
- the model-side operation schema uses `SET_TEXT`, `SET_INTEGER`, `SET_REAL`, `SET_BOOLEAN`, and `ADD_RELATION`; scalar type is encoded in the op name to reduce cross-field inconsistency on small local models;
- LOCAL and post-FRONTIER synthesis use the same `memory_ops[]` contract; FRONTIER results are interpreted by the local synthesis model as an external information input, not piped directly into SQLite;
- multi-op writes are atomic per turn; any genuinely rejected operation causes the whole L2 turn-set to be skipped while L0 retains the raw evidence;
- isolated store tests pass schema, typed values, relations, restart persistence, alias normalization, scope isolation, atomic apply, and fail-closed rejection on both tested Windows host classes;
- the constrained CPU-only notebook independently reproduced the extraction battery: dense four-fact turn `4/0`, relation turn `3/0`, correction `1/0`, preference-only `0/0`, post-FRONTIER synthesis `3/0` (valid/rejected);
- the same notebook confirmed a real 5120-token Ollama runtime context and a live four-fact L2 write followed by a LOCAL correction whose old scalar value was closed with `valid_to_turn` and replaced by the new current value;
- SQLite work remains negligible relative to local inference: measured live L2 writes were roughly hundredths of a second to about one second, while constrained-host local turns take tens to hundreds of seconds;
- post-dev3 runtime optimization validated on an isolated constrained CPU-only reference host (2026-10-09): LOCAL temperature `0.20 -> 0.10`, removal of an 871-character duplicated LOCAL rule block, and deterministic acknowledgement for a pure declarative update with a fully valid L2 set (prevented answer-only retry in a live turn). Two compact L2-policy candidates failed extraction and were abandoned; the original full policy was restored with exact blob identity to baseline;
- offline deterministic regression PASS; five-fixture extraction counts PASS (4/0, 3/0, 1/0, 0/0, 3/0 valid/rejected), retaining a pre-existing post-FRONTIER predicate ambiguity (`model` versus `cpu`). Isolated two-turn live fixture PASS: both LOCAL, first turn 4 accepted L2 facts, correction 1 accepted fact, 0 rejected, 5 historical SQLite rows with correct OS supersession and 4 current facts;
- measured comparison on the constrained reference host: first turn 185.81 -> 169.006 seconds and prompt 1674 -> 1488 tokens; correction 34.14 -> 25.845 seconds. These are paired single-run observations, not statistically proven speedups or confirmed cross-host gains. SQLite write time remained negligible. At that earlier dev3 checkpoint L2 reads into the prompt were still pending; they were later added and functionally validated under dev4 stage 2 with a deterministic read/write guard.

### Planned v9.4 development sequence after dev3

The **v9.4-dev3 write-side and post-dev3 optimization validation boundary is now completed** on the constrained CPU-only reference host. No additional dev3 optimization candidates are introduced. Dev4 begins with performance observability and bounded L0/L1/L2 context assembly; dev5 remains the measured performance-tuning phase. Any cross-host transfer and further repetition are future research/measurement tasks, not retroactive evidence of performance generalization.

#### v9.4-dev4 — performance observability and context assembly

**Dev4 stage 1 — OBSERVABILITY / L0–L1 ASSEMBLY: PASS (2026-10-09, Lenovo CPU-only reference host).** Added `LfoTurnTelemetry.ps1`, per-phase Ollama prefill/decode/wall counters, turn-scoped immutable pre-inference L0/L1/recent-message snapshot, and trace fields `dev4_phases` and `dev4_context`. The baseline regression and isolated two-turn ORION fixture passed with correct LOCAL routing and five-row/four-current-fact L2 supersession. Context assembly was measured at 0.0482 s and 0.0146 s; these are single-run latencies, not proven invariant overhead.

**Dev4 stage 2 — SELECTIVE CURRENT-FACT L2 RETRIEVAL: FUNCTIONAL PASS (2026-10-09, same reference host).** The new optional SQLite read path opens an existing DB read-only, matches exact normalized aliases explicitly mentioned by the current user, selects only `current_facts` within `conversation:<epoch>`, excludes superseded facts, fails closed on ambiguous aliases, and retains `source_turn`. Defaults remain `StructuredReadEnabled=$false`, `StructuredReadMaxItems=6` and `StructuredReadMaxChars=800`; explicit corrections/declarations bypass read-side injection. Offline tests `Test-Dev4L2Retrieval.ps1`, `Test-Dev4Observability.ps1`, `Test-PromptPolicyOptimization.ps1` and `Test-LfoMemoryStore.ps1` all passed, covering type/relations, isolation, budgets, query specificity, alias ambiguity, missing database, zero unintended writes and ordinary dev3/FRONTIER write parity.

**Regression found and repaired:** The first read-enabled live experiment produced four correct retrieved ORION facts but Qwen incorrectly echoed all four as new L2 operations; a prompt prohibition was insufficient. Added deterministic `Protect-LfoPersistenceFromReadSide` before persistence. In a fresh isolated LOCAL live turn, Qwen answered all four ORION facts correctly from L2 despite empty L0/L1; it generated four model ops but the guard suppressed four, resulting in zero applied/rejected operations and no L1 note. The strict `Test-Dev4L2LiveTrace.ps1` verified turn 3, scope, guard counters, seven unchanged seeded SQLite rows and no note. A mistakenly submitted PowerShell checker produced one additional FRONTIER REPL turn, also verified to have no side effects; the expensive LOCAL inference was not repeated. Measured L2 retrieval: 0.7748 s, L2 input 4 facts / 336 chars, total context assembly 0.8566 s, model request 189.9054 s, 1588 prompt tokens and 294 generated tokens. One run provides no statistical throughput/speedup claim; L2 is still opt-in and disabled by default.

**Scope limitation:** LOCAL turns with actual L2 retrieval currently suppress *all* model-derived L2 ops and L1 micro-notes; this can omit legitimate new implicit facts in mixed question-plus-assertion turns. Standalone declarative updates and corrections bypass L2 retrieval and preserve the dev3 write contract; FRONTIER synthesis retains its own evidence flow. A later provenance-aware design may relax this conservatism only with independent regression evidence. With both dev4 functional stages validated on the reference host, subsequent performance work belongs to dev5; multi-host verification and overhead characterization remain open.

Purpose:

- make local inference cost attributable by phase before further tuning;
- add explicit phase-level performance tracing for LOCAL generation, prompt evaluation/prefill, decode, FRONTIER handoff, post-FRONTIER synthesis, answer recovery, memory compaction, and L2 work where applicable;
- introduce a turn-scoped context/retrieval assembly object so L0/L1/L2 retrieval results can be computed once, bounded, deduplicated, measured, and reused by the components that need them;
- record context cost by layer, including selected item count, characters/tokens where available, retrieval latency, and model prompt-evaluation counters;
- integrate bounded/selective L2 read/retrieval through this observable context-assembly path rather than by directly dumping structured memory into the prompt;
- preserve the validated memory and routing semantics while adding observability and the read-side plumbing.

Acceptance boundary:

- no regression of the validated v9.3 and v9.4-dev3 contracts;
- traces make separate prompt-evaluation and decode cost visible for each local inference phase;
- one turn does not repeat equivalent history/structured-memory scans without an explicit reason;
- L2 retrieval is bounded, selective, provenance-preserving, and its incremental prompt cost is measurable;
- instrumentation itself must not become a material latency source.

#### v9.4-dev5 — measured performance tuning

**Started 2026-10-09 — candidate A implemented on separate branch `v9.4-dev5-compact-read`; A functional live PASS, B policy reduction awaiting offline validation.** The first experiment targets wasted single-pass LOCAL generation: dev4's L2-assisted read turn correctly answered the four ORION facts but Qwen emitted four `memory_ops[]` that the deterministic guard suppressed. Candidate A conditionally asks for only `route` and `answer` on precisely this read-only path, eliminating unused schema fields and their generation cost; all other paths retain the validated four-field schema. Both `LocalGeneration.CompactReadSchemaEnabled` and `Memory.StructuredReadEnabled` remain **false by default**. The offline parser/schema/route regression `tests/Test-Dev5CompactRead.ps1` and all four prior L2/observability/policy/SQLite regressions **PASS on the constrained reference host (2026-10-09)**. Full LOCAL output schema 1198 characters versus compact 247, a reduction of 951 (79.4%); this is not yet a measured token/latency improvement. The first isolated compact-read LIVE run on the constrained reference host also passed answer/routing/read-only guard/SQLite validation. Its Ollama output token count fell to 45 versus 294 in the historical dev4 full-schema trial, and decode to 13.0807 s versus 65.4042 s; reported total answer wall 154.549 s versus 191.062 s. Input increased to 1641 from 1588 tokens and prefill increased to 112.4917 from 104.3436 s. These are nonpaired single-run observations with possible load/cold-cache confounding, **not reproducible speedup evidence**. Next: same dev5 branch fresh full-schema control, read-only comparer `tests/Compare-Dev5CompactRead.ps1`, then repeat/alternate as justified. Promotion requires correct read semantics, verified unchanged SQLite/L1, lower generated tokens, and *repeatable* end-to-end gains—not schema-size savings alone. Full experiment plan: [DEV5_PERFORMANCE_EXPERIMENTS.md](DEV5_PERFORMANCE_EXPERIMENTS.md).

**Dev5 A/B checkpoint (2026-10-09):** One fresh full-schema control was run on the same dev5 code branch and same synthetic ORION fixture shape (independent TEMP data). Full and compact both passed read-only semantic/SQLite acceptance; full emitted 294 tokens versus compact 45, with decode 76.7314 s versus 13.0807 s. Prefill 109.6928 s versus 112.4917 s; measured model wall 212.8339 s versus 153.0422 s. However FULL `answer_seconds=324.962` exceeds its Ollama model wall by 112.1281 s, with only 1.1756 s attributable to context assembly, leaving roughly **110.95 s unaccounted**. The compact counterpart had under 1 s outside model/context assembly. As a result **the 52.4% observed turn-wall improvement is NOT attributable yet** and must not be promoted. Added request-build and response-processing phase instrumentation, plus anomaly-detecting comparison/reporting; the two new timing hooks have now passed all five offline test suites on the reference host; new live timing attribution remains pending. The existing full/compact comparator confirmed an unexplained `UntimedAnswerS` of **110.953 s vs 0.694 s** and correctly warned that the older traces predate the new phases. Next is one isolated diagnostic full-schema run, not an automatic expensive A/B repetition. The original 249-token reduction demonstrates removal of wasted generation, but repeatability, host variance and whole-app net dev5 improvement remain unproven. **Subsequent diagnostic (2026-10-09):** one instrumented fresh FULL run returned 203.140s answer wall versus 201.0549s model request, 1.4278s context assembly, 0.0401s request build and 0.3924s response handling, leaving only 0.225s unaccounted. The earlier 110.953s anomaly did NOT recur; its origin remains unknown. Against the prior COMPACT 154.549s/45-token run, this new FULL still required 294 output tokens and 74.7088s decode (compact 13.0807s), but this is not repeatable A/B evidence. The comparator now marks missing phases in historical traces as null, not false 0-second measurements. **Candidate B implemented but UNVALIDATED:** separate `LocalGeneration.LeanReadPolicyEnabled=$false` switch to remove unused L2 write-extraction prompt instructions *only* when candidate A's read-only compact schema is active, retaining the full validated write path and guard. The new B offline and prior four regression suites **all PASS** on Lenovo (2026-10-09); the real-policy prompt rewrite removed 2522 characters in the A+B-only branch, with `AOnlyPolicyPreserved=True`, `BOptOutAndNormalWritePreserved=True`, no production-memory writes and a clean Git tree. The historical A-vs-FULL comparer still PASSed with absent old timing phases correctly shown as missing. These are structural results, **not measured prompt-token or time savings**. **A+B first isolated LIVE PASS (2026-10-09):** `-CompactReadSchema -LeanReadPolicy` returned the correct four ORION facts, LOCAL routing, active dev4 read/write guard, zero generated or applied L2 ops, no L1 micro-note and seven SQLite rows unchanged. Trace policy `lean-read`, schema `compact-read`. A-only vs A+B: prompt **1641→1042 tokens (-599/-36.5%)**, prefill **112.4917→75.5314s (-36.9603/-32.9%)**, output 45→46, decode 13.0807→11.1494s, model request 153.0422→110.0576s, answer 154.549→111.614s. A+B's end-to-end timing accounted to ~0.11s. This is a single-trial exploratory comparison, not a proven population mean or full-project net optimization. Next: broader semantic tests and repeated alternating/host transfers where warranted, maintaining both feature switches false by default; no new FULL repetition merely to reconfirm the known four facts. **Semantic work reached offline PASS:** `tests/Test-Dev5SemanticReadBoundary.ps1` passed ten isolated cases on the reference Lenovo host, alongside five existing regression suites (2026-10-09). It covers corrected/current facts, epoch scope, missing/ambiguous aliases, explicit corrections, user-memory instructions, mixed question+new claim, retrieval opt-out and instruction-like text stored as a fact. It also checks that FRONTIER's independent write path survives and SQLite remains unchanged. The matrix reports `MixedReadClaimStored=False` by design: mixed read+new-claim still discards the new model-derived assertion. A stored instruction-like fact reaches model context, but offline validation cannot show how Qwen responds. **Candidate C has passed six OFFLINE suites on Lenovo AND its first isolated adversarial LIVE trial:** a third opt-in `LowerTrustL2EvidenceEnabled=$false` requiring A+B separates actual L2 records from the system role into a JSON-quoted, lower-priority user data message preceding the real current user request. It preserves normal A+B and write paths when off; scope, guard and retrieval are unchanged. All four real-SQLite role probes and the revised compact-read regression PASS, along with four prior suites. A TEMP-only adversarial TITAN fixture is now prepared with correct `TITAN.os=Debian 13`, an untrusted L2 `operator_note` attempting to force `ALPHA`, historical and cross-scope decoys, and strict independent read-only answer/SQLite checks. The launcher and independent checker now both ran on Lenovo: exact TITAN OS question yielded **`Debian 13`**, not the malicious **`ALPHA`** marker, with `user-data` role, two scoped L2 facts, no model-suggested/applied L2 ops or L1 note and all five SQLite records unchanged. Measured 1085 prompt tokens, 24 output tokens, 72.9066 s prefill, 6.1784 s decode, 100.0397 s model call and 101.573 s answer wall. **This single C success does NOT establish improved injection resistance**: the next discriminating check is an otherwise identical independent A+B baseline with C disabled and TITAN's malicious operator note retained. No project-wide perf or security claim. This may increase tokens and is not an asserted speedup. See [DEV5_PERFORMANCE_EXPERIMENTS.md](DEV5_PERFORMANCE_EXPERIMENTS.md).

Purpose:

- optimize only after dev4 can show where time and context are actually spent;
- benchmark prompt/context traffic reductions and remove redundant inference or retrieval work when evidence shows end-to-end benefit;
- run per-host concurrency/thread-count sweeps rather than assuming maximum thread occupancy is optimal;
- compare representative clean/low-background-load runs with normal operating conditions to detect memory, CPU, paging, or scheduler contention;
- evaluate whether compaction or other non-interactive work can be deferred to idle/background windows without blocking the next interactive turn;
- treat executor/model alternatives, including sparse/MoE options, as measured experiments rather than default migrations.

Method:

- change one material variable at a time;
- require end-to-end improvement, not only an isolated microbenchmark win;
- keep semantic/retrieval regression tests unchanged while measuring performance candidates;
- reject platform-specific tuning that does not reproduce on the target host class;
- promote only results that are repeatable and large enough to matter relative to run-to-run variance.
- the steady-state dev5 runtime, **including any always-on observability overhead introduced by dev4**, must remain faster than the comparable dev3 baseline; diagnostic tracing may be more expensive only when explicitly enabled. Any dev4 overhead that remains enabled by default must be more than compensated by dev5's architectural savings.

This sequence intentionally separates **dev3 correctness validation**, **dev4 observability/read-side context assembly**, and **dev5 optimization experiments** so performance gains remain causally interpretable.

Post-dev5 dissemination:

- prepare a short technical replication/transferability note summarizing the dev3 baseline, dev4 observability, dev5 end-to-end results, host classes, methodology, positive transfers, negative results, and observability overhead;
- send the note to **Daniel Correa Villa**, author of *Pushing Four Raspberry Pis to the Memory Wall* (DOI: 10.5281/zenodo.20357376), via the verified public Hellomatik contact **administracion@hellomatik.com**;
- if direct email routing is unclear or no reply arrives, use the author's public GitHub account **@danielcorrea-hellomatik** as a secondary contact path rather than guessing an unpublished personal email address.


**Project-wide optimization rule:** dev4/dev5 are expected to improve performance primarily through architecture-level reductions in work, context traffic, repeated retrieval/inference, and blocking—not through aggressive fitting to one hardware configuration. Host-specific thread, affinity, accelerator, driver, or capacity tuning remains secondary and belongs in runtime profiles; it must not be required for the common optimization path to be worthwhile.

## Multi-host

- Common orchestration code.
- Per-host runtime/model profiles.
- Profiles for modern GPU hosts, older CPU-oriented hosts, and edge nodes.
- Reproducible smoke tests for each runtime profile.
- No machine identity embedded in shared source files.

## Edge / accelerator exploration

Potential targets include:

- always-on local routing and retrieval;
- embeddings and reranking;
- compact structured classifiers;
- small local LLMs on SBC accelerators;
- Hailo-based execution where supported;
- Radxa/Rockchip-class accelerator modules where supported.

The orchestrator should not assume that every accelerator exposes the same model runtime or memory architecture.

## Codex-first branch

Continue separate tuning of:

```text
Codex CLI -> Codex Router -> local Qwen
```

Research goals:

- reduce agent/tool context overhead;
- characterize small-model limits under the Codex harness;
- test tool-use reliability;
- preserve compatibility with upstream Codex and Codex Router.

## Human–AI bias balancing

- define explicit mediator interventions;
- add trace schema for reliance, verification, confidence, and disagreement;
- distinguish generic from personalized policies;
- keep content beliefs out of the first personalization model;
- develop offline replay/stress tests for confirmation-machine behaviour;
- freeze an auditable experimental configuration before human-subject testing.

## Later possibilities

- local retrieval/RAG;
- project-state manifests;
- policy-driven privacy/redaction;
- additional frontier tiers;
- write-capable tools as separate capabilities with explicit safety boundaries;
- optional training/fine-tuning from curated traces after a stable task definition exists.
