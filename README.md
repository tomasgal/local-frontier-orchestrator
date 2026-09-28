# Local Frontier Orchestrator

**Status:** experimental / research prototype (`v0.1-alpha`)

Local Frontier Orchestrator is a local-first conversational orchestration layer for combining a small local language model with a stronger remote frontier model.

The project starts from a simple premise: a local model does not need to outperform a frontier model in general intelligence to be useful. It can remain the always-available conversational layer, handle inexpensive or privacy-sensitive work locally, preserve conversational continuity, and selectively escalate tasks that require fresh information, external verification, stronger reasoning, or broader tool access.

The current reference implementation uses **Qwen via Ollama** as the local conversational/orchestration model and the authenticated **OpenAI Codex CLI** as an on-demand frontier subagent. It does not require an OpenAI API key for the frontier path when Codex CLI is already authenticated.

This repository is intentionally experimental. Routing, synthesis policy, context handling, and future bias-balancing behaviour are being tuned through longer-term use rather than optimized around a small fixed benchmark.

As of **2026-09-28**, the first Windows/GPU reference deployment is frozen as a regression baseline, and a clean second Windows host has also passed the same Qwen-first contract on much more constrained CPU-only hardware. The second-host result is a proof-of-concept capacity and portability validation rather than a performance target. Clean-host validation also exposed a Windows npm-shim portability issue; QwenChat now prefers `codex.cmd` before falling back to other Codex command shims.

## Core architecture

```text
User
  |
  v
Local model / orchestrator
  |
  +-- LOCAL ---------------------------------> local answer
  |
  +-- FRONTIER
         |
         v
      ask_codex
         |
         v
   native codex exec
         |
         v
   frontier model / live web when needed
         |
         v
   local synthesis / critique
         |
         v
        User
```

The local model is therefore more than a router. It remains part of the conversation before and after frontier escalation.

### Current design principles

- **Local-first:** stable reasoning, writing, translation, summarization, and ordinary factual questions can remain local.
- **Capability gates before self-confidence:** explicit freshness, web, URL, and named-product specification rules can force frontier escalation even if the local model would otherwise try to answer.
- **Controlled frontier action:** the local model does not receive a general shell. It can request a bounded `ask_codex` action implemented by the wrapper.
- **Read-only frontier MVP:** `codex exec` is launched with read-only sandboxing and without interactive approval.
- **Bounded escalation:** the current design allows at most one frontier call per user turn.
- **Conversation continuity:** the frontier result returns to the local model, which produces the final user-facing response and keeps the interaction coherent.
- **Evidence anchoring without turning the local model into a pipe:** researched frontier facts are treated as the primary factual substrate, while the local model is still allowed to reorganize, explain, criticize, and add clearly distinguishable interpretation.
- **Host-specific runtime, common orchestration:** GPU/CPU placement, context length, thread count, quantization, and model selection belong to runtime/model profiles rather than the orchestration logic.
- **Policy/config separation:** routing/system policy, synthesis policy, frontier-subagent instructions, hard gates, and generation defaults are externalized from the transport/orchestration script so they can be reviewed and changed without editing process-control code.
- **Traceable experimentation:** longer-term failures and corrections are more informative than tuning the system around one or two prompts.

## Why not simply run the frontier model for everything?

The project explores a heterogeneous architecture in which different computational tiers have different roles.

Potential reasons to keep a local first-line model include:

- lower latency for simple tasks;
- lower frontier usage;
- offline or degraded-operation capability for selected tasks;
- local preprocessing and future retrieval over private sources;
- local policy enforcement and redaction before a cloud call;
- explicit control over routing and intervention policy;
- a stable place to implement metacognitive and Human–AI bias-balancing experiments;
- the ability to use different local hardware tiers without changing the user-facing interaction model.

## Hardware scope

The public architecture is deliberately hardware-agnostic. Personal hostnames, network details, local paths, and machine-specific sizing are not part of this repository.

The intended deployment range includes:

- current PCs with discrete GPUs;
- older PCs running smaller or CPU-oriented local models;
- mixed multi-PC environments with different host profiles;
- always-on edge nodes;
- single-board computers with attached AI accelerators;
- future local execution through accelerators such as **Hailo** or **Radxa/Rockchip-class AI modules**, where the runtime ecosystem makes this practical.

The local model is a replaceable executor. Qwen is the current reference implementation, not a permanent architectural requirement.

## Codex Router: historical and ongoing parallel path

This project was partly motivated by experiments with [Codex Router](https://github.com/duolahypercho/codex-router).

A separate experimental path successfully demonstrated the inverse topology:

```text
Codex CLI
   |
Codex Router
   |
local model via Ollama
```

That path is useful because **Codex can act as the user-facing agent interface for a local Qwen model**, including access to the Codex agent environment. It works, but still needs tuning: the Codex agent/tool surface can be disproportionately large for a small local model, and context/tool compatibility needs continued work.

A related experimental fork is maintained at [tomasgal/codex-router](https://github.com/tomasgal/codex-router). The Local Frontier Orchestrator does **not** require Codex Router for its primary Qwen-first frontier path. The two approaches are complementary research branches:

- **Qwen-first:** local conversational model calls Codex only when needed;
- **Codex-first:** Codex provides the interface and routes execution to a local model.

## Human–AI bias balancing research

A major research track for this architecture is **Human–AI bias balancing**.

The working hypothesis is that Human–LLM interaction can form a reciprocal feedback loop:

- human confirmation/myside bias, automation bias, confidence miscalibration, and framing affect how AI advice is requested and interpreted;
- LLM sycophancy, agreement bias, context sensitivity, and fluent overconfidence can reinforce the user's initial framing;
- personalization can improve assistance but can also become a higher-order **confirmation machine** if it learns what the user prefers rather than where the user's reasoning is poorly calibrated.

The local layer provides a natural experimental location for an auditable **Local Epistemic Balancer**. It can inspect the user request before frontier escalation and inspect the frontier result before presenting it to the user.

The goal is not to create an “unbiased AI.” The goal is to study whether a local mediator can improve **appropriate reliance**: accepting useful AI guidance while resisting misleading guidance, without merely suppressing disagreement or maximizing user satisfaction.

See [`docs/HUMAN_AI_BIAS_BALANCER.md`](docs/HUMAN_AI_BIAS_BALANCER.md).

## Repository layout

```text
.
├── README.md
├── .gitignore
├── config/
│   ├── host.example.psd1
│   └── QwenChat.config.psd1
├── docs/
│   ├── ARCHITECTURE.md
│   ├── CODEX_ROUTER_NOTES.md
│   ├── HUMAN_AI_BIAS_BALANCER.md
│   ├── NOTEBOOK_SETUP.md
│   └── ROADMAP.md
├── policy/
│   ├── orchestrator-system.txt
│   ├── synthesis-system.txt
│   └── frontier-subagent.txt
├── launch/
│   ├── QwenChat.bat
│   ├── Start-Ollama.bat
│   └── Start-Ollama.ps1
└── src/
    └── QwenChat.ps1
```

## Requirements

The current Windows reference implementation assumes:

- Windows PowerShell 5.1 or compatible PowerShell;
- Ollama available locally;
- a local chat model installed in Ollama;
- OpenAI Codex CLI installed and authenticated if frontier escalation is required.

The scripts avoid hard-coded personal paths. Runtime paths can be supplied through command-line parameters or environment variables.

## Quick start

Start Ollama:

```powershell
.\launch\Start-Ollama.ps1
```

or:

```text
launch\Start-Ollama.bat
```

Then start the chat client:

```powershell
.\src\QwenChat.ps1 -Model "your-local-model:tag"
```

or use the BAT wrapper:

```text
launch\QwenChat.bat -Model "your-local-model:tag"
```

The local model profile should carry hardware/runtime placement settings appropriate for that machine. The chat client intentionally avoids overriding GPU/CPU placement, context length, or thread count per request.

For a clean Windows host bootstrap, see [`docs/NOTEBOOK_SETUP.md`](docs/NOTEBOOK_SETUP.md). Do not copy a tuned context/GPU profile from another machine before measuring the new host.

## Security and privacy notes

The current frontier wrapper is intentionally constrained:

- frontier execution is read-only;
- the delegated prompt is sent through stdin, not interpolated into a shell command;
- common API-key environment variables are removed before launching Codex so the authenticated Codex session is used instead;
- the local model is not given arbitrary shell execution;
- personal deployment paths, hostnames, network topology, credentials, and private data are excluded from this public repository.

This is still experimental software. Review the scripts before running them in your environment.

## Project status

The transport path is working:

```text
local model -> ask_codex -> native Codex frontier -> local model
```

Current work focuses on:

- long-term routing quality;
- faithful-but-useful frontier synthesis;
- context continuity;
- structured trace logging;
- additional host validation and context sizing;
- multi-host profiles;
- bias-aware mediation;
- future edge/SBC execution.

## License

No open-source license has been selected yet. Until a license is added, normal copyright rules apply.
