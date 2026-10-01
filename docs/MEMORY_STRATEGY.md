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
120 pending characters
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

## Future direction: keyed memory operations

The strongest candidate for eliminating LLM-based compaction is to make memory updates more structured.

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
| **LangMem / LangGraph** | Supports memory formation in the hot path or in background reflection. Its documentation explicitly notes the latency trade-off of hot-path formation. | LFO keeps immediate memory formation but avoids a second hot-path inference by piggybacking the micro-note on the answer/synthesis generation. |
| **Mem0** | Uses extracted memories plus retrieval; its 2026 memory pipeline describes single-pass ADD-only extraction, entity linking, and multi-signal retrieval. | LFO currently uses a much smaller local pipeline: single-pass answer-side extraction, tiny rolling state, and lexical exact-history retrieval. Entity/key structure is a plausible future convergence point. |
| **Letta** | Uses persistent memory blocks that remain in context, plus archival/vector-backed memory. | LFO uses a much smaller always-present rolling state because constrained local context is a primary design target; detailed history is retrieved only when needed. |
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
