# Persistent conversation memory and research logging

## Goals

QwenChat v9.1.3 treats the terminal as one continuing conversation rather than a set of disposable process sessions.

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

The post-turn memory call receives only bounded portions of:

- the **new user turn as primary evidence**;
- a shorter assistant outcome as secondary evidence;
- the route marker.

It does not receive the whole previous memory or frontier payload. The extractor records the **new conversational delta**, not a summary of the full turn. In v9.1.2 the same user-delta-first semantics are expressed with a shorter policy prompt to reduce repeated prompt-evaluation cost on slow CPU hosts. Output is plain text rather than JSON and is hard-capped to 40 characters by the wrapper.

This keeps maximum-quality per-turn semantic extraction while greatly reducing prompt and generation cost on slow CPU-only hosts.

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

The next performance target is **single-pass micro-memory**. The current v9.1.3 baseline deliberately uses a second local-model inference after each answer to extract the micro-note; on constrained CPU-only hardware that extra call is operationally significant. v9.2 should attempt to emit a bounded hidden/structured note from the existing LOCAL answer or post-frontier synthesis pass, with the wrapper stripping it from the user-visible answer and persisting it without changing the three-layer memory semantics.

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
