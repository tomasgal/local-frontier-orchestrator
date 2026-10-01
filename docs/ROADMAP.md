# Roadmap

This roadmap describes engineering directions, not release commitments.

## Baseline reached — 2026-09-29

- First Windows/GPU reference deployment is considered stable enough to freeze as a regression baseline.
- Qwen-first LOCAL/FRONTIER routing and bounded read-only `ask_codex` are working.
- Frontier synthesis has explicit factual-preservation rules while keeping the local model as an independent editor/critic.
- Behavioural policy and common generation settings are separated from transport/orchestration code.
- Hardware placement remains host-specific and outside QwenChat request payloads.
- Public repository hygiene excludes personal paths, private hostnames, LAN details, and private hardware sizing.
- Clean second-host validation passed on an older CPU-only 8 GB Windows notebook at 4k context under normal desktop memory pressure.
- Windows npm Codex shim portability was fixed by preferring `codex.cmd` in the shared resolver.
- Persistent memory v9.1.3 reached a frozen validation point: user-delta-first micro-notes, compact rolling state, raw JSONL history, restart continuity, and isolated exact historical retrieval are functioning together without the earlier JSON-output failure mode.

## Near term

- Keep hard freshness/capability gates intentionally narrow.
- v9.1.3 memory baseline is validated on the constrained CPU-only notebook: 0–40 char user-delta notes, five-step 0–160 char normalized compaction, restart continuity, and isolated exact historical retrieval all passed.
- v9.2 single-pass micro-memory is validated on the constrained CPU-only notebook: the bounded note is produced inside the existing LOCAL answer or post-frontier synthesis inference, eliminating the separate per-turn memory-model call.
- Ordinary memory persistence dropped from roughly 18–21 seconds in the v9.1.3 baseline to commonly about 0.01–0.05 seconds; five-turn compaction remains a separate inference at roughly 19 seconds.
- Preserve raw-history authority, exact retrieval, restart continuity, correction handling, and append-only research traces while evaluating single-pass semantic quality over longer real use rather than tuning for perfect fixed-benchmark accuracy.
- Benchmark host-capacity reductions separately from the semantic change (for example smaller context/recent/retrieval budgets on constrained CPU-only hosts).
- Prevent internal retrieval turn markers such as `T34` from leaking into user-facing answers.
- Evaluate routing and synthesis over longer-term real use rather than a tiny prompt set.
- Use append-only traces for offline Local Epistemic Balancer replay and bias-analysis experiments.
- Keep host/model profiles separate; do not transplant tuned context/GPU values between machines without measurement.

## Multi-host

- Common orchestration code.
- Per-host runtime/model profiles.
- Profiles for modern GPU hosts, older CPU-oriented hosts, and edge nodes.
- Reproducible smoke tests for each runtime profile.
- No machine identity embedded in shared source files.

## Edge / accelerator exploration

Potential targets include:

- always-on local routing and retrieval;
- embeddings and reranking;
- compact structured classifiers;
- small local LLMs on SBC accelerators;
- Hailo-based execution where supported;
- Radxa/Rockchip-class accelerator modules where supported.

The orchestrator should not assume that every accelerator exposes the same model runtime or memory architecture.

## Codex-first branch

Continue separate tuning of:

```text
Codex CLI -> Codex Router -> local Qwen
```

Research goals:

- reduce agent/tool context overhead;
- characterize small-model limits under the Codex harness;
- test tool-use reliability;
- preserve compatibility with upstream Codex and Codex Router.

## Human–AI bias balancing

- define explicit mediator interventions;
- add trace schema for reliance, verification, confidence, and disagreement;
- distinguish generic from personalized policies;
- keep content beliefs out of the first personalization model;
- develop offline replay/stress tests for confirmation-machine behaviour;
- freeze an auditable experimental configuration before human-subject testing.

## Later possibilities

- local retrieval/RAG;
- project-state manifests;
- policy-driven privacy/redaction;
- additional frontier tiers;
- write-capable tools as separate capabilities with explicit safety boundaries;
- optional training/fine-tuning from curated traces after a stable task definition exists.
