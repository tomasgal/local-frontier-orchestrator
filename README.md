# Local Frontier Orchestrator

**Current operational version: v9.6.3 (2026-10-20, `main`).** v9.6.3 promotes the controlled Windows runtime and unattended experiment runner, keeps the accepted L0-L4 semantics, and adopts **High Windows process priority as the default inference profile** based on the bounded counterbalanced host experiment documented below.

Release notes: [docs/RELEASE_V9.6.3.md](docs/RELEASE_V9.6.3.md).

**Immutable release:** [`v9.6.3`](https://github.com/tomasgal/local-frontier-orchestrator/tree/v9.6.3), published 2026-10-20 as an annotated Git tag. Tag object `bfd0e6b482a1c4819fca39c68f3a32bf62921709` resolves to release-closure commit `4f89badcd1a3f91ecdf32666566e9d81efff0cda`. The tag is the immutable v9.6.3 boundary; subsequent documentation or development on `main` does not alter that release.

**Previous immutable release:** [v9.6.2](https://github.com/tomasgal/local-frontier-orchestrator/tree/v9.6.2) (2026-10-14). Zenodo software archive DOI [10.5281/zenodo.23373391](https://doi.org/10.5281/zenodo.23373391).

## v9.6.3: controlled runtime and unattended experiments

v9.6.3 provides one primary Windows entrypoint for ordinary interactive use and reproducible experiments:

~~~powershell
.\LFO.ps1
.\LFO.ps1 -Device CPU
.\LFO.ps1 -Device GPU
.\LFO.ps1 -Priority Normal
.\LFO.ps1 -Experiment .\experiments\runtime-priority-counterbalanced.json
~~~

Ordinary production launch defaults to **High** process priority for the inference runtime. `Normal` remains available as an explicit override/control; `Realtime` is not a production default. SurrealDB/L4 remains at Normal priority. The production launcher verifies/sets the configured Ollama process tree rather than assuming that priority on a wrapper process is sufficient.

Long silent waits use compact liveness output: one status line is opened and a dot is appended every five seconds until the next event. The unattended Qwen watchdog uses the same behavior, preserving console history while still making a live process visibly active.

The experiment runner supports isolated prompt state, LOCAL-only guards, owned service envelopes, warm-up, repeated/counterbalanced conditions, checkpoint/resume, JSONL/JSON/CSV results, process-priority verification and Ollama placement capture. Shared experiment definitions are in [`experiments/`](experiments/).

The runtime-priority work was motivated in part by **Daniel Correa Villa's architecture-first optimisation work** on a four-node Raspberry Pi 5 inference cluster. LFO transfers the general host-runtime question, not the Raspberry Pi measurements themselves. The accepted Windows experiment found a strong and counterbalanced High-priority prefill effect on the constrained CPU-only validation notebook; decode moved in the same direction but more noisily. See [the full v9.6.3 runtime-priority report](docs/RUNTIME_PRIORITY_EXPERIMENT_V963.md).

Related sources:

- Correa Villa's distributed-llama project / reproducibility implementation: [`danielcorrea-hellomatik/distributed-llama`, `pi5-cluster`](https://github.com/danielcorrea-hellomatik/distributed-llama/tree/pi5-cluster)
- Daniel Correa Villa, *Pushing Four Raspberry Pis to the Memory Wall: Bit-Exact 30B Mixture-of-Experts Inference, +16% over the Public Record*: DOI [10.5281/zenodo.20357376](https://doi.org/10.5281/zenodo.20357376)
- Hellomatik project summary: [World-record LLM speed on Raspberry Pi 5](https://hellomatik.com/en/blog-articles/30b-llm-raspberry-pi-record-3)

## Windows bootstrap for v9.6.3

The v9.6.3 bootstrap retains the accepted v9.6.2 installer, shared Ollama model-store and L4 provisioning semantics, updates the runtime contract to v9.6.3, records `DefaultPriority = High`, publishes the new `LFO.ps1` entrypoint into the installed `launch` directory, and keeps the CPU/GPU launchers as compatibility wrappers. **LFO-owned Ollama and SurrealDB services are started headless with stdout/stderr redirected under `runtime\logs\services`; they no longer depend on an interactive Windows console and therefore cannot be paused by console selection/QuickEdit state.**

**Release-closure smoke: PASS on 2026-10-20.** Installed source `e625e2f44187c23f9379fd9ef3e3c8cb74109972` was exercised on the Windows 10 CPU-only validation notebook after the headless-service fix. The bootstrap successfully reused live Ollama 0.34.4 and SurrealDB 3.3.0, republished the v9.6.3 launch tree, and the installed `LFO.ps1 -Device CPU` verified Ollama at **High** priority, reported L4 `CONFIGURED`, entered interactive QwenChat, and returned cleanly from `/exit` with no false failure. This final smoke intentionally used `-SkipModelPull -SkipL4Acceptance` because model aliases and the inherited deterministic 33-check L4 suite had already passed earlier in the same v9.6.3 validation cycle.

The installer:

- reuses a compatible existing Ollama runtime/model store where possible, but persists one **shared LFO model store** for both CPU/GPU aliases and refuses to reuse a listener that points at a conflicting store;
- discovers and reuses a compatible **SurrealDB 3.3.0** binary from explicit override, prior install state, PATH, bounded `%LOCALAPPDATA%\` discovery, or a running process; it never hardcodes a host-specific path;
- always creates/reuses an **LFO-owned isolated datastore and current-user DPAPI credentials**, independent of where the SurrealDB executable was found;
- writes the L4 endpoint and runtime credential into the installed local config and also exports them to the launcher environment;
- preserves v9.6.1 L0 provenance and conservative L4 recording semantics;
- runs the inherited deterministic L4 recording suite by default (**33 checks, zero model/FRONTIER calls**);
- exposes CPU/GPU launchers for the same installed source tree;
- opens the installed `launch` directory in Windows Explorer so shortcuts can be created easily;
- after a successful bootstrap, automatically starts LFO/Qwen with the selected CPU or GPU profile.

From Windows PowerShell 5.1, choose the bootstrap command for the profile you want to use by default.

**CPU bootstrap** — selects the CPU model profile (`num_gpu 0`, 5120-token context) and automatically starts Qwen with that profile after a successful install:

~~~powershell
Invoke-WebRequest -UseBasicParsing "https://raw.githubusercontent.com/tomasgal/local-frontier-orchestrator/main/install/Install-LFO.ps1" -OutFile "$env:TEMP\Install-LFO.ps1"; powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$env:TEMP\Install-LFO.ps1" -Profile CPU
~~~

**GPU bootstrap** — selects the GPU model profile (`num_gpu 99`, 8192-token context; Ollama performs the actual supported GPU offload) and automatically starts Qwen with that profile after a successful install:

~~~powershell
Invoke-WebRequest -UseBasicParsing "https://raw.githubusercontent.com/tomasgal/local-frontier-orchestrator/main/install/Install-LFO.ps1" -OutFile "$env:TEMP\Install-LFO.ps1"; powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$env:TEMP\Install-LFO.ps1" -Profile GPU
~~~

Both bootstrap paths install/reuse the same LFO runtime and prepare **both** CPU and GPU model aliases and launchers in one shared Ollama model store. v9.6.3 also installs the primary `LFO.ps1` entrypoint and uses **High** inference priority by default; `-Priority Normal` remains an explicit override. CPU/GPU selection changes execution parameters only; it does not split model storage, LFO memory, logs, or L2–L4 state. `-Profile` selects the default profile recorded for the installation and the profile that is launched automatically at the end. Windows Explorer still opens the installed `launch` directory so the user can create shortcuts wherever desired; `Start-LFO-CPU.ps1` and `Start-LFO-GPU.ps1` remain explicit overrides. The default install root is `%LOCALAPPDATA%\LFO`. Use `-InstallRoot` only when you intentionally need a separate installation, such as an isolated acceptance tree. `-SkipLaunch` suppresses only the final automatic Qwen launch; `-SkipL4Acceptance` is for explicit troubleshooting only and is not part of the normal install path.

## macOS users: AI-assisted porting guidance

**macOS is not yet a supported v9.6.3 runtime target.** PowerShell itself is available natively on macOS as **PowerShell 7 (`pwsh`)**, so the LFO PowerShell code can be ported, but the current Windows bootstrap and production launcher contain Windows-specific process, path, service and priority handling and should not be expected to run unchanged.

For a Mac user, the recommended workflow is to give this repository/README and the relevant launcher to a capable coding assistant and ask it to create a **macOS runtime adapter**, while preserving the LFO orchestration and experiment semantics. The port should keep the existing model/routing/memory behavior and declarative experiment format wherever possible, and replace only the operating-system-specific runtime layer.

A coding assistant performing the port should follow these rules:

- install/use native macOS **PowerShell 7 (`pwsh`)**, Ollama, SurrealDB and Codex CLI rather than attempting to emulate the Windows environment;
- preserve the existing LFO `QwenChat`, L0-L4, routing, memory, trace and experiment semantics unless a platform incompatibility specifically requires a documented change;
- preserve the JSON experiment definitions and result fields so that Windows and macOS runs remain comparable;
- replace Windows-only path discovery such as `%LOCALAPPDATA%`, Windows bootstrap state assumptions and backslash-specific paths with macOS-safe paths and explicit install-state discovery;
- replace Windows-only process APIs such as `Get-CimInstance Win32_Process`, `taskkill.exe`, Windows `ProcessPriorityClass` handling and `Start-Process -WindowStyle Hidden` with appropriate macOS process-tree, termination and priority mechanisms;
- do **not** assume that Windows `Normal`/`High`/`Realtime` priority classes have direct semantic equivalents on macOS. If priority experiments are ported, map them explicitly to the chosen macOS mechanism (for example nice/renice or another documented mechanism), record the actual applied value, and treat cross-OS comparisons as separate experimental conditions;
- on Apple Silicon, let the native Ollama/Metal runtime determine supported acceleration and verify actual model placement/runtime behavior rather than copying Windows/NVIDIA GPU-detection logic;
- keep experiment memory and L4 datastores isolated from the user's normal LFO state;
- retain LOCAL-only benchmark guards when running controlled performance experiments so a routing decision cannot silently introduce a FRONTIER/Codex call into a local inference benchmark;
- run a macOS smoke test after conversion: one LOCAL interactive turn, one FRONTIER turn if Codex is configured, persistence across restart, and one short unattended experiment. A syntactically successful conversion is not evidence of runtime parity.

For an AI coding assistant, the intended architectural boundary is therefore:

```text
portable LFO logic
    QwenChat / routing / memory / L0-L4 / experiment schema
                         |
                         v
platform runtime adapter
    Windows: current bootstrap/launcher/process control
    macOS:   pwsh + native process/path/priority/service control
```

A macOS port should be treated as a **new host/runtime validation target**, not as evidence that the existing Windows acceptance results automatically transfer to Apple hardware or macOS.

## v9.6.1: L4 recording and manual analysis

- **Automatic recording:** deterministic T1 emits `FRAMING`, `ASYMMETRIC_EVIDENCE_REQUEST`, or ABSTAIN for short, explicit Slovak/English user instructions. Each observation links to its exact L0 turn/stage and content hash. Assistant text is outside this classifier's scope; observations are reported signals, not proven bias or user traits.
- **Manual analysis:** `/analyze` summarizes the last 8 turn IDs in the current epoch; `/analyze 20` changes the window (1–100). The existing A1/A2 chain reports counts, recurrence and up to 12 source references without a model call. No automatic T2 trigger is used.
- **Response behavior:** P1/P2 response intervention is disconnected and P2 stays OFF. D1 remains offline. L4 works with LOCAL conversations and has no FRONTIER dependency. L4 errors leave ordinary chat operational.
- **Bounded reads:** no ordinary-turn L4 analytics reads. Explicit analysis uses the frozen A1/A2 capped-epoch readers (200 records, pages of 50), then selects the turn window. Exceeding the cap reports an unavailable analysis instead of a partial result.

### Enable recording

Outside the Windows bootstrap path, use an existing initialized R1 SurrealDB 3.3.0 service and its current-user runtime credential. Set `L4.Endpoint` and `L4.CredentialPath` in the chat config, or supply `LFO_L4_ENDPOINT` and `LFO_L4_RUNTIME_CREDENTIAL`. `LFO_L4_ENABLED=1` enables recording; `0` disables it. The Windows bootstrap provisions/reuses the LFO datastore, credentials and headless service; custom/manual deployments remain responsible for those components. Missing configuration leaves L4 unavailable and chat functional.

Startup `CONFIGURED` confirms settings were loaded. Per-turn `CREATED` confirms an R1 write; `UNKNOWN` means the write could not be confirmed. ABSTAIN performs no R1 I/O. `/clear` starts a new conversation epoch and retains historical observations.

See [configuration, limits and live test steps](docs/L4_RECORDING_MANUAL_ANALYSIS.md) and [I1 extraction evidence](docs/L4_V961_GATE1.md).

### Validation and release scope

- Windows PowerShell 5.1 / SurrealDB 3.3.0 recording and command-loop suite: **33/33 PASS**, including real isolated R1 writes, source drill-back, idempotent replay, manual read-only analysis and failure isolation.
- Preserved I1 regression: **128/128 PASS**, including **108/108 pre-inference checks**; adapter checks **8/8 PASS**. Gate 1 also compared **45 output artifact pairs** against the recovered original I1 harness.
- Automated validation used **zero model inference calls** and **zero FRONTIER calls**.
- Live Windows chat/manual-analysis operation: **maintainer-reported success on 2026-10-14**.
- Installed-tree **FRONTIER/Codex end-to-end smoke: PASS on 2026-10-14** against source commit `dbd14629d2318bc5f340271b225518c39d217f16`. A hard web/freshness request routed to FRONTIER, completed one authenticated `ask_codex` call, returned evidence to Qwen, completed post-FRONTIER local synthesis, and finished with `route=FRONTIER`.
- Installed-tree **CPU execution-profile acceptance: PASS on 2026-10-14** on the same Windows installation using `lfo-qwen3.5-4b-cpu5k:latest` (`num_gpu=0`, 5120-token context). A LOCAL arithmetic turn completed successfully with `route=LOCAL`. This verifies the CPU profile itself; it is not a separate-host compatibility claim.
- The shared Ollama model-store repair was exercised by a clean runtime restart: both CPU/GPU aliases resolved from one persisted store and the post-FRONTIER synthesis no longer failed after Codex returned.

These live checks add no cross-host replication or general detector-accuracy claim.

v9.6.2 packages the already accepted recording/manual-analysis scope together with the accepted Windows bootstrap and model-store lifecycle fixes. Automatic rare triggers and response interventions are not release requirements. The immutable `v9.6.1` tag remains the earlier L4 operational evidence boundary; `v9.6.2` is the packaging/runtime release boundary.

## Accepted research baselines

| Layer | Accepted role and status |
| --- | --- |
| **L0** | Authoritative conversation JSONL and USER/LOCAL/FRONTIER/FINAL provenance. v9.6.1 adds an isolated post-L0 callback and enables source-stage capture in the shipped config. |
| **L1** | Single-pass semantic micro-memory and pressure-triggered compaction; accepted behavior retained. |
| **L2** | Typed current/historical factual state and selective read/write safeguards; immutable [`v9.4-l2-frozen`](https://github.com/tomasgal/local-frontier-orchestrator/tree/v9.4-l2-frozen). |
| **L3** | Reconstructible faceted retrieval/index and bounded context with baseline fallback; immutable [`v9.5-l3-frozen`](https://github.com/tomasgal/local-frontier-orchestrator/tree/v9.5-l3-frozen). |
| **L4 research** | R1/R2/A1/A2/D1/P1/P2 retain their frozen research scopes. [Accepted I1](docs/L4_I1_INTEGRATION_EVIDENCE.md) demonstrated the prepared-observation chain through a real local model. v9.6.1 reuses its integration logic for ordinary recording and manual analytics. |

Frozen milestone tags, policy rules, intervention text and historical evidence remain unchanged. P2's frozen decision is `PROMISING_BOUNDED_EFFECT`; its [integrity compatibility contract](docs/L4_P2_INTEGRITY_COMPATIBILITY.md) remains in place. Frozen research evidence and the v9.6.1 operational release have distinct scopes.

**Start here:** [L0 source contract](docs/L0_STAGE_SOURCE_CAPTURE.md) | [L2 baseline](docs/L2_FROZEN_BASELINE.md) | [L3 baseline](docs/L3_FROZEN_BASELINE.md) | [L4 runtime guide](docs/L4_RECORDING_MANUAL_ANALYSIS.md) | [P2 research baseline](docs/L4_P2_FROZEN_BASELINE.md).

DEV5's architecture-first optimization direction was materially informed by Daniel Correa Villa's *Pushing Four Raspberry Pis to the Memory Wall* (DOI `10.5281/zenodo.20357376`). LFO transfers the general principle of eliminating unnecessary work and context/data movement before hardware-specific tuning; it does not claim a reproduction of the paper or transfer of its Raspberry Pi measurements. The exact accepted mapping is documented in [docs/DEV5_IMPLEMENTATION_SUMMARY.md](docs/DEV5_IMPLEMENTATION_SUMMARY.md).

**DEV5 technical note:** the bounded transferability results are now published as *Reducing Context and Generation Traffic in a Local-First LLM Orchestrator: A Transferability Case Study* on Zenodo, DOI [10.5281/zenodo.23318551](https://doi.org/10.5281/zenodo.23318551). The note reports the accepted A+B mechanism and R5 observations with the same evidence boundaries as the frozen baseline; it is not presented as a replication of the motivating Raspberry Pi study or as a universal speedup claim.

Local Frontier Orchestrator is a local-first conversational orchestration layer for combining a small local language model with a stronger remote frontier model.

The project starts from a simple premise: a local model does not need to outperform a frontier model in general intelligence to be useful. It can remain the always-available conversational layer, handle inexpensive or privacy-sensitive work locally, preserve conversational continuity, and selectively escalate tasks that require fresh information, external verification, stronger reasoning, or broader tool access.

The current reference implementation uses **Qwen via Ollama** as the local conversational/orchestration model and the authenticated **OpenAI Codex CLI** as an on-demand frontier subagent. It does not require an OpenAI API key for the frontier path when Codex CLI is already authenticated.

For v9.2 memory validation, the project uses a **conservative 90% engineering acceptance floor** for qualitative semantic behavior. This is not a claim that measured reliability is 90% or below 99%: the development smoke suite performed materially better than the acceptance floor, but its size and construction do not support a statistically defensible 99%-class reliability estimate.

The project combines a fixed operational L0-L3 baseline with ongoing L4 research. Known limitations and the boundaries of the accepted tests remain documented; further research does not automatically reopen the fixed layers.

For the rationale behind the conversational-memory architecture, trade-offs against other memory systems, and the planned path from single-pass micro-memory to pressure-triggered and eventually keyed/deterministic memory updates, see [docs/MEMORY_STRATEGY.md](docs/MEMORY_STRATEGY.md).

For an optional external-knowledge integration pattern using a human-curated DokuWiki, deterministic graph/section structure, and a compact lexical rescue index, see [docs/DOKUWIKI_SEARCH_SUBSYSTEM.md](docs/DOKUWIKI_SEARCH_SUBSYSTEM.md). This is intentionally separate from LFO's internal L0-L4 architecture and may later be exposed through the L3 retrieval/resolution layer.

As of **2026-10-01**, QwenChat v9.3 has passed the defined memory-path validation scope on the constrained reference hardware. It preserves v9.2 single-pass micro-memory as the normal path, adds pressure-triggered compaction at `>=4` pending notes or `>=108` pending-note characters, and uses at most one focused memory-only recovery when the user explicitly asks the system to remember something but the single-pass note is empty. Invalid final-answer sentinels are also recovered without regenerating memory, and correction-prefix normalization is hardened across `CORR`, `CORR:` and `CORR :` variants. Isolated end-to-end tests passed both count-pressure and char-pressure compaction, while ordinary implicit memory remains single-pass. Raw JSONL history remains authoritative; rolling memory remains a lossy orientation layer.

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
- **Persistent conversation continuity:** recent raw turns, micro-memory, and compacted rolling state survive process restarts; `/exit` ends the process, while `/clear` explicitly resets active memory without deleting historical logs.
- **Conversation continuity across frontier calls:** bounded persistent memory, recent dialogue, and selectively retrieved exact historical snippets are supplied to LOCAL routing, frontier delegation, and post-frontier synthesis.
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
- a stable place to implement metacognitive and Humanâ€“AI bias-balancing experiments;
- the ability to use different local hardware tiers without changing the user-facing interaction model.

## Scalability of single-pass memory

The v9.2 single-pass memory design is **not specific to the constrained CPU notebook used for validation**. The notebook makes the latency benefit unusually visible, but the architectural gain applies across hardware tiers.

The key change is structural: the local model already performs the answer or post-frontier synthesis inference, and v9.2 asks that same inference to also emit a very small structured `memory_note`. The wrapper then persists that note without launching a second memory-model inference. This does not require a second copy of the model, a second concurrent KV cache, or meaningful additional VRAM. The incremental cost is limited to a small output schema and a short metadata field.

Practical scaling expectations:

| Hardware tier | Expected effect of v9.2 |
| --- | --- |
| CPU-only / constrained host | Largest absolute latency gain. On the validated notebook, ordinary post-answer memory work fell from roughly 18â€“21 s to commonly 0.01â€“0.05 s. |
| ~6 GB VRAM | The removed second inference is already much faster than on CPU, but still consumes prompt evaluation, decode, scheduler, and runtime overhead. Single-pass therefore remains useful for latency and efficiency. |
| ~16â€“17 GB VRAM | More VRAM can be spent on a larger model, higher-quality quantization, or more context without changing the single-pass memory architecture. A stronger local model may also improve semantic extraction quality. |
| 24 GB+ / server-class GPU | The absolute latency saving per turn may become small, but removing one model request per conversational turn still improves throughput, concurrency, and energy efficiency. |
| Multi-user service | The benefit compounds with request volume: v9.2 avoids one separate memory-note inference for each completed turn; only periodic compaction remains an additional model call. |

This should be read as an **architectural scaling argument, not a completed benchmark matrix**. The large latency reduction is directly measured on the constrained CPU host. The same design is expected to remain efficient on 6 GB, ~17 GB, and larger GPUs because the memory side-channel adds negligible model-residency overhead, but those tiers should be benchmarked separately before making hardware-specific latency or throughput claims.

The main scaling boundary is therefore not VRAM but **side-task complexity**. A small schema such as `route + answer + memory_note` is well suited to single-pass generation. If future versions add many independent classifiers, confidence signals, user-model updates, retrieval queries, or tool plans into the same response, those side tasks may eventually compete with answer quality and should then be split into dedicated or background components.

Historically, v9.2 used separate compaction every five completed memory steps. The accepted L1 baseline uses the later v9.3 pressure thresholds described below; routine L1 tuning is closed while L4 is developed.

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

The relationship is not purely downstream: **contributed local Ollama context and timeout support to Codex Router; merged upstream in [PR #925](https://github.com/duolahypercho/codex-router/pull/925).**

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

## Humanâ€“AI bias balancing research

A major research track for this architecture is **Humanâ€“AI bias balancing**.

The working hypothesis is that Humanâ€“LLM interaction can form a reciprocal feedback loop:

- human confirmation/myside bias, automation bias, confidence miscalibration, and framing affect how AI advice is requested and interpreted;
- LLM sycophancy, agreement bias, context sensitivity, and fluent overconfidence can reinforce the user's initial framing;
- personalization can improve assistance but can also become a higher-order **confirmation machine** if it learns what the user prefers rather than where the user's reasoning is poorly calibrated.

The local layer provides a natural experimental location for an auditable **Local Epistemic Balancer**. It can inspect the user request before frontier escalation and inspect the frontier result before presenting it to the user.

The goal is not to create an â€śunbiased AI.â€ť The goal is to study whether a local mediator can improve **appropriate reliance**: accepting useful AI guidance while resisting misleading guidance, without merely suppressing disagreement or maximizing user satisfaction.

See [`docs/HUMAN_AI_BIAS_BALANCER.md`](docs/HUMAN_AI_BIAS_BALANCER.md).

A narrower **generic, non-personalized mediation** workstream is documented in [`docs/GENERIC_EPISTEMIC_MEDIATOR.md`](docs/GENERIC_EPISTEMIC_MEDIATOR.md). It focuses on operationalizing observable interaction-level phenomena, measuring **bias magnitude relative to explicit reference/control conditions** rather than assigning a generic risk score, defining auditable pre/post-response interventions, and evaluating direct versus mediated interaction on reproducible benchmarks. Candidate implementation ideas that are not yet frozen are collected in [`docs/CANDIDATE_SOLUTION_DESIGNS.md`](docs/CANDIDATE_SOLUTION_DESIGNS.md).

L4 uses `EpistemicObservation` as its core object and SurrealDB (`lfo / epistemic / observations`) as its canonical store; full conversation sources remain in L0. v9.6.1 implements write-mostly recording with explicit `/analyze` reads. Observations remain separate from L2 factual evidence. Framing and presupposition are not automatically biases.

The L4 substrate is now documented through frozen R1/R2/A1/D1/A2/P1/P2 baselines. v9.6.1 operationally enables only conservative post-L0 recording and explicit `/analyze`; P1/P2 response intervention remains OFF. The consolidated research boundary and future bias-magnitude work are in [`docs/GENERIC_EPISTEMIC_MEDIATOR.md`](docs/GENERIC_EPISTEMIC_MEDIATOR.md), while runtime behavior is in [`docs/L4_RECORDING_MANUAL_ANALYSIS.md`](docs/L4_RECORDING_MANUAL_ANALYSIS.md). The historical pre-freeze L4 design notes are retained under `docs/archive/`.

A separate possible research track, [auditing Russian propaganda susceptibility](docs/RUSSIAN_PROPAGANDA_RESILIENCE_RESEARCH.md), proposes a claim-level benchmark for factual accuracy, framing, manipulated source context, and changes between FRONTIER output and local synthesis. It specifies implementation steps, controls, scoring, and evidence limits above v9.6.2; it is not an implemented propaganda detector or a completed evaluation.

## Documentation map

- **Install/runtime:** [v9.6.3 release notes](docs/RELEASE_V9.6.3.md) · [runtime-priority experiment](docs/RUNTIME_PRIORITY_EXPERIMENT_V963.md) · [Windows bootstrap](docs/WINDOWS_BOOTSTRAP_BUILD.md) · [host validation/tuning](docs/NOTEBOOK_SETUP.md) · [architecture](docs/ARCHITECTURE.md)
- **Memory/provenance:** [runtime storage and logs](docs/MEMORY_AND_LOGGING.md) · [memory strategy](docs/MEMORY_STRATEGY.md) · [L2 frozen baseline](docs/L2_FROZEN_BASELINE.md) · [L3 frozen baseline](docs/L3_FROZEN_BASELINE.md)
- **L4 runtime:** [recording and manual analysis](docs/L4_RECORDING_MANUAL_ANALYSIS.md) · [v9.6.1 gate](docs/L4_V961_GATE1.md) · frozen L4 baselines in `docs/L4_*_FROZEN_BASELINE.md`
- **Research:** [Balancing the Loop](docs/HUMAN_AI_BIAS_BALANCER.md) · [Generic Epistemic Mediator](docs/GENERIC_EPISTEMIC_MEDIATOR.md) · [Russian propaganda resilience proposal](docs/RUSSIAN_PROPAGANDA_RESILIENCE_RESEARCH.md) · [candidate solution designs](docs/CANDIDATE_SOLUTION_DESIGNS.md)
- **Alternative Codex-first branch:** [Codex Router notes](docs/CODEX_ROUTER_NOTES.md)
- **Historical records:** [docs/archive/](docs/archive/README.md)

## Repository layout

```text
.
|-- README.md
|-- LFO.ps1
|-- experiments/
|   |-- runtime-priority-l4-pilot.json
|   `-- runtime-priority-counterbalanced.json
|-- install/
|   `-- Install-LFO.ps1
|-- launch/
|   |-- Start-LFO.ps1
|   |-- Start-LFO-CPU.ps1
|   |-- Start-LFO-GPU.ps1
|   `-- View-LFOConversationLog.ps1
|-- config/
|   `-- QwenChat.config.psd1
|-- policy/
|-- schema/
|   `-- L4Observations.surql
|-- src/
|   |-- QwenChat.ps1
|   |-- QwenMemory.ps1
|   `-- LfoL4Runtime.ps1
|-- tests/
`-- docs/
    |-- ARCHITECTURE.md
    |-- ROADMAP.md
    |-- WINDOWS_BOOTSTRAP_BUILD.md
    |-- NOTEBOOK_SETUP.md
    |-- MEMORY_AND_LOGGING.md
    |-- MEMORY_STRATEGY.md
    |-- L4_RECORDING_MANUAL_ANALYSIS.md
    |-- HUMAN_AI_BIAS_BALANCER.md
    |-- GENERIC_EPISTEMIC_MEDIATOR.md
    `-- archive/
```

## Hardware and storage requirements

The current reference executor is `qwen3.5:4b-q4_K_M` through Ollama. The orchestration code itself is very small; most resource use comes from the local model, its runtime, and optional long-term research logs.

| Resource | Validated / practical baseline | Recommendation |
| --- | --- | --- |
| CPU | x86-64 CPU; CPU-only operation has been validated on an older 2-core / 4-thread notebook CPU | A newer 4-core-or-better CPU improves interactive latency |
| RAM | **8 GB validated** for a constrained CPU-only proof of concept with a 5k-class context and normal paging | **16 GB or more** for more comfortable CPU-only use and larger headroom |
| GPU | **Not required**; CPU-only mode is supported | A discrete GPU substantially improves latency and may allow a larger context, depending on VRAM and runtime support |
| Local model | `qwen3.5:4b-q4_K_M`, about **3.3 GiB** on disk in the validated Ollama installation | The same model is the current reference; other local chat models can be substituted |
| Context | 4096 is a conservative fallback; **5120 was validated** on the constrained 8 GB host | Size context per host rather than copying another machine's profile |
| Free disk space | **8 GB** is a practical starting point for the reference model plus runtime overhead | **10 GB or more** leaves useful headroom for runtimes and growing logs |

The repository source, policies, and configuration are **well under 1 MiB**. Disk use is therefore dominated by:

- Ollama model weights (about 3.3 GiB for the current reference model);
- Ollama, Node.js, and Codex CLI runtime files;
- append-only conversation and research JSONL logs, which grow with use.

The 8 GB RAM result is a **compatibility/portability baseline, not a performance target**. On that class of CPU, local answers and post-turn memory work can take tens of seconds. A discrete GPU is optional architecturally; it mainly changes latency and the context size that can be used comfortably.

## Software requirements

For the supported Windows bootstrap path:

- Windows PowerShell 5.1 on a supported Windows 10/11 system;
- the Windows `winsqlite3.dll` ABI used by the project;
- network access for source/runtime/model acquisition when a compatible local
  copy is not already available.

The bootstrap can use Git when present and otherwise falls back to a GitHub
source archive. It reuses or provisions compatible Ollama and SurrealDB
runtimes. If Codex CLI is missing, it offers to run the official Codex Windows
installer; Codex authentication is still required before FRONTIER requests can
succeed.

Normal users do not need Node.js, npm, Codex Router, a separately cloned
repository, or a manually created Ollama alias merely to install LFO.

## Quick start

For Windows, use the bootstrap commands near the top of this README. The
bootstrap installs/reuses the supported runtime components, creates both CPU and
GPU aliases/launchers, prepares the installation-local memory/L4 stores and runs
the deterministic L4 acceptance gate.

After installation, the primary entrypoint is:

```powershell
& "$env:LOCALAPPDATA\LFO\launch\LFO.ps1"
```

This uses automatic device selection and High inference priority by default. Explicit CPU/GPU compatibility launchers remain available:

```powershell
& "$env:LOCALAPPDATA\LFO\launch\Start-LFO-GPU.ps1"
& "$env:LOCALAPPDATA\LFO\launch\Start-LFO-CPU.ps1"
```

For post-bootstrap hardware validation and tuning, see
[`docs/NOTEBOOK_SETUP.md`](docs/NOTEBOOK_SETUP.md). For current storage/log
semantics, see
[`docs/MEMORY_AND_LOGGING.md`](docs/MEMORY_AND_LOGGING.md).

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

**v9.6.3 is the current operational Windows runtime on `main`.** LOCAL/FRONTIER routing, synthesis, persistent memory and conservative L4 recording retain their accepted semantics. v9.6.3 adds the controlled runtime entrypoint, automatic/explicit device selection, unattended experiments, compact dotted wait/watchdog output, and High inference priority as the production default.

**v9.6.2 remains the previous immutable tagged and Zenodo-archived release boundary.** The v9.6.3 promotion does not reopen the frozen L2/L3 baselines or enable P1/P2 response intervention.

Further detector coverage, automatic analytics scheduling and response intervention require separate scope and validation. The accepted operational L4 behavior remains conservative recording plus manual `/analyze`.

## License

No open-source license has been selected yet. Until a license is added, normal copyright rules apply.
