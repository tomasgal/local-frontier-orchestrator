# Persistent conversation memory and research logging

## Goals

The terminal client is treated as one continuing conversation rather than a set of disposable process sessions.

- `/exit` stops the process and preserves memory.
- restarting QwenChat resumes bounded recent context plus persistent working memory.
- `/clear` resets active memory/context but never deletes historical logs.
- Qwen itself has no filesystem or shell tool.

## Storage

Default root:

```text
%LOCALAPPDATA%\\LocalFrontierOrchestrator
```

Layout:

```text
state/
  working_memory.json
  pending_notes.jsonl
  runtime_state.json
logs/
  conversation-YYYY-MM.jsonl
  trace-YYYY-MM.jsonl
```

The monthly split keeps append-only logs manageable and makes later compression/archival straightforward.

## Per-turn memory note

After every completed user/assistant turn, a small local Qwen call produces structured JSON containing:

- shortened user intent;
- topic labels;
- durable facts/context with explicit epistemic status;
- decisions;
- open loops;
- tentative bias-research signals.

This is the maximum-quality mode. It intentionally adds latency on slow CPU-only hosts.

## Compaction

After six successful memory notes by default, Qwen receives the existing working memory plus the pending notes and produces a new compacted `working_memory.json`.

Compaction tracks frequency, but frequency means conversational salience only. It must never upgrade a repeated claim into a verified fact.

Per-turn bias signals remain in the trace log and are not copied into working memory.

## Context injection

Bounded memory and recent raw dialogue are inserted into all three conversational paths:

```text
LOCAL Qwen
FRONTIER Codex delegation
post-frontier Qwen synthesis
```

Host launchers can override only capacity parameters such as recent-turn count and character budgets. They do not change memory semantics.

## Research trace

The trace is intended to support later Local Epistemic Balancer experiments and offline replay. It records routing, raw intermediate/final text when enabled, timing/token metadata, policy fingerprints, memory deltas, and tentative bias signals.

Because the log may contain complete conversation text and frontier results, it should be treated as private local research data.
