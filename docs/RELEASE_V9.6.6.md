# LFO v9.6.6 — Windows UMA and terminal usability

**Reference-host acceptance:** 2026-11-26  
**Type:** backwards-compatible Windows runtime expansion; release candidate pending exact-source CI and publication.  
**Accepted host implementation:** `69039ded73324b8064bbb96ecb29e037f50cf3ef`.

## Changes

- Third Windows execution profile: UMA, automatic selection on a UMA installation, shared existing native Ollama model store and a 35B Q8 alias with 16k context. No duplicate weight download for the alias.
- Ollama v1/v2 manifest compatibility; persistent import/export paths; SSH and SkipLaunch suppress Explorer.
- Terminal-oriented Markdown renderer, including wrapped aligned tables, optional outer pipes and control-character stripping. Raw Markdown export remains separate from rendering.
- Sequential UTF-8 prompt import using a standalone three-pipe separator; ordinary interactive routing and memory semantics retained. Explicit last-answer and monthly log export.
- UMA generation ceilings of 4096/8192 tokens with heuristic context headroom; original CPU/GPU generation defaults retained. Truncated local structured output is marked incomplete; invalid envelopes no longer appear as raw internal JSON. Existing frontier synthesis fallback retained.
- Singleton prompt arrays preserved in unattended experiments. A production RocksDB process/endpoint check refuses a detected live source before physical L4 datastore copying.
- v9.6.5 research tooling retained; no promotion of P1/P2 or reopening of frozen L0–L4 milestones.

## Evidence and boundaries

Windows 11 Pro reference host: Ryzen AI Max+ 395, Radeon 8060S, 128 GB unified LPDDR5X; native Ollama 0.40.16, SurrealDB 3.3.0, Windows PowerShell 5.1. The model was loaded with 16,384-token context and Ollama reported 35,539 MiB of 35,539 MiB in GPU residency.

| Reference-host test | Result |
| --- | --- |
| Bootstrap/reinstall and L4 deterministic suite | PASS, 33 checks |
| LOCAL, FRONTIER transport and local synthesis | PASS |
| L4 recording and manual analysis | PASS |
| L3 runtime-context offline fixture | PASS, 1091 characters saved; fallback parity |
| v9.6.5 research tooling | PASS, 16 parameter configurations, 2 replay items, 12 audit rows |
| Markdown table rendering and import/export | PASS, six targeted table cases and sequential batch |
| Isolated LOCAL-only experiment, L4 OFF | PASS, 38.33 decode tokens/s |
| Isolated LOCAL-only experiment, L4 ON | PASS, 37.46 decode tokens/s, observation CREATED |
| Long LOCAL response after quote mitigation | PASS, 1947 generated tokens, 53.13 s |
| Multi-example response with literal double/triple quotes | PASS, 696 generated tokens, 19.53 s |

The L4 ON/OFF samples used different prompts and one measured sample per condition; they are smoke tests, not evidence of L4 overhead. Throughput figures refer to the tested host and model, not general performance. The source contract and legacy-profile checks are deterministic; this cycle did not repeat live inference on CPU and discrete-GPU hosts.

A valid JSON envelope sometimes closed its answer early (Ollama done_reason=stop), near a quotation mark. The UMA-only writing guidance mitigated the reproduced example and preserved quotation marks in a subsequent code task. The underlying cause is not established, and general completeness is not guaranteed. The code task also contained a model-generated variable-name error. No correctness or debiasing-efficacy claim follows from transport acceptance.

Streaming and routing latency improvements remain separate future work. The research logging profile retains raw conversations and memory snapshots; protect them and intentionally configure exchange access. Do not copy the production L4 store while its service is active.

See [UMA bootstrap](UMA_BOOTSTRAP.md), [v9.6.5 release](RELEASE_V9.6.5.md) and [runtime-priority experiment](RUNTIME_PRIORITY_EXPERIMENT_V963.md).
