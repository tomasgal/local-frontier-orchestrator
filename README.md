# Local Frontier Orchestrator

**Development status (2026-10-09): `v9.4-dev5-compact-read` — experimental Dev5 A+B / G2 variant, testing PAUSED after first dev3-vs-dev5 pilot.** Dev3 structured writes, Dev4 observability/opt-in L2 reads, and Dev5 G2 offline transactional regression gates have PASS evidence. **Dev5 full-loop net speedup over dev3 is NOT established; experimental features remain OFF by default.** The `main` branch remains at the validated v9.3 baseline; no experimental dev5 feature was promoted or merged.

**Restart here:** [G2 handoff and known limitations](docs/DEV5_G2_HANDOFF.md) · [Dev5 experiments and timings](docs/DEV5_PERFORMANCE_EXPERIMENTS.md) · [dev3/dev5 benchmark protocol](docs/DEV5_VS_DEV3_BENCHMARK_PROTOCOL.md) · [roadmap](docs/ROADMAP.md).

Local Frontier Orchestrator is a local-first conversational orchestration layer for combining a small local language model with a stronger remote frontier model.

The project starts from a simple premise: a local model does not need to outperform a frontier model in general intelligence to be useful. It can remain the always-available conversational layer, handle inexpensive or privacy-sensitive work locally, preserve conversational continuity, and selectively escalate tasks that require fresh information, external verification, stronger reasoning, or broader tool access.

The current reference implementation uses **Qwen via Ollama** as the local conversational/orchestration model and the authenticated **OpenAI Codex CLI** as an on-demand frontier subagent. It does not require an OpenAI API key for the frontier path when Codex CLI is already authenticated.

For v9.2 memory validation, the project uses a **conservative 90% engineering acceptance floor** for qualitative semantic behavior. This is not a claim that measured reliability is 90% or below 99%: the development smoke suite performed materially better than the acceptance floor, but its size and construction do not support a statistically defensible 99%-class reliability estimate.

This repository is intentionally experimental. Routing, synthesis policy, context handling, and future bias-balancing behaviour are being tuned through longer-term use rather than optimized around a small fixed benchmark.

For the rationale behind the conversational-memory architecture, trade-offs against other memory systems, and the planned path from single-pass micro-memory to pressure-triggered and eventually keyed/deterministic memory updates, see [docs/MEMORY_STRATEGY.md](docs/MEMORY_STRATEGY.md).

As of **2026-10-01**, QwenChat v9.3 has passed the defined memory-path validation scope on the constrained reference hardware. It preserves v9.2 single-pass micro-memory as the normal path, adds pressure-triggered compaction at `>=4` pending notes or `>=108` pending-note characters, and uses at most one focused memory-only recovery when the user explicitly asks the system to remember something but the single-pass note is empty. Invalid final-answer sentinels are also recovered without regenerating memory, and correction-prefix normalization is hardened across `CORR`, `CORR:` and `CORR :` variants. Isolated end-to-end tests passed both count-pressure and char-pressure compaction, while ordinary implicit memory remains single-pass. Raw JSONL history remains authoritative; rolling memory remains a lossy orientation layer.

## v9.4 experimental status — Dev3 → Dev4 → Dev5 (checkpoint 2026-10-09)

**Dev3: functional L2 structured memory validated.** The scoped SQLite fact store provides typed attributes/relations, multi-fact updates, supersession history, source-turn provenance, correction, alias isolation, fail-closed atomic turn writes and restart continuity. Tests covered two Windows host classes and isolated live Qwen writing/correction on the constrained reference host. Dev3's post-write prompt/runtime optimization showed one-sample latency reductions; cross-host/repeated gains were not established.

**Dev4: observability and selective L2 read-side validated.** Per-phase model/assembly/persistence traces and bounded current-fact retrieval were introduced, with a deterministic read-side guard because the local model had echoed old retrieved facts as new write operations. On an isolated live four-fact ORION read, the guard suppressed four model-derived operations, left SQLite unchanged and preserved the answer. L2 retrieval is still opt-in.

**Dev5: architecture-first performance and G2 persistence hardening are experimental.** Candidate A generates only `route` and `answer` when an actual protected L2 read makes memory operation output unnecessary. Candidate B separately removes unused write-extraction instructions on that same eligible path. Candidate C moves L2 evidence to a lower-priority quoted message; one adversarial control pair showed no proven C advantage. A separate narrow mixed-current-user evidence path permits exactly source-validated RAM updates in supported forms. All optional switches, including `Memory.StructuredReadEnabled`, are **false in default configuration**. Normal declarative writes and synthesis retain the full validated schema.

### What is confirmed

- **Targeted live A mechanism:** on the synthetic ORION read, output fell **294 → 45 tokens (-84.7%)** with the compact schema; full-schema control still emitted 294. This demonstrates removal of wasted generation on an *eligible* read path, not whole-project speedup.
- **Targeted live A+B mechanism:** prompt input fell **1641 → 1042 tokens (-36.5%)** versus A-only. The observed one-sample answer wall fell **154.549 → 111.614 s**, with correct answers and no new L1/L2 state. Time attribution is exploratory and not statistically repeated.
- **Bounded mixed-user feature:** a one-turn isolated Qwen test correctly answered a question while storing a single exact-source, opt-in RAM64→96 update, retaining scope, history and provenance. Wider language coverage and adversarial safety are **not** established.
- **G2 Windows offline hardening:** **9/9 regression suites PASS**, including SQLite `BEGIN IMMEDIATE` guarded alias/scope authorization, writer lock, duplicate replay, cross-scope rejection, rollback under SQL failure and mixed-wrapper persistence failure reporting. This does not make the SQLite + L0 JSONL stores a single distributed transaction.
- **Comparator contract:** synthetic-only comparator self-test PASS, including eight negative contract cases. It does not count as actual performance evidence.
- **Measured model-free component pilot:** 4 matched AB/BA repetitions (pinned dev3 `a34658b8...` / dev5 `75e0b4b8...`) passed correctness. Five of six shared PowerShell/SQLite operations had dev5 medians ~12–17% slower, but subsequent paired-sign analysis found **none of the six consistently slower or faster over all 4 pairs**; absolute differences were millisecond-scale. This result does not establish either a stable regression or a net system gain.

### First live dev3/dev5 pilot: useful diagnosis, **not A+B acceptance**

Two isolated TEMP runs used `qwen3.5:4b-q4_K_M`, Ollama 0.34.4, `think=false`, context hint 5120 and the same synthetic BENCH_SERVER read request. Both answered the four requested facts correctly.

| Pilot measure | dev3 pinned `a34658b8...` | dev5 pinned `1f57ec16...` |
|---|---:|---:|
| Answer wall | 184.84 s | 130.54 s |
| Input tokens | 1508 | 1517 |
| Output tokens | 298 | 234 |
| L2 operations reported applied | 4 | 1 |
| L1 micro-note | none | none |

The observed dev5 turn was **54.30 s / 29.4% shorter**, but the sequential one-pair measurement does **not** prove a repeatable, weighted or causal speedup. The dev5 trace identified `l2_read_status=write_only_turn`, `l2_read_items=0`, `dev5_local_output_mode=full`, `dev5_read_policy_mode=full`, `l2_read_write_guard_active=false`, and `l2_write_source=model-unmodified`. Its request began with `State BENCH_SERVER ...`; the heuristic treated this imperative read request as a declarative update. **A and B did not activate.** The model suggested four memory operations and one was reported persisted despite the user's read-only intent. Which row was written requires a separate SQLite audit; the trace alone does not establish the exact predicate or historical effect.

**This failure is actionable diagnostic evidence.** The goal is not to bolt on ever more regex exceptions or rewrite test prompts until they trigger A+B. For real workloads, measure routing hit/miss, extra token/time cost, model-call retries, memory mutation containment and ability to explain the decision from trace. Incorrect optimization selection may incur bounded extra cost; unsupported inference from earlier memory must not silently authorize new durable facts.

### What is NOT confirmed and what happens next

No repeatable representative **dev5-over-dev3 end-to-end net speedup**, no measured natural-workload optimization eligibility rate/weights, no comprehensive mixed-intent write safety, no RPi5/heterogeneous-node performance transfer and no deployment-ready security conclusion. An older full-schema timing residual (~110.95 s) was not reproduced in a later instrumented trial; its root cause is unknown. No default opt-in switch should be promoted on this evidence.

The pause checkpoint is documented in [`docs/DEV5_G2_HANDOFF.md`](docs/DEV5_G2_HANDOFF.md). On restart, first audit the single reported dev5 SQLite write **offline**, then freeze a natural-language five-case workload and evaluation rubric before more model calls. Separate the dev5 A+B mechanism test (eligible scoped reads) from the dev3/dev5 whole-system benchmark (all routing outcomes, including heuristic misses). Match evidence, model digest and runtime conditions; stop early on failed correctness or excessive cost. Keep benchmarks in fresh TEMP state, and do not transfer host-specific tuning into common orchestration.

**Raspberry Pi/edge transfer hypothesis:** work on memory-constrained Raspberry Pi inference motivates reducing unnecessary tokens, memory/context traffic, extra inference and blocking before tuning hardware-specific knobs. The roadmap cites *Pushing Four Raspberry Pis to the Memory Wall* (DOI `10.5281/zenodo.20357376`); informal references to a `5x RPi5` setup are not an independently verified replication specification here. Dev5 supports the **software work-elimination principle**, but LFO has not reproduced the paper, run a five-RPi5 system, measured energy/bandwidth or shown that its speedups transfer to Raspberry Pi devices. See the G2 handoff for evidence boundaries.

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
- a stable place to implement metacognitive and Human–AI bias-balancing experiments;
- the ability to use different local hardware tiers without changing the user-facing interaction model.

## Scalability of single-pass memory

The v9.2 single-pass memory design is **not specific to the constrained CPU notebook used for validation**. The notebook makes the latency benefit unusually visible, but the architectural gain applies across hardware tiers.

The key change is structural: the local model already performs the answer or post-frontier synthesis inference, and v9.2 asks that same inference to also emit a very small structured `memory_note`. The wrapper then persists that note without launching a second memory-model inference. This does not require a second copy of the model, a second concurrent KV cache, or meaningful additional VRAM. The incremental cost is limited to a small output schema and a short metadata field.

Practical scaling expectations:

| Hardware tier | Expected effect of v9.2 |
| --- | --- |
| CPU-only / constrained host | Largest absolute latency gain. On the validated notebook, ordinary post-answer memory work fell from roughly 18–21 s to commonly 0.01–0.05 s. |
| ~6 GB VRAM | The removed second inference is already much faster than on CPU, but still consumes prompt evaluation, decode, scheduler, and runtime overhead. Single-pass therefore remains useful for latency and efficiency. |
| ~16–17 GB VRAM | More VRAM can be spent on a larger model, higher-quality quantization, or more context without changing the single-pass memory architecture. A stronger local model may also improve semantic extraction quality. |
| 24 GB+ / server-class GPU | The absolute latency saving per turn may become small, but removing one model request per conversational turn still improves throughput, concurrency, and energy efficiency. |
| Multi-user service | The benefit compounds with request volume: v9.2 avoids one separate memory-note inference for each completed turn; only periodic compaction remains an additional model call. |

This should be read as an **architectural scaling argument, not a completed benchmark matrix**. The large latency reduction is directly measured on the constrained CPU host. The same design is expected to remain efficient on 6 GB, ~17 GB, and larger GPUs because the memory side-channel adds negligible model-residency overhead, but those tiers should be benchmarked separately before making hardware-specific latency or throughput claims.

The main scaling boundary is therefore not VRAM but **side-task complexity**. A small schema such as `route + answer + memory_note` is well suited to single-pass generation. If future versions add many independent classifiers, confidence signals, user-model updates, retrieval queries, or tool plans into the same response, those side tasks may eventually compete with answer quality and should then be split into dedicated or background components.

Periodic compaction is intentionally still separate in v9.2. It occurs every five completed memory steps by default and remains the next obvious optimization target if deployment scale makes that cost material.

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
    ├── QwenChat.ps1
    └── QwenMemory.ps1
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

QwenChat v9.3 keeps persistent local state under `%LOCALAPPDATA%\LocalFrontierOrchestrator` by default. Ordinary memory remains **single-pass**: the LOCAL answer or post-frontier synthesis may emit a bounded 0–40 character user-delta micro-note without a separate per-turn memory inference. Pending notes are compacted into a 0–160 character rolling state when semantic pressure reaches **4 notes or 108 pending-note characters**. If the user explicitly asks the system to remember something and the single-pass note is empty, the wrapper permits at most one focused memory-only recovery call. Exact historical data is not compressed away: full conversation JSONL remains authoritative and bounded relevant raw snippets can be retrieved when needed.

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

- **v9.4-dev5-compact-read (G2, experimental):** document the already validated Dev3 write and Dev4 read/observability paths; characterize Dev5 A+B's read-path token savings and the live heuristic-misroute/persistence anomaly; complete natural-workload full-loop net-gain evaluation before any release promotion. See [G2 handoff](docs/DEV5_G2_HANDOFF.md);
- keep all Dev5 opt-in read/compact/lean/lower-trust/mixed features disabled in defaults until evidence justifies promotion;
- preserve the v9.3 `main` baseline and do not alter production memory when testing;
- long-term routing quality;
- faithful-but-useful frontier synthesis;
- structured trace logging;
- additional host validation and context sizing;
- suppressing internal retrieval metadata from user-facing answers;
- multi-host profiles;
- bias-aware mediation;
- future edge/SBC execution.

## License

No open-source license has been selected yet. Until a license is added, normal copyright rules apply.
