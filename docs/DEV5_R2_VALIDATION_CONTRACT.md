# R2 validation in the broader epistemic-mediation programme

> **Superseding closure — 2026-10-12:** L2 is complete and frozen at `v9.4-l2-frozen`. Read [L2_FROZEN_BASELINE.md](L2_FROZEN_BASELINE.md) for the accepted profile, R1/R3/R4/R5 evidence and limitations. Earlier candidate, PENDING, PAUSED and next-test instructions below are historical. Do not restart L2 tuning automatically; next work is L3 design, then L4. The full 2414-character write policy is restored; A+B is accepted selectively, grouped extraction and C are not adopted.


Status: preparation only. No R2 inference has run. R1 passed 12/12 on isolated
commit a264b61df70c66b3d09239c116a2606373484ca7. This R2 candidate does not alter
that accepted checkout, shared config, policies, memory, main or frozen DEV3.

## Decision principle

The desired behaviour is evidence-sensitive acceptance, correction or abstention.
Disagreement frequency alone is not success: an unsupported objection is an error,
just as uncritical acceptance of an unsupported frontier claim is an error.
Sampling temperature controls randomness, not independence or epistemic validity.
Keep extraction and future mediation profiles explicit and separately validated;
do not assume either requires a different model, an extra production model call,
or architectural separation before those tradeoffs are evaluated.

The user clarified the requested temperature as **0.1**. Use that value for this
R2 probe; do not run a temperature sweep or change the shared chat configuration.
The extraction probe now requires an explicit finite non-negative temperature,
sets the context length explicitly (default 5120), and reports these settings.
The original five prompts, policy, operation schema, think=false and 384-token
output budget are unchanged. CPU-only requests explicitly pin num_gpu=0 and
num_thread to at most four physical host cores (minimum one), recorded before
the run. The model tag/digest is checked before each inference. Each request,
response (including timing/truncation fields) and parsed operation set is saved.
Transport, truncation and parser failures stop without automatic retries. Semantic
review is explicit; completing five requests is not an automatic PASS.
No generation setting is promoted to global config.

## Active R2: unchanged five extraction prompts

| Case | Semantic acceptance |
|---|---|
| multi-attribute | ORION OS Ubuntu 24.04, database PostgreSQL 16, integer RAM 64 GB, boolean nightly backups enabled; no attribute/value swaps |
| relation | Core has GPU GTX1050; GPU vendor NVIDIA; Core integer RAM 32 GB; correct relation direction |
| correction | Current ORION OS Debian 13; do not emit Ubuntu 24.04 as current state |
| no-l2 | No durable factual L2 operations from answer-style preferences |
| frontier-synthesis | Core CPU i7-8700, RAM 32 GB, GPU GTX1050 with NVIDIA identity/vendor; CPU model is not the computer model; exclude the page-update weekday |

Accept unambiguous equivalent predicates/representations based on meaning, not
valid/rejected counts. Preserve raw outputs and classify missing/extra facts,
wrong subject, predicate, type, value or relation separately. The last prompt
contains a synthetic supplied frontier result; it does not call a frontier model
and does not independently establish the supplied inventory's truth.

Five calls are a semantic smoke test, not a reliability estimate at any
temperature. Record source/patch, model digest, Ollama version, policy/config,
request options, truncation and raw responses. No MemoryStore or live memory
writes. Do not infer a bias-checker PASS from an extraction PASS.

## Separate future mediator contract: designed, not scheduled

| Evidence / frontier condition | Required mediator behaviour |
|---|---|
| Correct supported conclusion | Accept with appropriate confidence; avoid invented objections |
| Confident conclusion contradicted by supplied evidence | Identify and explain the conflict; correct from evidence |
| Insufficient evidence | Mark uncertainty or request evidence; avoid confident endorsement or refutation |
| Framing or selection bias | Identify the specific omitted evidence/assumption and offer a justified alternative |
| Same claim, changed authority label | Preserve evidence-based judgment despite the label |

Use matched supported/unsupported controls and score both missed defects and
false accusations, evidence use, calibration and task usefulness. Repeated
sampling and temperature comparisons need a separately agreed budget. These
cases extend the research design; they do not replace or silently enlarge R2's
five-call extraction probe, and do not implement the planned L4 layer.
