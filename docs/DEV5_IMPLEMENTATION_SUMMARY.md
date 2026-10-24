# DEV5 implementation summary and provenance

## Status

DEV5 is closed as part of the frozen L2 milestone at tag
[`v9.4-l2-frozen`](https://github.com/tomasgal/local-frontier-orchestrator/tree/v9.4-l2-frozen),
commit `34ba712566132fcebcb3f67b0c9b7ccdb1e7036a`.

This document records which DEV5 ideas were actually retained, what motivated
them, and which experiments were deliberately not promoted. It is a concise
interpretive index over the frozen evidence, not a replacement for
[`L2_FROZEN_BASELINE.md`](https://github.com/tomasgal/local-frontier-orchestrator/blob/v9.4-l2-frozen/docs/L2_FROZEN_BASELINE.md).

## External inspiration and attribution

The DEV5 optimization direction was materially informed by **Daniel Correa
Villa, _Pushing Four Raspberry Pis to the Memory Wall_**, DOI
[`10.5281/zenodo.20357376`](https://doi.org/10.5281/zenodo.20357376).

The transferable idea used by LFO is architectural rather than a claim of
hardware equivalence: on constrained systems, first remove unnecessary work and
data/context movement, then evaluate the complete loop including coordination
and observability overhead. This influenced the decision to prioritize reduced
prompt traffic, reduced generated output, elimination of work that is known to
be discarded, and end-to-end measurement before host-specific tuning.

LFO does **not** claim to reproduce the paper's Raspberry Pi setup, topology,
memory-wall measurements, energy results, multi-node scaling, or numerical
speedups. The accepted mechanisms below are LFO-specific adaptations in its
PowerShell/SQLite local-first architecture.

## What DEV5 retained

### A â€” compact read schema

For eligible LOCAL read-only turns backed by protected L2 retrieval, the model
no longer has to generate the full write-capable response schema. The accepted
compact contract requests only the fields needed for the read response
(`route` and `answer`).

The purpose is to remove output that the deterministic read-side guard would
discard anyway. All non-eligible paths retain the full write-capable contract.

Accepted switch in the frozen profile:

- `LocalGeneration.CompactReadSchemaEnabled = true`

### B â€” lean read policy

When the compact read schema is active on an eligible protected read, the model
also receives a reduced read policy without L2 write-extraction instructions
that cannot be used on that path.

This reduces input/context traffic while preserving the full extraction policy
for write-capable turns.

Accepted switch in the frozen profile:

- `LocalGeneration.LeanReadPolicyEnabled = true`

A and B are intentionally coupled by eligibility. DEV5 does not globally
replace the full schema or the full write policy.

### Supporting integrity work retained with DEV5

Several changes developed while validating DEV5 are retained because the
optimization is only acceptable if incorrect path selection remains cheap,
observable, and unable to silently corrupt structured memory:

- model-origin writes on protected read paths are suppressed;
- read and write contracts are separated;
- alias/scope authorization and guarded SQLite application are transactional;
- trace fields expose whether retrieval, compact mode, lean policy, guards and
  writes were actually active;
- a narrow current-user mixed-turn path can authorize one exact-source typed
  update without treating retrieved L2 facts or model output as user authority.

Accepted switch for that bounded mixed-origin path:

- `LocalGeneration.MixedUserEvidenceWriteEnabled = true`

This mixed path is deliberately narrow. It is evidence that provenance-aware
authorization can work inside the accepted boundary, not a general natural
language update parser.

## What DEV5 did not retain

The frozen L2 baseline deliberately excludes several explored candidates:

- **C / lower-trust L2 evidence message:** not adopted; no demonstrated security
  advantage justified the additional mechanism and token cost.
- **Grouped extraction/output format:** not adopted; live trials showed semantic
  omissions despite structural/offline success.
- **Shortened 2040-character write policy:** not adopted; the full
  2414-character extraction policy was restored.
- **Broad lexical special-casing to force optimizer eligibility:** not adopted;
  safe misses and visible fallbacks are preferred to brittle benchmark tuning.
- **Universal DEV5 speedup claim:** not supported. The accepted evidence is a
  bounded eligible-path mechanism result.

## Accepted evidence boundary

The frozen acceptance combines deterministic regression checks with bounded
LOCAL pilots.

For the final R5 eligible-read pilot, the same retrieved evidence was used in
four correctness-gated FULL/A+B trials. All answers were correct and L1/L2 were
unchanged. Observed input fell from 1756 to 1210 tokens and mean output from
173 to 24 tokens. Mean complete-turn time was 159.629 s for FULL and 24.791 s
for A+B.

Those timing observations include unequal cache/load conditions and are **not**
a statistically established or portable 84.47% speedup. The stronger causal
evidence is the reduced prompt/output traffic and the substantially lower
decode work on the A+B path. This was sufficient for selective engineering
acceptance, not for a general performance claim.

For exact R1-R5 results, limitations, source pins and hashes, see the
[frozen L2 baseline](https://github.com/tomasgal/local-frontier-orchestrator/blob/v9.4-l2-frozen/docs/L2_FROZEN_BASELINE.md).

## Provenance boundary

It is useful to distinguish three levels of provenance:

1. **Research motivation:** Correa Villa's work motivated the architecture-first
   focus on eliminating unnecessary work and traffic on constrained systems.
2. **LFO design decisions:** compact read output, lean read policy, provenance
   guards, transactional authorization and the exact accepted feature
   composition were derived and tested within LFO.
3. **LFO empirical evidence:** the R1-R5 results establish only the tested
   PowerShell/SQLite/Ollama scenarios documented in the frozen baseline.

The project therefore acknowledges the external research influence without
presenting LFO as a reproduction, implementation of the paper, or transfer of
its reported numerical results.

## Related records

- [Published DEV5 transferability technical note](https://doi.org/10.5281/zenodo.23318551): *Reducing Context and Generation Traffic in a Local-First LLM Orchestrator: A Transferability Case Study* (DOI 10.5281/zenodo.23318551)
- [Published runtime-priority technical note](https://zenodo.org/records/23610929): *Windows Process Priority and Local LLM Inference: A Counterbalanced Host-Runtime Study* (DOI 10.5281/zenodo.23610929). This follow-up studies host-runtime priority rather than DEV5 context/work reduction.

- [Frozen L2 contract and results](https://github.com/tomasgal/local-frontier-orchestrator/blob/v9.4-l2-frozen/docs/L2_FROZEN_BASELINE.md)
- [Frozen file manifest](https://github.com/tomasgal/local-frontier-orchestrator/blob/v9.4-l2-frozen/docs/L2_FROZEN_MANIFEST.json)
- [Historical DEV5 performance experiments](https://github.com/tomasgal/local-frontier-orchestrator/blob/v9.4-l2-frozen/docs/DEV5_PERFORMANCE_EXPERIMENTS.md)
- [Historical G2 DEV5 handoff](https://github.com/tomasgal/local-frontier-orchestrator/blob/v9.4-l2-frozen/docs/DEV5_G2_HANDOFF.md)
- [Project roadmap](ROADMAP.md)
