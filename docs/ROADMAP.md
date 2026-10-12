# Roadmap

## Current status â€” L2 CLOSED; L3 design next

**2026-10-12:** L2 is complete for the accepted scope at immutable tag `v9.4-l2-frozen`. The DEV3 foundation, integrity fixes and selective DEV5 A+B read optimizations are accepted. R1/R3 offline gates and the bounded R4/R5 LOCAL pilots passed. Shortened/grouped extraction candidates are not adopted; full write policy retained, C OFF.

See the [canonical closure record](https://github.com/tomasgal/local-frontier-orchestrator/blob/v9.4-l2-frozen/docs/L2_FROZEN_BASELINE.md) for exact evidence and limitations, the [DEV5 implementation/provenance summary](DEV5_IMPLEMENTATION_SUMMARY.md) for the accepted A+B mapping and research attribution, and the [fixed file manifest](https://github.com/tomasgal/local-frontier-orchestrator/blob/v9.4-l2-frozen/docs/L2_FROZEN_MANIFEST.json). `main` keeps its v9.3 runtime unchanged. No L2 retuning or repeated model benchmark is a prerequisite for future work.

Next: specify L3 semantic retrieval, entity resolution and selective reranking against the frozen L2 contract; then scope L4 epistemic mediation separately. Neither is implemented by this closure.

## Historical roadmap â€” superseded by the closure above

The older active/pending DEV3/DEV5 programme below records the development path; it is not an instruction to reopen L2.

This roadmap describes engineering directions, not release commitments.

## Active development programme â€” DEV3 + DEV5 â†’ L3 â†’ L4 (2026-10-11)

**Management assessment: successful optimization discovery and development-process refactoring.** The DEV3 and DEV5 investigations exposed a substantial opportunity to simplify how LFO is developed, validated and benchmarked. Earlier semantic-policy reductions identified the cost of losing critical extraction instructions; selective read-path experiments demonstrated that unnecessary model output and input can be eliminated on eligible paths. Repeated orchestration/test-launch failures and inconclusive whole-loop timings identified avoidable development overhead. These are actionable discoveries, not proof of a general speedup. The new bounded roadmap is expected to accelerate *implementation and decision-making* by reusing existing test gates, reducing parameter combinations and requiring fewer expensive model experiments; the acceleration itself has not yet been measured.

**Version and development policy:** `main` = frozen **v9.3 validated working/release baseline**; historical **DEV3** = immutable reference `a34658b81742596520da844618b5bb39f3329279`, with functionally validated L2 write semantics and accepted post-dev3 small optimizations; active integration/refactoring = **`v9.4-dev5-compact-read`**. DEV3 remains an active *development and comparison workstream*, not a branch to rewrite. DEV5 retains post-DEV3 authorization, transaction and read-side safety fixes. No automatic merge or feature promotion.

### Execution roadmap and gates

1. **R0 â€” Refactoring checkpoint (DONE).** Simulated Delphi-style prioritization, [issue #3](https://github.com/tomasgal/local-frontier-orchestrator/issues/3), [experimental-branch handoff](https://github.com/tomasgal/local-frontier-orchestrator/blob/v9.4-dev5-compact-read/docs/DEV5_DELPHI_REFACTOR_HANDOFF.md), 2414 â†’ 2040-character L2 policy candidate retaining five examples and static structural checks. Character savings are confirmed; semantic equivalence, Windows acceptance and net speedup are **not**.
2. **R1 â€” Cheap deterministic acceptance (NEXT).** On clean Windows checkout of the exact DEV5 commit run existing `tests/Test-PromptPolicyOptimization.ps1` and `tests/Invoke-Dev5OfflineRegressions.ps1`; TEMP-only, zero Ollama, no production memory. Fix only demonstrated defects; no new test harness.
3. **R2 â€” DEV3/DEV5 semantic gate (EXPLICIT APPROVAL FOR OLLAMA).** Run the unchanged five-case L2 extraction battery against the 2040-character candidate; inspect full entity/predicate/type/value/relation semantics, including LOCAL and post-FRONTIER evidence scope. On regression, preserve evidence and revert **only** the L2 policy to its pinned full-policy blob. Do not dilute fixtures.
4. **R3 â€” Selective DEV5 simplification (PLANNED).** Assess a coherent opt-in A+B read profile with derived schema/policy; keep separate controls only when attribution requires them. Consider explicit typed L2 updates instead of expanding special-case mixed-turn grammar, subject to user-effort and automatic-capture trade-offs. Retain write authorization, transaction guards, observability and safe misses; avoid a new intent classifier or configuration sweep.
5. **R4 â€” Isolated end-to-end integrity (EXPLICIT APPROVAL FOR MODEL RUNS).** Validate LOCAL and FRONTIER write/read/correction/mixed scenarios, independent SQLite/L1 audit, source-turn provenance and rejection behavior, using isolated TEMP state. Preserve DEV3 and v9.3 contracts.
6. **R5 â€” Bounded performance attribution (EXPLICIT APPROVAL FOR OLLAMA).** Separate eligible FULL vs A+B from frozen five-case DEV3 vs DEV5 whole-turn comparisons. Pin source, policy, model/runtime and evidence; correctness gate first, then AB/BA, controlled cold/warm state, measured A+B hit/miss rate and realistic workload weights. Expand only on evidence of useful repeatable gains; accept inconclusive/negative results.
7. **R6 â€” Architecture decision.** Accept, retain opt-in, simplify or retire candidates based on semantic integrity, net useful-turn cost and complexity budget. Preserve v9.3 main unless an explicit release decision authorizes promotion.
8. **L3 â€” Next planned milestone, to be decomposed after R1â€“R6.** Semantic retrieval, candidate linking/entity resolution and selective reranking across L0/L1/L2, without replacing authoritative provenance or adding a vector/graph database by default. After the DEV3/DEV5 gates, define L3 scope, interface contract, evaluation corpus, necessity threshold, architecture alternatives, costs and acceptance criteria **before implementation**. L3 is retained on the roadmap, not cancelled.
9. **L4 â€” Subsequent planned research/development milestone, to be decomposed after L3 planning.** Generic epistemic mediation / Local Epistemic Balancer: interaction-level bias detection and interventions, explicit control/reference conditions, reliance and calibration metrics, and preservation of a reproducible local epistemic anchor. Define research hypotheses, ethical constraints, intervention contract and separate validation gates after preceding milestones. L4 is retained on the roadmap, not cancelled; no premature coupling to DEV5 optimizations.

**Streamlining principles:** optimize whole inference calls and useful-answer quality before micro-tuning; preserve semantic contracts; treat model-free tests as distinct from live correctness and speed evidence; reuse existing scripts rather than generate large ad-hoc PowerShell launchers; eliminate redundant knobs, not necessary safety guards. No production-memory access, `main` changes or costly model runs without authorization.

## Baseline reached â€” 2026-09-29

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
- v9.1.3 memory baseline is validated on the constrained CPU-only notebook: 0â€“40 char user-delta notes, five-step 0â€“160 char normalized compaction, restart continuity, and isolated exact historical retrieval all passed.
- v9.2 single-pass micro-memory is validated on the constrained CPU-only notebook: the bounded note is produced inside the existing LOCAL answer or post-frontier synthesis inference, eliminating the separate per-turn memory-model call.
- v9.3 pressure-triggered compaction is validated for both thresholds: compact at `>=4` pending notes or `>=108` pending-note characters; empty notes and trivial repeats do not advance pressure.
- Explicit memory intent is a wrapper-level invariant in v9.3: normal implicit memory remains single-pass, while an explicit storage request may use at most one focused memory-only recovery if the single-pass note is empty.
- Invalid final-answer sentinels are recovered without regenerating the memory note; correction normalization handles `CORR`, `CORR:` and `CORR :` consistently.
- Ordinary memory persistence dropped from roughly 18â€“21 seconds in the v9.1.3 baseline to commonly about 0.01â€“0.05 seconds; five-turn compaction remains a separate inference at roughly 19 seconds.
- Preserve raw-history authority, exact retrieval, restart continuity, correction handling, and append-only research traces while evaluating single-pass semantic quality over longer real use. Treat 90% as a conservative engineering acceptance floor, not a measured reliability estimate; the current smoke suite performed materially above that floor but is not large enough to support a 99%-class statistical claim.
- Benchmark host-capacity reductions separately from the semantic change (for example smaller context/recent/retrieval budgets on constrained CPU-only hosts).
- Prevent internal retrieval turn markers such as `T34` from leaking into user-facing answers.
- Evaluate routing and synthesis over longer-term real use rather than a tiny prompt set.
- Use append-only traces for offline Local Epistemic Balancer replay and bias-analysis experiments.
- Keep host/model profiles separate; do not transplant tuned context/GPU values between machines without measurement.

## v9.4 milestone â€” L2 structured memory

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

## Humanâ€“AI bias balancing

The research track is split into a broader longitudinal/personalization program and a narrower **generic, non-personalized mediator** workstream.

Near-term research/design work for the generic mediator:

- operationalize a small number of observable interaction-level phenomena, initially emphasizing human framing / confirmation-seeking signals, model sycophancy / agreement bias, and appropriate reliance as an outcome;
- measure **bias magnitude / effect strength** relative to explicit ground-truth, neutral, balanced, or counterbalanced reference conditions rather than assigning a generic low/medium/high risk score;
- distinguish direct observations from derived psychological interpretations and keep event-scoped hypotheses out of L2 factual state and ordinary conversational memory;
- define auditable pre-response and post-response interventions such as neutral rewrites, counter-evidence requests, alternative-hypothesis prompts, critique, and verification triggers;
- define paired/counterbalanced benchmarks and metrics including false-prior agreement, sycophancy, accuracy, answer shift, counter-evidence coverage, false interventions, latency and token/call overhead;
- stabilize a technology-neutral mediator contract before coupling the implementation to still-evolving L3/L4 interfaces;
- keep authority-related effects and anthropomorphism as secondary theoretical topics until they have defensible operational measures.

Broader research work remains:

- add trace schema for reliance, verification, confidence, disagreement, interventions and outcomes;
- distinguish generic from personalized policies;
- keep content beliefs out of the first personalization model;
- develop offline replay/stress tests for confirmation-machine behaviour;
- freeze an auditable experimental configuration before human-subject testing.

See [HUMAN_AI_BIAS_BALANCER.md](HUMAN_AI_BIAS_BALANCER.md), [GENERIC_EPISTEMIC_MEDIATOR.md](GENERIC_EPISTEMIC_MEDIATOR.md), and [CANDIDATE_SOLUTION_DESIGNS.md](CANDIDATE_SOLUTION_DESIGNS.md).

## Later possibilities

- local retrieval/RAG;
- project-state manifests;
- policy-driven privacy/redaction;
- additional frontier tiers;
- write-capable tools as separate capabilities with explicit safety boundaries;
- optional training/fine-tuning from curated traces after a stable task definition exists.
