# v9.6.3 Windows runtime-priority experiment

Status: **ACCEPTED AS BOUNDED HOST-RUNTIME EVIDENCE — 2026-10-20**

This document records the experiments used to decide the default Windows inference process priority for LFO v9.6.3. The result is a **host-scoped runtime decision**, not a universal benchmark claim.

**Published technical note:** [*Windows Process Priority and Local LLM Inference: A Counterbalanced Host-Runtime Study*](https://zenodo.org/records/23610929), DOI [10.5281/zenodo.23610929](https://doi.org/10.5281/zenodo.23610929). The publication packages the counterbalanced result together with machine-readable research data, figures, the frozen statistical analysis contract and reproduction scripts. Its contribution is the empirical quantification of how the documented Windows process-priority mechanism translated into local-LLM throughput on this validated host, not a claim that the underlying Windows scheduling behavior is novel.

## Motivation

The experiment was motivated by Daniel Correa Villa's architecture-first work on a Raspberry Pi 5 inference cluster, where apparently secondary host activity measurably affected bandwidth-limited autoregressive decode. LFO transfers the methodological question — whether host/runtime conditions materially affect local inference — without claiming that a Windows Skylake-U notebook reproduces the Raspberry Pi memory-wall mechanism.

Related source: Daniel Correa Villa, *Pushing Four Raspberry Pis to the Memory Wall: Bit-Exact 30B Mixture-of-Experts Inference, +16% over the Public Record*, DOI `10.5281/zenodo.20357376`; reproducibility branch `danielcorrea-hellomatik/distributed-llama:pi5-cluster`.

## Validated host and workload boundary

Measurements were obtained on one constrained Windows 10 CPU-only notebook: Intel Skylake-U class, 2 physical cores / 4 logical threads, approximately 8 GB RAM, Ollama 0.34.4, `lfo-qwen3.5-4b-cpu5k:latest`, 5120-token context. Ollama placement was CPU-only (`size_vram_bytes = 0`).

Each measured prompt ran in a fresh isolated conversation/process state; FRONTIER/Codex calls were suppressed for benchmark samples; each condition had a warm-up before measured work. The result does not establish the same effect on other CPUs, GPU inference, other operating systems, larger models or concurrent multi-user workloads.

## Pilot: L4 participation and process priority

Definition: [`experiments/runtime-priority-l4-pilot.json`](../experiments/runtime-priority-l4-pilot.json)

| Condition | Decode tok/s | Prefill tok/s | Answer time |
| --- | ---: | ---: | ---: |
| Normal + L4 | 3.8482 | 18.9882 | 182.22 s |
| Normal, L4 off | 3.8369 | 18.5165 | 183.12 s |
| High, L4 off | 4.2557 | 22.1703 | 151.42 s |

The Normal + L4 and Normal without L4 conditions were effectively indistinguishable at this sample size. All 9 measured L4 turns produced detector **ABSTAIN**, so this bounds the overhead of an enabled L4/SurrealDB runtime plus an ABSTAIN callback path; it is **not** a benchmark of sustained positive R1 observation writes.

Because the pilot used fixed condition blocks, the apparent High-priority effect required a counterbalanced confirmation.

## Counterbalanced Normal versus High confirmation

Definition: [`experiments/runtime-priority-counterbalanced.json`](../experiments/runtime-priority-counterbalanced.json)

Six blocks alternated order: Normal -> High, High -> Normal, repeated three times. Each condition used the same three isolated LOCAL prompts, producing **18 Normal and 18 High measured samples; 36/36 passed**.

| Metric | Normal | High | Relative change |
| --- | ---: | ---: | ---: |
| Prefill | 18.7034 tok/s | 22.0197 tok/s | **+17.7%** |
| Decode | 3.8150 tok/s | 4.1036 tok/s | **+7.6%** |
| Answer time | 181.68 s | 158.41 s | **-12.8%** |

Answer time is secondary because generated-token counts vary. Prefill/decode throughput are the primary performance metrics.

### Paired evidence

Pairing by block and prompt gives 18 matched High/Normal pairs.

- **Prefill:** High faster in **18/18 pairs**; mean paired gain +3.316 tok/s; descriptive paired 95% CI +2.308 to +4.324 tok/s; paired t-test `p = 2.38e-6`.
- **Decode:** High faster in **12/18 pairs**; mean paired gain +0.289 tok/s; 95% CI -0.007 to +0.584 tok/s; paired t-test `p = 0.055`. The direction is consistent with the pilot, but less cleanly established than prefill.
- **Answer time:** mean paired change -23.27 s; paired t-test `p = 0.0036`, with the output-length caveat above.

Order reversal did not remove the prefill effect: Normal -> High blocks showed **+16.6%** High prefill; High -> Normal blocks showed **+18.9%**.

### Variability

| Metric | Normal CV | High CV |
| --- | ---: | ---: |
| Prefill | 11.4% | 1.8% |
| Decode | 14.4% | 8.3% |
| Answer time | 15.7% | 6.6% |

High therefore increased mean prefill throughput and substantially reduced observed run-to-run variation on the validated host.

## Priority application verification

The runner recorded process-tree priority after model warm-up. In all counterbalanced High conditions, both `ollama` and the actual `llama-server` inference process were High. In all Normal conditions both were Normal. The result is not explained by changing only the PowerShell wrapper.

## Interpretation and production decision

The Raspberry Pi motivation and Windows result have different signatures. Correa Villa's result is consistent with a strong decode memory-bandwidth wall. On this Windows CPU-only notebook, scheduler priority produced the clearest effect in **prefill**, while decode improved more modestly and noisily. The bounded interpretation is therefore a mixed scheduler/CPU-resource and memory-pressure regime, not a demonstrated reproduction of the Raspberry Pi memory-wall mechanism.

For v9.6.3 Windows runtime policy:

- **High** is the default production inference priority;
- **Normal** remains an explicit override/control;
- SurrealDB/L4 stays at Normal priority;
- `Realtime` is not a production default;
- no L4/no-L4 branch is needed in the normal performance profile.

The production decision is stronger than the mechanism claim: High is useful on the validated host; the exact microarchitectural cause remains open to future telemetry work.

## Reproduction

```powershell
.\LFO.ps1 -Experiment .\experiments\runtime-priority-l4-pilot.json
.\LFO.ps1 -Experiment .\experiments\runtime-priority-counterbalanced.json
```

The runner records resolved state, per-sample JSONL metrics, summaries, process-priority verification, Ollama placement, service logs and checkpoint state under the installation experiment-results directory.
