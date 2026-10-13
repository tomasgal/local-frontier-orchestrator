# L4-R2 Frozen Baseline — Explicit Annotation Pilot

**Closure date:** 2026-10-13  
**Development branch:** `v9.6-l4-r2-annotation-pilot`  
**Immutable tag:** `v9.6-l4-r2-frozen`  
**R1 dependency:** `v9.6-l4-r1-frozen`  
**Status:** CLOSED for the explicit annotation-pilot scope.

## Decision

R2 is accepted as a bounded human/offline annotation workflow plus a small,
reproducible seed corpus and first deterministic analytics.

R2 does not add automatic detection, online turn hooks, prompt injection,
response intervention, psychological profiling, or mandatory model inference.

R1 remains frozen and unchanged.

## Accepted R2-A workflow

`src/LfoEpistemicAnnotationWorkflow.ps1` provides:

- strict JSON plan schema `lfo-epistemic-annotation-plan-v1`;
- explicit detector/version;
- one explicit L0 monthly file and epoch per plan;
- stable caller-supplied observation IDs and observed timestamps;
- local ordered keys and backward-only `related_key` links;
- full canonicalization through the frozen R1
  `New-LfoEpistemicObservation`;
- `-ValidateOnly` with no database write;
- sequential append through the frozen R1 API;
- idempotent exact-plan replay through stable IDs/payloads.

R2-A isolated acceptance passed 13 checks with real SurrealDB 3.3.0,
`ModelCalls=0` and `ProductionMemoryTouched=False`.

## Accepted R2-B engineering corpus

The public seed corpus is synthetic by design. It contains:

- 6 persisted synthetic L0 turns;
- 17 explicit observations;
- USER, LOCAL, FRONTIER and FINAL actor coverage;
- all five R1 interaction values;
- 10 observation types;
- 11 related-observation links;
- 17/17 exact provenance resolutions back to L0.

R2-B isolated acceptance passed 13 checks. The identical plan replay converged
to `ALREADY_EXISTS` for every record and the L0 JSONL remained byte-identical.

These counts are constructed test coverage, not behavioral prevalence.

## Accepted R2-C analytics

`src/LfoEpistemicPilotAnalytics.ps1` adds a bounded explicit read-only analytic
surface above R1. It paginates through the frozen R1 read API and derives:

- counts by actor;
- counts by stage;
- counts by observation type;
- counts by interaction;
- linked actor-to-related-actor interaction patterns.

The R2-C gate deliberately uses a page size of 5 against the 17-record corpus
to exercise keyset pagination. Exact expected actor/type/interaction/link
aggregates must match.

Analytics are corpus descriptions only. Frequency is not truth, importance,
diagnosis, detector accuracy, or evidence of intervention efficacy.

## Frozen R2 invariants

- R1 store/API contract remains unchanged.
- L0 remains authoritative source evidence.
- Observations remain annotations, not facts.
- Human/offline annotation is explicit.
- No automatic detector exists in R2.
- No ordinary prompt receives L4 history.
- No user-visible answer is changed by R2.
- No mandatory model call is added.
- Public synthetic fixtures contain no private conversation content.

## Known limitations

- The seed corpus is synthetic and small.
- R2 demonstrates representational and query mechanics, not ecological validity.
- Human annotation consistency/inter-rater agreement has not been measured.
- No detector precision/recall/calibration has been measured.
- No longitudinal recurrence claim is supported.
- No policy or Balancer intervention effect has been measured.
- The R2 analytic helper reads a bounded corpus through paginated R1 reads; it
  is not yet a general high-scale analytics engine.

## Reopen policy

Do not reopen frozen R2 merely to tune the synthetic corpus.

Reopen only for a demonstrated material workflow/analytic defect or a new
explicitly versioned requirement.

## Next milestone

Proceed to **L4-A1 Observatory analytics design** using R2 as the stable
evidence-producing layer.

The next question is no longer whether L4 can store linked annotations. It is
which longitudinal/interaction analytics are useful enough to justify a formal
Observatory surface. Automatic detector work should follow only after the
analytic targets are explicit enough to evaluate detector output against them.
