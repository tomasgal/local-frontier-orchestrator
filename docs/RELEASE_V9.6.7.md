# LFO v9.6.7 — Interactive streaming and routing

**Type:** backwards-compatible Windows runtime update over immutable v9.6.6.  
**Reference-host acceptance:** 2026-11-27; development implementation `32938bc667cd373c7c72ce148fe44dc8c01d69ff`.

## Changes

- Stream Ollama NDJSON for interactive answers, with completed Markdown blocks, provisional output markers, final validation, and no duplicate replay. UMA defaults to streaming; session overrides are available on all profiles.
- Stream the dedicated thinking channel when enabled; separate it from the final answer. Preserve raw content, routing, memory and export semantics.
- Display elapsed Codex wait time on one refreshed console line; no claims about internal Codex activity.
- Explicit AUTO, LOCAL and FRONTIER session routing; LOCAL overrides freshness gates and cannot call Codex. Validate all interactive slash commands locally; help and missing/invalid parameter handling never reach inference.
- Distinguish current external verification from historical evidence in local generation and recovery. A forced LOCAL request matching a frontier hard gate receives deterministic notice before inference and in delivered/exported text.
- Record phase timings and first visible thinking/answer. Aggregate interactive multi-call answer generation tokens and duration-weighted decoding rate. Preserve legacy benchmark and trace metrics; unattended benchmark transport remains non-streaming.
- Preserve v9.6.6 tag-pinned CPU/GPU/UMA bootstrap support, existing profile defaults, L0–L4 semantics and P1/P2 intervention OFF.

## Reference-host acceptance

Windows PowerShell 5.1, native Ollama 0.40.16, Ryzen AI Max+ 395 / Radeon 8060S, 128 GB unified memory, Qwen 3.5 35B-A3B Q8, 16k context.

| Check | Result |
|---|---|
| LOCAL and FRONTIER answer streaming | PASS |
| Dedicated thinking channel streaming | PASS; first visible thinking 2.74 s, first answer block 6.40 s in one turn |
| Codex elapsed-time heartbeat and slash help | PASS |
| Forced LOCAL on web request | PASS; no Codex call; deterministic evidence notice |
| Multi-call answer telemetry | PASS; two real recovery cases (321 and 1089 generated tokens; 2 calls each) |
| Isolated LOCAL-only UMA experiment, L4 OFF | PASS; 39.2748 decode tok/s; 1608.4591 prefill tok/s; 3.409 s measured answer; full reported GPU residency |
| Batch execution and owned-process cleanup | PASS; non-streamed transport and isolated memory |

The experiment had one measured prompt and one warmup, with ambient services permitted. It is a functional regression smoke test, not a controlled performance comparison. Windows PowerShell occasionally returned no ExitCode; the existing completion-marker plus empty-stderr fallback was exercised successfully. CPU/discrete-GPU live reinstallation and inference were not repeated during this cycle.

## Epistemic and output limitations

A sequential exploratory six-prompt diagnostic, first thinking OFF then ON, yielded descriptive scores 9/12 and 10/12 on a nonvalidated working rubric. The second series had access to prior responses; no causal reasoning benefit can be inferred. The model corrected a false premise and generally acknowledged missing live evidence, but sometimes asserted unverified source/database or training-corpus claims. It also complied with a request to simulate verification, including an unsupported claim of having checked sources in the OFF condition. The deterministic notice applies to forced LOCAL requests matching a hard gate, not to all possible misleading provenance claims. Prompt guidance is not a guarantee of compliance or factual correctness. All twelve turns recorded L4 ABSTAIN; the accepted detector scope is unchanged. No new epistemic detector or intervention is introduced.

Earlier v9.6.6 structured-output completeness mitigation remains bounded; no general reliability claim. Provisional streaming is not final validated output and may be superseded. No changes to historical release tags or citation metadata.

See [v9.6.6](RELEASE_V9.6.6.md) and [UMA bootstrap](UMA_BOOTSTRAP.md).
