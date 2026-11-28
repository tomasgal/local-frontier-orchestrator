# G2 — NPU detection research (P32–P55)

**Checkpoint: 2026-11-28. Experimental; no production enablement.** The immutable v9.6.8 release and accepted L0–L4 contracts remain unchanged. The objective is a generic, non-personalized epistemic mediator: CES regulation and autonomous detection/advice are equally important; no diagnosis of people.

## Reference heterogeneous host

MINISFORUM MS-S1 MAX, AMD Ryzen AI Max+ 395, Radeon 8060S integrated GPU, AMD XDNA2 NPU, 128 GB unified memory, Windows 11 Pro / Windows PowerShell 5.1. GPU reference: Ollama 0.40.16, Qwen3.5 35B-A3B Q8, 16,384 context, 4096 generation ceiling in shaping pilots, thinking off. NPU: AMD NPU Compute Accelerator Device driver 32.0.20102.4480 (observed functional); [FastFlowLM](https://github.com/ROCm/FastFlowLM) native Windows runtime. Do not equate NPU use with dedicated VRAM, measured energy savings, or proven simultaneous CPU/NPU/GPU throughput. No energy or contention benchmark yet.

The NPU runtime was installed and exercised independently of LFO. No automatic startup, bootstrap change, mandatory NPU dependency, model download by LFO, or production detector integration. Local loopback API port 52625 in the tested configuration; check actual server port on other installations. Use separate terminals for server and experiment client. Stop only the relevant server before switching models.

```powershell
flm pull d3:nano
flm serve --decision d3:nano
```
```powershell
flm pull nemotron3.5-bolt-dflash:e4b
flm serve nemotron3.5-bolt-dflash:e4b
```

D3: POST /v1/systemone with state and named questions, each type choice with clear/defect/unknown criteria; returns choice and class scores. Generative model: POST /v1/chat/completions, temperature 0, reasoning_effort none, stream false, one-letter C/D/U or explicit JSON Schema. Send UTF-8 bytes and decode raw response bytes as UTF-8 in Windows PowerShell 5.1. Validate model identity, output contract and completion; never treat invalid/unknown as clear. Class scores are not calibrated probabilities of correctness. A request to disable reasoning is not proof of internal reasoning behavior.

## Exactly two active NPU model candidates

| Candidate | Intended experimental role | Status |
|---|---|---|
| `d3:nano` | Discriminative multi-question epistemic predicates, low latency, score-based escalation research | Primary candidate |
| `nemotron3.5-bolt-dflash:e4b` | Generative single-predicate adjudication or complex named structured vectors | Secondary candidate; not a routine provenance gate |

Other models screened (D3 Edge/Lite/Mini, LFM3 1.7B, Gemma 4 E2B, Qwen3.5 2B) are historical comparisons, not active candidates. The primary GPU answer model is separate from this NPU candidate set. No model is accepted for production.

## Evidence ledger

All counts below are working author-labelled synthetic/replay pilots, measured on the reference host. No independent blinded annotation, representative sampling or human efficacy evidence. Related/reused cases are not independent replications. Different model contracts and subsets limit comparisons; no causal claim about architecture.

- P32–34 Edge: revision contrast detectable, provenance weak; P33 6/12 target labels, F1 .40; output scores identical when questions evaluated together vs separately in tested cases. Stop Edge prompt tuning.
- P35–38 Lite: P33 9/12; P37 frozen E2/E4/E5/E6 thresholds 19/24, E5 failed; P38 six vs three questions identical on scored outputs, three questions ~225 ms vs ~406 ms, cross-sensitivity remains.
- P39 Nano choice 28/32 (16 TP, 12 TN, 4 FP), noul 28/32 (15 TP, 13 TN, 3 FP, 1 FN). P40 choice 30/32, all 16 positives detected; noul 28/32. P40 about 261 ms including both contracts. P41 manual context split 22/24 vs full 19/24, but split is oracle segmentation and adds latency. P42 hard router 7/12; reject hard skip. P43 three-state 18/24 vs four-state collapsed 17/24; retain three states. Unknown does not mean clear.
- P44 Nano vs Mini: common new 12 cases each 8/12; Nano ~226 ms vs Mini ~515 ms. No quality gain justifying larger D3.
- P45 Nemotron 10/12 vs Nano/Mini 8/12 on same new cases; 3/4 positives, 4/4 clear, 3/4 unknown; ~1.05 s. P46 one-axis P33 12/12, compact vector format valid only 2/24 (one-axis 12/12; two-axis 0/12).
- P47 explicit named JSON Schema on 8 P43 cases: 16/16 valid calls; pair 8/16 vs six-axis vector 14/16 on E2/E6 only; vector 6/6 defects, 6/8 clear, 2/2 unknown; ~4.67 s, 52 output tokens. Other four axes not independently annotated. P48 positional array 11/16, 4/6 defects, 8/8 valid, ~2.62 s; not accepted. Format and prompt are bundled factors.
- P49 direct provenance 9/12 vs extracted actor/modality/quote + CPU 7/12; ~1.05 vs 2.30 s. Exact quote does not validate semantic attribution. Same text with different runtime state produced same extraction and correct distinct verdicts in the three matched cases. Keep runtime authority; do not adopt this extractor.
- P50 Nemotron EN 5/8, SK 4/8; defects EN 2/4, SK 0/4. Both PRE positives missed in both languages. Only 4/8 translation pairs agree. No broad language competence inference.
- P51 LFM3 9/28, 21/28 valid, no valid clear predictions; P52 constrained diagnostic 2/8, all valid. Output UTF-8 ambiguity noted; no claim that input encoding caused failures.
- P53 Gemma 13/28, 28/28 valid, ~440 ms; P54 Qwen 2B 12/28, 28/28 valid, ~646 ms. Both miss all eight P50 positives.

### Common 28-case generative comparison (P45 + P50)

| Model | Correct | Defect (12) | Clear (8) | Unknown (8) | Valid | Mean latency (approx.) |
|---|---:|---:|---:|---:|---:|---:|
| Nemotron | 19/28 | 5 | 7 | 7 | 28/28 | 1.05 s |
| LFM3 | 9/28 | 1 | 0 | 8 | 21/28 | 1.63 s |
| Gemma | 13/28 | 3 | 8 | 2 | 28/28 | 0.44 s |
| Qwen 2B | 12/28 | 2 | 3 | 7 | 28/28 | 0.65 s |

P55 is prepared, **not run**: replay the same 28 cases with D3-Nano choice, separate PRE/POST predicates, C/D/U mapping, class scores and timing. P45 is a replay of the previously tested P44 subset; P50 is new to Nano. This compares complete mechanisms, not model architecture in isolation. P55 wording/criteria differ from the generative contract and earlier D3 prompts; record exactly. Do not tune on P55 and call it independent validation. Follow with a fresh fully annotated held-out corpus before any integration decision.

## Integration direction, not implemented

CPU owns deterministic invariants and runtime provenance; NPU evaluates bounded semantic predicates; GPU performs complex contextual analysis/escalation when justified. Preserve C/D/U/invalid separation, legitimate intent, original L0 and memory, explicit actor provenance. Evaluate score-based escalation offline first; no hard routing, automatic rewrite, or universal threshold from small pilots. Measure paired quality, critical failures, invalid/unknown rates, wall latency and tail variance; compare against existing frozen CES candidates and no detector. Separate detection, advice and intervention efficacy. A score-based cascade must be compared with always/never escalate and tested on held-out families. Concurrent device utilization and net latency remain unmeasured.

See [CES specification](../../docs/COUPLED_EPISTEMIC_SHAPING.md) and [UMA bootstrap](../../docs/UMA_BOOTSTRAP.md).
