# Codex Router — alternative Codex-first research path

## Status

Codex Router is **not a dependency of the current LFO runtime**. The supported
v9.6.1 architecture is Qwen-first:

```text
Qwen local UI -> bounded ask_codex -> native Codex CLI
```

This document is retained because the complementary Codex-first topology remains
a useful research branch:

```text
Codex CLI -> Codex Router -> Ollama -> local Qwen
```

The two paths answer different questions and should not be conflated.

## What the Codex-first path demonstrated

A local Ollama/Qwen model can participate behind the Codex interface. This is
useful for experiments on:

- local models inside an established coding/agent interface;
- Codex tool-surface compatibility with alternative model backends;
- prompt/tool-schema overhead on small models;
- context and timeout requirements for slow local inference.

For small local models, however, the Codex agent/tool/session context can be
large relative to the user task. The primary LFO runtime therefore keeps Qwen
as the outer conversational orchestrator and escalates selectively to native
Codex.

## Upstream contribution

The local-context/timeout work was contributed upstream as:

- **duolahypercho/codex-router PR #925 — _Allow local Ollama context and timeout overrides_**

The PR was **merged on 2026-10-05** (merge commit
`85259b6725ced1c1f0f56325b0c97a7b6660a726`). It added bounded local Ollama
context/timeout overrides and preserved the no-retry local transport behavior.
The PR included a Windows end-to-end Codex -> Router -> LiteLLM -> Ollama -> Qwen
smoke test that completed successfully under a very long local request.

The experimental fork remains:

- <https://github.com/tomasgal/codex-router>

## Project boundary

Normal users installing LFO from the README should **not install Codex Router**
for the Qwen-first path. Native Codex CLI is the supported reference FRONTIER
adapter.

Revisit Codex Router only when explicitly working on the Codex-first research
branch or on the planned provider/client abstraction work.
