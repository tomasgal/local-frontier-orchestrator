# LFO v9.6.3 release notes

Date: **2026-10-20**

Status: **PROMOTED ON `main` AS THE CURRENT WINDOWS OPERATIONAL RUNTIME**

v9.6.3 promotes the controlled runtime/experiment candidate without reopening the accepted L0-L4 semantics. v9.6.2 remains the previous immutable tagged/Zenodo release boundary.

## Production runtime changes

- adds top-level **`LFO.ps1`** as the primary Windows entrypoint for ordinary chat and declarative experiments;
- supports `-Device Auto|CPU|GPU`, with explicit CLI device selection taking precedence over an experiment file;
- makes Windows inference priority **High by default** for ordinary production launch, while retaining an explicit `-Priority Normal` override;
- applies/verifies priority on the configured Ollama process tree rather than treating the PowerShell wrapper as the inference process;
- leaves SurrealDB/L4 at Normal priority;
- keeps `Realtime` available only as an explicit experimental condition, not a production default;
- keeps the existing CPU/GPU launchers as compatibility wrappers around the new entrypoint;
- publishes `LFO.ps1` into the installed `launch` directory;
- starts LFO-owned Ollama and SurrealDB services headless with redirected stdout/stderr logs, removing the Windows console QuickEdit/selection stall failure mode.

## Waiting/progress behavior

Long silent waits no longer consume one console line every five seconds. A waiting operation opens one status line and appends one dot every five seconds until another event occurs or the wait completes. The unattended Qwen batch watchdog follows the same compact pattern.

## Experiment runner

The v9.6.3 runner provides declarative JSON plans, isolated per-prompt state, owned Ollama and optional isolated SurrealDB envelopes, LOCAL-only benchmark guards, warm-up/repetitions, checkpoint/resume, machine-readable results, process-tree priority verification and Ollama placement capture.

Shared definitions are under [`experiments/`](../experiments/). The accepted runtime-priority evidence and limitations are documented in [`RUNTIME_PRIORITY_EXPERIMENT_V963.md`](RUNTIME_PRIORITY_EXPERIMENT_V963.md).

## Promotion evidence

- pilot: **27/27 measured samples PASS** across Normal+L4, Normal-no-L4 and High-no-L4;
- counterbalanced confirmation: **36/36 measured samples PASS**, 18 Normal and 18 High;
- High versus Normal prefill: **+17.7% mean**, High faster in 18/18 matched pairs;
- High versus Normal decode: **+7.6% mean**, directionally positive but materially noisier;
- process-priority records confirmed the intended class on both `ollama` and `llama-server`;
- CPU placement records reported zero model VRAM placement.

These measurements justify the Windows runtime default on the validated host class; they are not a universal cross-hardware performance claim.

## Compatibility and unchanged scope

- accepted L0/L1/L2/L3 semantics are unchanged;
- conservative L4 recording and explicit `/analyze` behavior are unchanged; P1/P2 remain OFF;
- CPU/GPU model aliases and the shared Ollama model store remain compatible with the v9.6.2 bootstrap layout;
- the current macOS guidance remains a porting guide, not a supported-runtime claim.

For the previous immutable software archive, see v9.6.2 and Zenodo DOI `10.5281/zenodo.23373391`.
