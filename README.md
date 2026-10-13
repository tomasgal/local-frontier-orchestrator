# Local Frontier Orchestrator

**Local Frontier Orchestrator (LFO)** is a local-first conversational AI runtime that keeps a small local model in the interaction loop and selectively escalates requests to a stronger frontier model when fresh information, external verification or stronger reasoning is needed.

The current reference stack uses:

- **Qwen 3.5 4B via Ollama** for local conversation, routing, synthesis and memory extraction;
- **OpenAI Codex CLI** as the supported frontier runtime;
- **SQLite** for structured local memory;
- **SurrealDB** for the L4 epistemic observation/research layer.

The local model remains the user-facing conversational layer before and after a frontier call. Frontier results are returned to the local model and can remain available to subsequent LOCAL turns.

## Project status

**Current integrated baseline: v9.6 family — 2026-10-13**

| Layer / component | Status |
| --- | --- |
| **L0** raw interaction history and provenance | FIXED |
| **L1** conversational working memory | FIXED |
| **L2** typed factual state | CLOSED/FROZEN — [v9.4-l2-frozen](https://github.com/tomasgal/local-frontier-orchestrator/tree/v9.4-l2-frozen) |
| **L3** bounded retrieval/resolution | CLOSED/FROZEN — [v9.5-l3-frozen](https://github.com/tomasgal/local-frontier-orchestrator/tree/v9.5-l3-frozen) |
| **L4 R1/R2/A1/D1/A2/P1/P2** bounded research milestones | CLOSED/FROZEN for their stated scopes |
| **L4-I1** integrated end-to-end walkthrough | **ACCEPTED** |
| **Windows installer/bootstrap** | **DEVELOPMENT CANDIDATE — acceptance in progress** |
| Ordinary-chat L4 runtime hook | **PENDING** |
| Automatic L4 intervention | **OFF / not authorized by this build** |

L4-I1 demonstrated the bounded integrated path from L0 provenance through SurrealDB, analytics, policy and intervention to a real local-model call with reverse provenance. It is integration evidence, not a claim that the ordinary chat entry point already executes the complete L4 chain on every turn.

See [L4-I1 integration evidence](docs/L4_I1_INTEGRATION_EVIDENCE.md) and the [current roadmap](docs/ROADMAP.md).

## What LFO does

LFO separates routine local interaction from bounded frontier escalation:

```text
User
  |
  v
Qwen / Ollama
  |
  +-- LOCAL --------------------------> local answer
  |
  +-- FRONTIER
         |
         v
      ask_codex
         |
         v
   OpenAI Codex CLI
         |
         v
   frontier result
         |
         v
   Qwen synthesis / continuation
         |
         v
        User
```

Core runtime principles:

- **local-first conversation** — ordinary turns can stay on the local machine;
- **bounded escalation** — at most one frontier call per user turn in the current reference path;
- **controlled frontier interface** — Qwen does not receive a general shell;
- **conversation continuity** — knowledge returned by frontier can remain usable in later LOCAL turns;
- **persistent local state** — raw history, working memory, structured facts and bounded retrieval survive restarts;
- **explicit provenance** — L0-L4 research work preserves traceability back to source interaction evidence;
- **host-independent orchestration** — CPU/GPU placement and context sizing are runtime profiles rather than separate LFO builds.

## Requirements

Current Windows bootstrap target:

- Windows 10 or Windows 11, x64;
- Windows PowerShell 5.1 or newer;
- Internet access during bootstrap;
- an OpenAI/ChatGPT account usable with **Codex CLI** for the frontier path.

Git is reused when available. If Git is absent, the bootstrap can obtain the LFO source through a GitHub source archive.

The reference frontier path intentionally standardizes on **OpenAI Codex CLI**. OpenAI currently makes Codex available across ChatGPT plans including Free and Go, subject to plan-specific limits. LFO therefore does not implement its own OpenAI login, API-key management or frontier TUI.

A provider-flexible frontier adapter layer is planned for **v10.0**. No alternative client is committed as a supported backend until it has been implemented and validated against the LFO runtime contract.

## Install — Windows bootstrap candidate

> **Development status:** this installer is still undergoing clean-build acceptance. It is suitable for current testing, but it is not yet published as a stable LFO release.

The bootstrap installs into:

```text
%LOCALAPPDATA%\LFO
```

It does not create Desktop or Start Menu shortcuts. At completion it opens the installed `launch` directory.

### Quick start

Open **Windows PowerShell** and run:

```powershell
Invoke-WebRequest -UseBasicParsing "https://raw.githubusercontent.com/tomasgal/local-frontier-orchestrator/build/windows-bootstrap-v1/install/Install-LFO.ps1" -OutFile "$env:TEMP\Install-LFO.ps1"; powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$env:TEMP\Install-LFO.ps1"
```

The bootstrap performs the following high-level steps:

1. validates Windows, PowerShell and the system SQLite ABI;
2. detects **OpenAI Codex CLI**;
3. if Codex is missing, offers **Install OpenAI Codex CLI** or **Exit installation**;
4. obtains the selected LFO source;
5. reuses a compatible Ollama installation/model store when possible, otherwise provisions the pinned runtime;
6. prepares one shared Qwen base model with CPU and GPU runtime aliases;
7. reuses or provisions the pinned SurrealDB binary;
8. creates an isolated LFO SurrealDB datastore and credentials;
9. generates local configuration and installed launchers;
10. opens `%LOCALAPPDATA%\LFO\launch` in Windows Explorer.

The installer does not overwrite unrelated SurrealDB stores and does not stop service processes it does not own.

### Codex authentication

The current candidate detects the Codex executable and validates `codex --version`.

**The bootstrap login/readiness gate is the next implementation step.** If Codex has just been installed and has never been authenticated, run:

```powershell
codex
```

and complete the normal Codex sign-in before relying on LFO frontier escalation.

The LFO reference frontier call uses Codex as an isolated authenticated pipe and currently retains the existing `--ignore-user-config` contract.

### Start LFO

The bootstrap publishes both PowerShell and double-clickable BAT launchers:

```text
Start-LFO-CPU.bat
Start-LFO-GPU.bat
Start-LFO-CPU.ps1
Start-LFO-GPU.ps1
```

Use **CPU** on CPU-only or constrained hosts. Use **GPU** where Ollama can offload the reference model to a compatible GPU.

Both launchers start the **same LFO build**. They differ only in the local Ollama execution profile.

## What the Windows runtime starts

The installed runtime uses three visible surfaces:

1. the main LFO chat console;
2. Ollama foreground output when LFO starts the service, or a status monitor when it reuses an existing server;
3. SurrealDB foreground output when LFO starts the service, or a status monitor when it attaches to an existing LFO datastore.

Status monitors poll frequently enough to notice changes but suppress repetitive idle output. An unchanged state is shown only as an occasional heartbeat.

Default reference endpoints are selected locally and recorded in the installed state. The installer avoids attaching the LFO runtime to an unrelated database merely because a SurrealDB process already exists.

## Local model and memory

The current reference model is:

```text
qwen3.5:4b-q4_K_M
```

The bootstrap creates lightweight runtime aliases for:

- a GPU-oriented 8k-class context profile;
- a CPU-only 5k-class context profile.

The aliases share the same model weights.

The accepted local memory architecture is:

```text
L0  raw interaction history / provenance
L1  semantic conversational working memory
L2  typed factual state in SQLite
L3  bounded retrieval and resolution
L4  epistemic observation / analytics / policy research layer
```

L0 is the authoritative interaction evidence. Higher layers are bounded derived structures and do not replace the raw source history.

## L4 boundary

The Windows bootstrap provisions the isolated SurrealDB environment required by L4 and exposes its runtime configuration to LFO.

The current ordinary `QwenChat.ps1` entry point still requires the final runtime adapter that invokes the accepted L4 chain during normal chat turns. Therefore:

- a READY SurrealDB service does **not** by itself mean that ordinary turns are writing L4 observations;
- the accepted I1 walkthrough remains the end-to-end integration proof;
- automatic L4 intervention is not enabled by the current launcher.

See [Windows bootstrap build](docs/WINDOWS_BOOTSTRAP_BUILD.md), [L4 design](docs/L4_EPISTEMIC_OBSERVATORY_DESIGN.md), [P1 Policy Capsule](docs/L4_P1_POLICY_CAPSULE.md) and [P2 evaluation](docs/L4_P2_EVALUATION_RESULTS.md).

## Repository layout

```text
config/     runtime and host configuration
docs/       architecture, milestone contracts, evidence and roadmap
install/    Windows bootstrap
launch/     Windows runtime/service launchers
policy/     routing, synthesis and frontier policy
src/        QwenChat, memory, retrieval and L4 modules
tests/      deterministic and bounded acceptance suites
```

## Documentation

Recommended entry points:

- [Windows bootstrap build](docs/WINDOWS_BOOTSTRAP_BUILD.md)
- [Roadmap](docs/ROADMAP.md)
- [L2 frozen baseline](docs/L2_FROZEN_BASELINE.md)
- [L3 frozen baseline](docs/L3_FROZEN_BASELINE.md)
- [L4-I1 integration evidence](docs/L4_I1_INTEGRATION_EVIDENCE.md)
- [Human–AI Bias Balancer](docs/HUMAN_AI_BIAS_BALANCER.md)
- [Generic Epistemic Mediator](docs/GENERIC_EPISTEMIC_MEDIATOR.md)
- [DokuWiki search subsystem](docs/DOKUWIKI_SEARCH_SUBSYSTEM.md)

## Research and historical paths

LFO grew from experiments in both directions: a Qwen-first local orchestrator that calls Codex when needed, and an earlier Codex-first path that routed Codex through local models. The current reference architecture is **Qwen-first**; Codex Router is not required for this path.

Historical Codex Router work, earlier memory experiments, performance measurements and detailed milestone evidence remain in `docs/` and Git history rather than the landing-page README.

The DEV5 optimization work is summarized in [DEV5 implementation summary](docs/DEV5_IMPLEMENTATION_SUMMARY.md). The related technical note is published as *Reducing Context and Generation Traffic in a Local-First LLM Orchestrator: A Transferability Case Study* (DOI `10.5281/zenodo.23318551`).

## Development policy

Frozen milestone tags are immutable. A closed layer is reopened only for a demonstrated material defect or an explicitly versioned new scope.

Research evidence, deployment acceptance and cross-host replication are separate claims. Passing one does not silently imply the others.
