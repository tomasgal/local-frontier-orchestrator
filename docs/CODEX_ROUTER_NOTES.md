# Codex Router notes

## Why it matters to this project

Early experiments used [Codex Router](https://github.com/duolahypercho/codex-router) to place a local Ollama/Qwen model behind the Codex interface.

That work demonstrated an important complementary capability:

```text
Codex CLI -> Codex Router -> Ollama -> local Qwen
```

In other words, **Codex can serve as the user-facing agent interface while the underlying model is local Qwen**.

A related experimental fork is maintained at:

- <https://github.com/tomasgal/codex-router>

## What worked

The local-model transport path through Codex Router works. The approach is useful for experiments where a local model should participate in the Codex agent environment rather than act as the outer conversational orchestrator.

## Why the main project pivoted to Qwen-first

For small local models, the full Codex agent/tool/session surface can be expensive relative to the actual user task. This creates several practical issues:

- large prompt prefill;
- context pressure;
- slower local inference;
- tool-schema overhead;
- more demanding instruction-following requirements for the local model.

The current primary path therefore reverses the topology:

```text
Qwen local UI -> bounded ask_codex -> native Codex frontier
```

Codex Router is not required for this path.

## Why keep both?

They answer different research questions.

### Qwen-first

Best suited for:

- cheap local conversation;
- local privacy/policy layer;
- selective frontier escalation;
- bias-aware mediation before and after frontier calls;
- heterogeneous local hardware.

### Codex-first

Best suited for exploring:

- local models inside an established coding/agent interface;
- Codex tool use with alternative/local model backends;
- the limits of small models under a rich agent harness;
- compatibility and tool-surface reduction.

The Codex-first branch remains active research and will continue to be tuned independently.
