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

v9.4 is the active memory-development milestone after the validated v9.3 baseline. The current implementation checkpoint is **v9.4-dev3 (L2 structured write integration)**.

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
- a post-dev3 optimization candidate is committed but not yet runtime-validated: LOCAL temperature `0.20 -> 0.10`, L2 policy `2414 -> 917` characters, removal of an additional 871-character duplicated LOCAL rule block, and a narrow deterministic acknowledgement path that skips an answer-only retry for pure declarative updates with a valid L2 set;
- the optimization candidate includes an offline deterministic regression test, but it must still pass that test, the L2 extraction battery, and a live same-fixture benchmark on the next available host before it becomes a validated checkpoint;
- L2 retrieval into Qwen context remains pending. The next architectural step is still the read/retrieval path, but only after the prompt/policy optimization boundary is validated.

### Planned v9.4 development sequence after dev3

The existing **v9.4-dev3** boundary is completed first. The already committed post-dev3 prompt/policy optimization candidate must pass its deterministic regression, the unchanged L2 extraction battery, and a live same-fixture benchmark before the project advances. Do not mix additional performance changes into that validation boundary.

#### v9.4-dev4 — performance observability and context assembly

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

This sequence intentionally separates **dev3 correctness validation**, **dev4 observability/read-side context assembly**, and **dev5 optimization experiments** so performance gains remain causally interpretable.

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
