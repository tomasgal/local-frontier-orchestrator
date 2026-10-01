# Persistent conversation memory and research logging

For design rationale, trade-offs, comparison with other memory approaches, and future direction, see [MEMORY_STRATEGY.md](MEMORY_STRATEGY.md).

## Goals

QwenChat v9.2 treats the terminal as one continuing conversation rather than a set of disposable process sessions.

- `/exit` stops the process and preserves memory.
- restarting QwenChat restores bounded recent raw turns plus persistent memory.
- `/clear` resets active memory/context but never deletes historical logs.
- Qwen itself receives no filesystem or shell tool.

## Storage

Default root:

```text
%LOCALAPPDATA%\LocalFrontierOrchestrator
```

Layout:

```text
state/
  working_memory.txt
  pending_notes.jsonl
  runtime_state.json
logs/
  conversation-YYYY-MM.jsonl
  trace-YYYY-MM.jsonl
```

Legacy v9 JSON working-memory files are left untouched. On first v9.1 start, the runtime state migrates to memory schema 2, clears obsolete pending-note state, and rebuilds active continuity from the raw conversation logs.

## Three context layers

The memory design deliberately separates orientation from exact data.

1. **Recent raw turns** — the newest conversation turns are passed verbatim within a host-specific character budget.
2. **Micro-memory** — every completed turn produces a single 0–40 character orientation note. Every five completed memory steps, the current state plus pending notes are compacted into a 0–160 character rolling state.
3. **Exact historical data** — full conversation JSONL is never replaced by summaries. A lightweight deterministic lexical retriever can inject a bounded number of relevant older raw snippets.

The rolling state answers "what are we doing?" while the raw store answers "what exactly was said?".

## Per-turn micro-memory

v9.2 removes the separate post-turn local-model inference used by v9.1.3. The bounded micro-note is now emitted inside the **existing answer pass**:

- LOCAL turns return a schema-constrained object containing `route`, the user-facing `answer`, and `memory_note`;
- FRONTIER turns leave the routing-pass note empty, and the post-frontier synthesis pass returns the final `answer` plus `memory_note`;
- the wrapper strips the structured envelope, displays only `answer`, and persists the cleaned 0–40 character note.

The semantic contract remains user-delta-first: the note should primarily represent new durable user state rather than summarize the answer or copy older memory. Explicit replacements/corrections carry a `CORR ` marker plus enough target identity to let compaction supersede the obsolete value.

The output schema guarantees structure, not perfect semantic extraction. The note is still produced by a small stochastic model, so occasional misses or over-tagging are expected. Raw conversation JSONL remains authoritative, and exact historical retrieval remains the correctness backstop.

## Compaction

Default compaction cadence is five completed memory steps.

Input:

```text
STATE: <=160 chars
NOTES: up to five x <=40 chars
```

Output:

```text
STATE: <=160 chars
```

Compaction is intentionally lossy. It preserves active entities, goals, decisions, constraints, preferences, and corrections, but it is not the authoritative data store. v9.1.3 also normalizes the result to state-only form: input labels are dropped and corrected values are stored once.

Repeated mentions may increase salience, never factual certainty. Later explicit corrections should supersede obsolete values in the rolling state while the raw history remains intact.

## Exact-data retrieval

Before LOCAL answering, frontier delegation, or post-frontier synthesis, the wrapper can search older conversation JSONL using a small lexical scorer.

The retrieval query combines:

- the current user request;
- current rolling state;
- pending micro-notes.

Recent raw turns are excluded from retrieval to avoid duplication. Older hits are ranked by lexical overlap and recency, then bounded by host-specific item and character limits.

This is deliberately simple: no vector database, embedding model, agent tool, or extra model inference is required.

## Context injection

The three conversational paths receive the same bounded continuity substrate:

```text
rolling state
+ pending micro-notes
+ relevant older raw snippets
+ recent raw turns
+ current request
```

Host launchers control capacity only. The semantic rules remain shared.

## Validated v9.1.3 baseline — 2026-09-30

On the constrained CPU-only Windows notebook, the final v9.1.3 validation used a clean memory epoch and a five-turn correction scenario.

Observed results:

- user-delta micro-notes preserved new facts, goals, constraints, and a later correction;
- normalized compaction produced a clean rolling state without leaking internal `STATE`/`NOTES`/`CORR` labels;
- post-turn micro-memory extraction was about **18–21 seconds** on this host;
- the fifth-turn extraction plus compaction was about **40 seconds**;
- after process exit and restart, the conversation continuity pipeline restored the corrected value and active goal/constraint correctly.

The earlier verbose v9.1.1 policy roughly doubled post-turn memory latency on this CPU. v9.1.2 restored the same user-delta semantics with a much shorter policy prompt, and v9.1.3 added compaction-output normalization without reintroducing the latency regression.

An isolated exact-data retrieval regression was then run with the target fact outside the recent raw-turn window and removed from active rolling state. The trace showed empty active `STATE`/`PENDING` fields, the correct older raw turn under `RELEVANT OLD DATA`, and a correct final recall. This validates the complete three-layer memory path:

```text
recent raw turns
+ compact working memory
+ selective exact historical retrieval
```

The test also exposed one presentation issue rather than a retrieval failure: internal historical turn markers (for example `T34`) can be echoed in user-facing prose. v9.2 should suppress those internal identifiers.

## Validated v9.2 single-pass memory — 2026-10-01

The v9.2 branch was validated on the same constrained CPU-only Windows notebook with `qwen3.5:4b-q4_K_M` at a 5120 context hint.

Observed results:

- the separate v9.1.3 per-turn memory inference was removed;
- ordinary post-answer memory persistence commonly measured about **0.01–0.05 seconds** instead of roughly **18–21 seconds** for the former extractor, with occasional local I/O outliers around 1–2 seconds;
- every fifth completed turn still performs a separate compaction inference, observed around **19 seconds** in the v9.2 tests;
- LOCAL structured output produced clean user-facing answers while keeping the note hidden from the terminal;
- FRONTIER synthesis also produced an authoritative single-pass note without adding a second memory inference;
- explicit correction notes now preserve an unambiguous `CORR <target>: <new value>`-style signal for compaction;
- restart continuity passed: a fact persisted before `/exit` was recalled correctly after a new QwenChat process loaded the same state;
- internal pending-note turn IDs are retained in JSONL for auditability but are no longer fed to the semantic compactor, preventing artifacts such as `T2` from leaking into rolling state.

This is a pragmatic conversational memory design, not a zero-error semantic extractor. The **90% figure is an engineering acceptance floor, not an estimate of the implementation's observed reliability**. The heterogeneous smoke suite performed materially better than that floor, while still exposing occasional semantic misses such as an omitted durable note or an unnecessary correction tag. The suite is intentionally too small and non-random to justify a statistical claim such as 99% reliability. The design therefore avoids prompt-tuning toward benchmark perfection while retaining authoritative raw history and exact retrieval as backstops for lossy micro-memory.


## Research trace

Monthly JSONL traces remain append-only and can record:

- raw user request;
- raw local result;
- raw frontier result;
- final answer;
- route and route reason;
- token/timing metadata;
- retrieved older-data snippets;
- memory before and after;
- cleaned micro-note and raw memory-model output;
- policy fingerprint.

These traces are intended for later offline replay and Local Epistemic Balancer research. Bias labels are not fed back into active memory by default, avoiding a self-reinforcing user model.

Because the logs may contain full conversation text and frontier results, they should be treated as private local research data.
