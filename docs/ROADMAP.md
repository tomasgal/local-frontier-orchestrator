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

v9.4 is the active memory-development milestone after the validated v9.3 baseline. The implementation remains on branch `v9.4-l2-structured-memory`; `main` stays on the validated v9.3 runtime until the v9.4 boundary is ready for promotion.

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

Current development status (2026-10-05):

- **v9.4-dev3 write-side validation is complete across two host classes**: a desktop reference host and a constrained CPU-only 8 GB notebook independently passed the schema-3 store path, typed values/relations, duplicate suppression, restart persistence, scope isolation, atomic fail-closed multi-op application, source-turn provenance, and scalar supersession;
- the constrained notebook also reproduced the structured extraction battery with no rejected operations and confirmed a real 5120-token Ollama runtime context;
- measured L2 SQLite writes remain negligible relative to local-model inference (roughly hundredths of a second to about one second versus local turns taking tens to hundreds of seconds);
- a **post-dev3 prompt/policy optimization candidate is implemented but not yet runtime-validated**: LOCAL temperature `0.20 -> 0.10`, L2 extraction policy `2414 -> 917` characters, removal of an additional 871-character duplicated LOCAL rule block, and a narrow deterministic acknowledgement path that avoids a second local inference for pure declarative updates that already produced a fully valid L2 operation set;
- before beginning the L2 read path, the optimization candidate must pass its offline regression, the unchanged extraction battery, and a same-fixture live benchmark on the next available host;
- **L2 read/retrieval injection into Qwen context remains pending** and is the next architectural boundary after this tuning pass.

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
