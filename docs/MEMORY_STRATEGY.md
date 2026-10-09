# Memory strategy

This document explains the **design rationale and evolution strategy** for conversational memory in Local Frontier Orchestrator (LFO).

For implementation details, storage layout, trace fields, and validated timings, see [MEMORY_AND_LOGGING.md](MEMORY_AND_LOGGING.md).

## Design problem

LFO needs persistent conversational continuity while remaining useful on small local models and constrained hardware.

The memory layer therefore has to balance several competing requirements:

- retain useful conversational state across process restarts;
- avoid treating every question as something worth remembering;
- preserve exact historical facts even when compact summaries are lossy;
- avoid adding another expensive LLM inference to every turn;
- keep context injection small enough for local models;
- support corrections without silently treating old and new values as simultaneously true;
- remain inspectable and auditable for research;
- scale from CPU-only hosts to GPU and multi-user deployments.

The central design principle is:

> **Memory is a bounded orientation layer over an authoritative raw history, not a replacement for that history.**

## What should be remembered?

Not every turn creates useful conversational state.

Examples such as:

- "What is 2 + 7?"
- "What is the chemical symbol for iron?"
- "Why is the sky blue?"

usually need an answer, but normally do **not** create durable conversational memory.

By contrast, turns such as:

- "Server ORION uses Debian 12."
- "Low RAM use is the priority."
- "We decided to keep the router local-first."
- "Correction: ORION now uses Ubuntu 24.04."

change the state of the conversation and should normally be remembered.

The memory layer therefore treats **durable conversational delta** as the scarce resource. A turn with no durable delta should create no memory pressure.

This distinction is deliberately semantic rather than purely based on prompt length. A short sentence may contain an important decision; a long question may contain no durable user state.

## Layered architecture

LFO separates conversational memory into layers with different roles.

### 1. Recent raw turns

A bounded number of the newest user/assistant turns are kept verbatim in context.

Purpose:

- preserve local conversational coherence;
- resolve pronouns and follow-ups;
- avoid summarizing very recent detail too early.

### 2. Single-pass micro-memory

Each LOCAL answer or post-FRONTIER synthesis can emit a short machine-only `memory_note` in the **same model inference** as the user-facing answer.

The current structured contract is intentionally small:

```text
route
answer
memory_note
```

The wrapper displays only `answer` and persists the cleaned note.

The note is bounded to 40 characters and is intended to capture only the new durable conversational delta. Explicit replacements/corrections use a `CORR` signal plus enough target identity to make the replacement unambiguous.

### 3. Pending buffer and rolling state

New durable micro-notes accumulate in a small pending buffer. They are periodically compacted into a short rolling state.

The rolling state is for orientation:

- active entities;
- current goals;
- constraints;
- decisions;
- preferences;
- latest corrected values.

It is intentionally lossy and bounded.

### 4. Authoritative raw history and exact retrieval

Every completed turn remains in append-only conversation JSONL.

This raw history is the authoritative source for exact historical facts. A lightweight retriever can re-inject older verbatim snippets when the rolling state is insufficient.

This separation matters:

```text
rolling state -> "what are we doing?"
raw history   -> "what exactly was said?"
```

## Why single-pass memory?

The v9.1.3 design used a separate local-model call after every answer to extract a micro-note.

On the constrained CPU validation host, that separate extraction commonly cost roughly **18–21 seconds per completed turn**.

v9.2 moved micro-note generation into the existing answer/synthesis inference using schema-constrained structured output.

Observed ordinary memory persistence then fell to roughly **0.01–0.05 seconds** on the same host, apart from occasional local I/O outliers.

This is not only a slow-CPU optimization. Removing one inference per conversational turn also reduces:

- prompt evaluation work;
- decode work;
- scheduler/request overhead;
- energy use;
- contention in multi-user deployments.

The absolute latency saving becomes smaller on faster GPUs, but the architectural efficiency gain remains.

## Why schema-constrained output instead of a text marker?

A natural design is a hidden tail such as:

```text
[MEMORY: ...]
```

Sonzai publicly documents a closely related dual-output pattern: the same LLM call produces the user-facing reply plus a hidden memory description, avoiding a second roundtrip.

LFO tested the same general class of solution with a text marker. On the validated Qwen 3.5 4B setup, marker compliance was not reliable enough: the model sometimes omitted the marker or produced an incorrect empty note even when generation completed normally.

LFO therefore moved the machine channel into an Ollama JSON Schema.

The schema improves **structural reliability**:

- required fields are present;
- route values are constrained;
- memory-note length is bounded;
- the user-facing answer can be separated deterministically.

It does **not** make semantic extraction infallible. The small model can still occasionally miss a durable fact or over-tag a correction.

## Corrections are operations, not just similar text

A correction such as:

```text
ORION used Debian 12.
Correction: ORION now uses Ubuntu 24.04.
```

must not be treated as two equally valid facts.

For this reason explicit replacements carry a `CORR` signal and target identity. The compaction layer can then replace the obsolete value instead of keeping both.

This is also why embedding similarity is not the primary merge mechanism. "Debian 12" and "Ubuntu 24.04" are semantically similar, but the important information is precisely that one value supersedes the other.

## v9.3 direction: pressure-triggered compaction

v9.2 compacts after a fixed number of completed memory steps.

That is simple, but it confuses **conversation length** with **memory pressure**. Five trivial questions can trigger compaction even when the pending memory contains almost nothing.

v9.3 changes the trigger model:

- an empty micro-note (`-`) does not increase memory pressure;
- a trivial repeat of already-known state should not increase memory pressure;
- compaction is triggered by pending-buffer occupancy rather than raw turn count;
- both **item count** and **character count** act as pressure thresholds.

The initial development thresholds are:

```text
4 pending notes
OR
108 pending characters
```

whichever comes first.

The two thresholds represent different kinds of pressure:

- many short deltas;
- fewer but denser deltas.

This allows a hundred stateless factual questions to pass without compaction, while a dense project conversation can compact quickly.

## Long and information-dense user turns

Prompt length alone is not a sufficient compaction trigger.

A long user message may contain many durable facts, but the current v9.2/v9.3 micro-memory contract still emits only one bounded note. Compacting that one note earlier cannot recover facts that were never extracted.

A future high-density-turn design should therefore consider:

- multiple micro-deltas in one structured output;
- typed/keyed memory operations;
- deterministic parsing for selected structured domains.

This is a separate problem from compaction scheduling.

## Memory layers: L0–L3

LFO memory should evolve as **complementary layers with different semantics**, not as repeated replacements of one storage format by another.

### L0 — authoritative raw history

L0 is the append-only conversation/research history already stored in JSONL.

Properties:

- authoritative record of what was actually said and observed;
- lossless relative to the captured conversation event;
- never replaced by compacted or structured state;
- source for exact historical retrieval and provenance;
- potentially large, but not injected wholesale into the model context.

L0 answers the question: **"What exactly happened?"**

### L1 — semantic conversational working memory

L1 is the current v9.3 memory path:

- same-pass bounded micro-notes;
- pending-note pressure buffer;
- pressure-triggered semantic compaction;
- bounded rolling working state;
- recent-turn context and selective exact retrieval from L0.

L1 is intentionally lossy. Its purpose is orientation and continuity, not database-grade state representation.

L1 answers: **"What should the conversation keep actively in mind?"**

### L2 — structured factual state

**v9.4 is the L2 milestone.**

L2 represents durable facts and relations that benefit from deterministic update/query semantics. The logical model is a small typed fact store rather than a nested JSON dictionary tied to one schema.

Logical fact forms are conceptually:

```text
(subject, predicate, object-entity)
(subject, predicate, typed-literal)
```

Examples:

```text
Core     type       computer
Core     has_gpu    GTX1050
GTX1050  vendor     NVIDIA
Core     ram_gb     32
ORION    os         Ubuntu 24.04
```

The goal is to stabilize the **logical contract** early so the physical backend can change later without rewriting LFO memory semantics.

L2 answers: **"What structured state is currently known, and how is it related?"**

### L3 — optional associative/semantic retrieval layer

L3 is **not a committed v9.4 feature** and is not another authoritative store.

If real use demonstrates that lexical retrieval and explicit entity/predicate matching are insufficient, L3 may later add:

- embeddings for semantic candidate retrieval;
- entity linking and alias matching;
- reranking;
- similarity-based discovery across L0/L1/L2.

L3 must not decide exact replacement semantics. For example, semantic similarity must not determine whether `Debian 12` was superseded by `Ubuntu 24.04`; that remains an L2 state/provenance operation.

L3 answers: **"What potentially relevant memory should be considered?"**

The intended authority ordering is therefore:

```text
L0 raw history        authoritative evidence/provenance
L1 working memory     lossy conversational orientation
L2 structured state   deterministic current factual state
L3 semantic index     optional candidate-finding layer
```

L3 may be added only if measured retrieval failures justify its extra complexity.

## v9.4 milestone — L2 structured memory

### Why v9.4 exists

v9.3 solves the latency and scheduling problems of conversational memory, but its side channel still has a deliberate information-capacity limit: one short semantic micro-note per turn.

That is sufficient for many conversations, but a single information-dense turn may contain several independent durable facts:

```text
ORION uses Ubuntu 24.04,
PostgreSQL 16,
64 GB RAM,
and nightly backups.
```

A single 40-character micro-note cannot reliably preserve all four facts in active memory. L0 still preserves the original turn, but L1 may omit part of the durable state and later depend on successful raw-history retrieval.

Similarly, textual correction/deduplication remains probabilistic even after the v9.3 hardening. A structured state such as:

```text
ORION.os = Ubuntu 24.04
```

can be updated and queried deterministically once the extraction step has produced the correct operation.

v9.4 therefore targets the **representation and execution gap between semantic working memory and authoritative raw history**.

### Goals

v9.4 should:

1. **Capture multiple durable deltas from one turn.**
   A single answer/synthesis inference may emit several structured memory operations instead of being limited to one representative micro-note.

2. **Represent both attributes and relations.**
   The logical model must support typed literals such as `ram_gb = 32` and entity relations such as `Core has_gpu GTX1050`.

3. **Provide deterministic current-state updates.**
   Once an operation is accepted, simple state changes must not require an LLM compaction call to decide how to merge them.

4. **Preserve provenance and history.**
   Structured current state must retain a link to the source turn and must not erase L0 history. Superseded values should remain reconstructible.

5. **Support relational-style queries without exposing SQL to Qwen.**
   Selection, projection, joins, and simple aggregation should be possible through a small MemoryStore API. Qwen produces/consumes structured memory intents, not raw SQL.

6. **Keep the storage abstraction stable.**
   LFO code above the MemoryStore boundary should depend on the fact/operation model, not on SQLite-specific details.

7. **Keep latency off the Qwen critical path where possible.**
   Structured reads needed to construct the Qwen prompt are critical-path operations; unrelated persistence/logging should not delay generation unnecessarily. Reads from L0, L1 and L2 may be fanned out in parallel before context assembly.

8. **Remain install-light on Windows.**
   The preferred first backend is the Windows-provided SQLite engine (`winsqlite3.dll`) accessed through a deliberately thin PowerShell interop layer. The interop layer is a pipe, not an ORM or business-logic wrapper.

### Preferred physical design

The preferred v9.4 backend is a local SQLite database such as:

```text
%LOCALAPPDATA%\LocalFrontierOrchestrator\state\l2-memory.db
```

The logical schema should be capable of representing:

- opaque entity identities independent of any supposedly canonical name;
- one or more observed surface names / aliases for an entity;
- predicates;
- entity-to-entity relations;
- typed scalar values;
- current validity;
- source turn / provenance;
- historical supersession.

The physical schema is an implementation detail and may evolve without changing the logical MemoryStore contract.

For performance and concurrency, the initial implementation should prefer:

- long-lived database connection(s), not open/close per lookup;
- prepared statements for common operations;
- WAL mode where supported;
- separate read and serialized write paths;
- small atomic transactions for multi-delta turns;
- indexes on the access paths actually used by LFO;
- no materialized Cartesian products when a selective join/query plan can be used.

The SQLite native interop should expose only the small ABI surface needed by the store (open/close, prepare/bind/step/finalize, column reads, errors/exec). Memory semantics stay in PowerShell above that pipe.

### Critical-path behavior

The intended turn topology is:

```text
                     +-- L0 exact/raw retrieval --+
User prompt ----------+-- L1 working memory -------+--> context assembly --> Qwen
                     +-- L2 structured query -----+
                     +-- hard deterministic gates -+

Qwen result
   |
   +--> user-facing answer
   |
   +--> structured memory operations --> serialized L2 transaction
   +--> unstructured durable delta  --> existing L1 pressure path
```

For an **explicit memory request**, LFO should not claim successful persistence until the required memory transaction has committed.

For ordinary implicit memory, implementation may minimize visible post-answer latency while preserving ordering and durability invariants.

### Why SQLite belongs specifically in L2

SQLite is not being introduced as a replacement for conversational memory or as the authoritative record of the conversation. Each layer has a different job:

- **L0 JSONL** preserves the raw evidence/provenance of what the user, local model, and frontier path actually produced;
- **L1** keeps a small lossy semantic orientation state for conversational continuity;
- **L2 SQLite** holds facts whose semantics benefit from typed values, relations, deterministic replacement, joins, indexes, atomic transactions, and reconstructible history;
- **L3**, if later justified, may help resolve aliases, ambiguity, fuzzy mentions, or semantic candidates, but it must not silently redefine L2 state.

The local model therefore never needs to know SQL and does not need to decide that a particular spelling is a "canonical name". It emits a semantic operation over surface mentions. The wrapper resolves those mentions to opaque entity IDs and applies accepted operations through the MemoryStore boundary. Post-FRONTIER synthesis follows the same rule: frontier output is an external information input to Qwen synthesis, and only the synthesis pass emits the L2 operations for that turn.

This division is why an embedded relational engine is useful even at small scale: the value is not dataset size but deterministic state semantics, relational queries, provenance, and transactions without adding a database server or exposing storage machinery to the model.

### v9.4-dev3 implementation checkpoint — updated 2026-10-05

The structured **write** boundary is now validated across two materially different Windows host classes:

- schema 3: `entities(id, entity_type, ...)` plus `entity_names(entity_id, name, normalized_name, source_turn, ...)`;
- entity names are mentions/surface forms, not identity keys;
- trivial normalization handles formatting variants; unresolved ambiguity is not guessed;
- typed scalar and entity-relation writes use one atomic transaction per user turn;
- source turn and conversation scope are persisted;
- scalar replacement closes the previous current fact through `valid_to_turn` and inserts the new current value;
- a mixed valid/rejected operation set is fail-closed for L2 rather than partially written;
- LOCAL and synthesis structured outputs share one `memory_ops[]` contract;
- the desktop reference host validated live atomic persistence and scalar supersession;
- a constrained CPU-only 8 GB notebook independently passed the complete store regression and reproduced the L2 extraction battery with no rejected operations, then live-wrote four facts and correctly superseded one scalar value on a LOCAL correction;
- the notebook also reproduced the narrow Qwen integer serialization quirk (`"{32}"`) already seen on the desktop host, and the deterministic brace-wrapped-integer normalization handled it as designed;
- measured SQLite write time remains negligible compared with local-model inference, so current optimization work targets prompt/model overhead rather than storage.

**Post-dev3 optimization checkpoint — isolated CPU-only end-to-end PASS (2026-10-09):**

- LOCAL generation temperature is reduced from `0.20` to `0.10`;
- the originally validated full L2 extraction policy is retained: compact policy variants failed the unchanged extraction battery, including typed validation and semantic fidelity;
- an additional 871-character duplicated LOCAL structured-output instruction block is removed;
- a conservative wrapper detector permits a deterministic acknowledgement instead of a second full local inference only when a pure declarative state update already produced a non-empty, fully valid L2 operation set;
- the offline regression checks syntax, restored full-policy contract anchors, temperature, and positive/negative declarative-fallback fixtures; it passed on the reference host.

**Validation evidence (2026-10-09):** both shorter L2-policy candidates failed the unchanged extraction battery, so the original full policy was restored with exact Git blob identity to the validated baseline. Offline regression PASS; extraction counts PASS for multi-attribute 4/0, relation 3/0, correction 1/0, no-L2 0/0, and post-FRONTIER 3/0 (valid/rejected). The post-FRONTIER CPU-model predicate ambiguity remains an observed semantic limitation of the baseline rather than a new regression. An isolated CPU-only 5120-context two-turn live test stayed LOCAL, wrote 4 typed facts followed by 1 corrected OS value, and verified the SQLite state: 5 total historical rows, 4 current rows, original OS closed at turn 2, and the other 3 facts preserved. On the first turn the model returned an invalid answer; `local-declarative-ack` supplied `OK.` without launching a second answer-only inference. The first turn measured 169.006 s, 1488 prompt tokens, 269 generated tokens and 1.471 s L2 write versus prior 185.81 s, 1674 prompt tokens, and 1.189 s L2 write. The correction measured 25.845 s and 0.028 s L2 write versus prior 34.14 s and 0.031 s. Production memory was not used. These are single-run end-to-end observations, not statistically reliable throughput/speedup estimates; cross-host performance transfer remains untested. L2 reads into prompt construction and phase-level observability remain dev4 work.


### Non-goals for v9.4

v9.4 is **not** intended to:

- replace L0 raw history;
- replace L1 semantic working memory;
- store every sentence or assistant answer as structured state;
- build a universal ontology or knowledge graph;
- require Neo4j, RDF/SPARQL, OLAP cubes, or a database server;
- expose SQL generation to Qwen;
- introduce a vector database by default;
- use embeddings to decide exact corrections;
- guarantee that an LLM-extracted fact is objectively true;
- optimize for millions of enterprise records before LFO has such a workload;
- implement a full Datalog/WCOJ engine merely for theoretical elegance.

### Main threats and failure modes

1. **Wrong extraction becomes hard state.**
   A model may attach a value to the wrong entity or predicate. Deterministic storage makes a wrong extraction consistently wrong, so structured writes must be conservative and observable.

2. **Predicate fragmentation.**
   `db`, `database`, and `database_engine` can become separate predicates unless canonicalization rules are introduced carefully.

3. **Overwriting valid state.**
   A mistaken `set` operation can replace a correct current value. Provenance and historical validity are therefore part of the model from the beginning.

4. **Schema side-channel overload.**
   Asking a small local model to emit too many independent control fields can degrade answer quality. v9.4 should keep the structured output narrow and measured.

5. **Premature ontology work.**
   The project should stabilize generic fact semantics, not attempt to predefine every possible entity type or predicate.

6. **Storage abstraction leakage.**
   SQLite-specific SQL or row layouts must not spread through QwenChat and higher-level memory logic.

### What happens if L2 is never implemented?

Nothing catastrophic. v9.3 remains a valid architecture:

- L0 retains complete raw history;
- L1 provides bounded conversational continuity;
- exact retrieval can recover facts that were omitted from rolling state.

The cost is that information-dense turns remain lossy at the active-memory layer, corrections/deduplication remain partly semantic, and more future queries depend on successful retrieval from raw history.

L2 is therefore an **efficiency, precision, and state-management improvement**, not a prerequisite for LFO to function.

### v9.4 acceptance direction

The first v9.4 development build should demonstrate at least:

- multiple durable facts extracted from one turn;
- two different entities updated in one turn;
- typed scalar and entity-relation facts;
- deterministic replacement of one current attribute;
- duplicate structured fact suppression;
- provenance back to the source turn;
- persistence across restart;
- a multi-relation query such as "which computers have an NVIDIA GPU?";
- coexistence with an unstructured L1 micro-note;
- no SQL exposed to Qwen;
- no regression of the validated v9.3 memory path;
- measured structured-memory overhead far below local-model inference latency on the reference hosts.

## Structured memory design rationale

The strongest candidate for eliminating unnecessary LLM-based compaction for simple factual state is to make those memory updates structured.

Instead of only:

```text
CORR ORION: Ubuntu 24.04
```

a future side-channel could represent an operation closer to:

```text
entity = ORION
key    = os
op     = set
value  = Ubuntu 24.04
```

Then the merge can become deterministic:

```text
state["ORION"]["os"] = "Ubuntu 24.04"
```

Potential benefits:

- no compaction LLM call for simple state updates;
- exact correction semantics;
- easier deduplication;
- clearer provenance;
- easier testing.

Embeddings may still be useful for **retrieval, entity linking, or alias matching**, but they are not the preferred mechanism for exact state replacement.

## Why not use a vector database immediately?

LFO deliberately keeps the current exact-retrieval path simple.

A vector store can improve semantic recall, but it also adds:

- an embedding model or service;
- another index and lifecycle to manage;
- similarity thresholds and failure modes;
- greater resource use on small hosts.

For the current scale, lexical retrieval plus raw JSONL gives a useful baseline with no extra model inference.

A vector layer becomes attractive when real use shows that semantic recall failures materially outweigh the added complexity.

## Relationship to other memory systems

LFO is not the first system to explore persistent or same-call memory. The relevant difference is the specific combination of constraints: small local model, local-first routing, same-pass structured micro-memory, bounded rolling state, raw-history authority, and explicit performance validation on constrained hardware.

| System | Public memory pattern | LFO relationship |
| --- | --- | --- |
| **[Memori](https://memorilabs.ai/docs/memori-byodb/concepts/architecture/)** | SQL-native BYODB memory over SQLite/PostgreSQL/MySQL and other databases. It captures raw interactions, asynchronously extracts facts and semantic triples, builds a knowledge graph, generates local embeddings, and injects recalled memories on later calls. | This is the closest public analogue to LFO's SQL direction. Memori is a general memory middleware with semantic/vector recall and asynchronous augmentation; LFO is intentionally narrower for a small local model: same-pass bounded extraction, typed current-state operations, explicit supersession/provenance, and no embeddings by default. |
| **[LangGraph SQLite Store / Checkpointer](https://github.com/langchain-ai/langgraph/tree/main/libs/checkpoint-sqlite)** | SQLite can persist graph checkpoints and application-defined key/value JSON; the store can optionally add vector search. It is deliberately generic rather than prescribing semantic fact extraction. | LFO shares the embedded/local persistence philosophy but places a stronger domain contract above SQLite: entities, typed facts, relations, current validity, provenance and fail-closed turn transactions. |
| **[Open WebUI Memory](https://docs.openwebui.com/features/chat-conversations/memory/)** | Local per-user memory snippets are managed through add/update/replace/delete/search tools and can be injected into system context under explicit character budgets. Its documentation warns that very small local models may struggle with autonomous memory selection. | LFO avoids relying on autonomous memory tools for the 4B reference model. The wrapper owns persistence and bounded extraction, while the model emits a narrow schema-constrained side channel. |
| **[Letta](https://docs.letta.com/v1-sdk/memory/memory-blocks)** | Persistent memory blocks are pinned into the context window and can be edited or shared across agents; older messages remain retrievable outside the active context. | LFO's L1 is analogous to a much smaller working-memory block, while L0 raw history and the emerging L2 fact store are kept explicitly separate to conserve constrained context. |
| **Mem0** | Uses extracted memories plus retrieval and entity-oriented memory management. | LFO currently uses a smaller local pipeline and treats semantic retrieval as optional L3 rather than a prerequisite for exact current-state replacement. |
| **Sonzai** | Documents a dual-output pattern where the same LLM call emits a reply plus a hidden `[MEMORY: ...]` line; deeper extraction can run asynchronously. | LFO uses the same broad no-second-roundtrip idea, but moved the hidden channel to schema-constrained JSON after text-marker reliability proved insufficient on the tested small local model. |

These systems solve overlapping but not identical problems. LFO intentionally favors a minimal, inspectable architecture that can run locally and can be measured on weak hardware.

## Quality and reliability philosophy

The project currently uses a **90% engineering acceptance floor** for qualitative semantic memory behavior.

This is **not** an estimate that the implementation is only 90% reliable, nor a statement that it performs below 99%.

The heterogeneous smoke suite performed materially better than the acceptance floor, but it is too small and non-random to justify a statistically defensible 99%-class reliability claim.

The design therefore prefers:

- a robust enough semantic orientation layer;
- raw-history authority;
- retrieval backstops;
- correction handling;
- traceability;

over prompt-tuning a small model toward apparent perfection on a narrow fixed test set.

## Observability

Research traces should make memory behavior inspectable rather than implicit.

Useful fields include:

- emitted micro-note;
- parse status;
- whether the note was appended or skipped;
- skip reason;
- pending-buffer item count;
- pending-buffer character count;
- compaction trigger;
- memory before/after;
- retrieved historical snippets;
- answer and memory timings.

This supports both engineering regression work and later research replay.

## Scaling model

Single-pass memory should remain useful across hardware tiers because it removes an entire inference request rather than relying on a specific CPU/GPU characteristic.

Expected emphasis by tier:

- constrained CPU: largest absolute latency saving;
- small GPU: latency plus compute-efficiency benefit;
- larger GPU: throughput/concurrency benefit and room for stronger local models;
- multi-user service: reduced inference-request count compounds with traffic.

The main scaling limit is not VRAM but **side-task complexity**. If the same output is eventually asked to carry many independent classifiers, user-model updates, retrieval plans, confidence estimates, and tool plans, those tasks may begin to compete with the quality of the primary answer.

## Non-goals

The active conversational memory layer should not become:

- a hidden belief model of the user;
- an automatically learned political or ideological profile;
- a replacement for authoritative source data;
- a vector database by default;
- a place to store every assistant answer.

Bias-analysis and personalized epistemic interventions belong in explicit research traces or dedicated experimental layers, not silently inside conversational memory.

## References

Official/public documentation consulted for the design comparison:

- LangMem conceptual guide: https://langchain-ai.github.io/langmem/concepts/conceptual_guide/
- LangMem background memory: https://langchain-ai.github.io/langmem/background_quickstart/
- Mem0 2026 benchmark/pipeline overview: https://mem0.ai/library/agent-memory/ai-memory-benchmarks-in-2026
- Letta memory blocks: https://docs.letta.com/v1-sdk/memory/memory-blocks
- Letta archives: https://docs.letta.com/api/typescript/resources/archives
- Sonzai standalone real-time memory: https://sonz.ai/docs/en/connect-standalone-realtime
- Sonzai memory overview: https://sonz.ai/docs/en/memory
