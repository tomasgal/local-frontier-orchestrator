# L4-A1-B Observatory Implementation

**Status:** A1-B implementation candidate  
**Dependency:** `v9.6-l4-r2-frozen`  
**Contract:** `docs/L4_A1_OBSERVATORY_CONTRACT.md`

A1-B implements all five questions from the accepted A1-A contract as an
explicit read-only PowerShell surface in `src/LfoEpistemicObservatory.ps1`.

## Implemented questions

- **Q1 Window summary:** bounded counts inside one store/epoch and inclusive
  source-turn window.
- **Q2 Linked response transitions:** direct R1 links interpreted in semantic
  antecedent (`related`) → response (`current`) direction, returned as separate
  actor-transition, type-transition and child-interaction aggregates. A link counts only
  when parent and child are both inside the window; otherwise it increments
  `ExcludedBoundaryLinks`.
- **Q3 Recurrence:** repeated `actor|type` and
  `parent_actor->child_actor|interaction` signatures across at least two
  distinct child/source turns.
- **Q4 Window comparison:** descriptive B-minus-A deltas for two ordered,
  non-overlapping windows in the same store/epoch.
- **Q5 Provenance drill-back:** at most 50 bounded references containing only
  observation ID and L0 locator/hash fields. Raw source content is not expanded.

## Chronology

All windowing, sorting and recurrence use `source.epoch`, `source.turn_id` and
the numeric `stage_id` suffix. `observed_at` is ignored for conversation
chronology.

The deterministic fixture deliberately assigns annotation timestamps out of
conversation order, so the acceptance gate fails if implementation starts
using `observed_at` as the timeline.

## Boundary fixture

The A1 fixture has six synthetic L0 turns and twelve annotations. One annotation
on turn 6 explicitly links back to a turn-4 annotation.

Therefore:

- in window 4-6 the link is in-scope;
- in window 5-6 the child is in-scope but the parent is outside, so it is
  excluded from transition aggregates and reported as one boundary link.

This tests window semantics without changing frozen R1/R2.

## Read-only boundary

A1-B only calls the frozen R1 read functions after fixture setup. It does not
write observations, alter L0-L3, call a model, inject L4 into prompts or affect
user-visible answers.

The fixture setup itself uses frozen R2 annotation workflow against a new TEMP
L0/SurrealDB instance. Test observations never enter the persistent development
store.

## Interpretation

A1-B outputs are descriptions of stored annotations in explicit windows.
Counts, recurrence and deltas are not truth, prevalence, diagnosis, detector
quality, trend, causation, improvement/deterioration or intervention efficacy.

A1-C must still determine whether this surface is practically useful on a small,
explicitly curated non-synthetic corpus before A1 is frozen.
