# L4-P1 Frozen Baseline - Rare-trigger Policy Capsule

**Closure date:** 2026-10-13  
**Development branch:** `v9.6-l4-p1-policy`  
**Immutable tag:** `v9.6-l4-p1-frozen`  
**Dependency:** `v9.6-l4-a2-frozen`  
**Status:** CLOSED for the bounded default-OFF policy-capsule scope.

## Decision

P1 is accepted as a deterministic policy recommendation layer over bounded
explicit A2 summaries. It remains default OFF and does not perform runtime
intervention.

The frozen engine emits `NO_ACTION` or one of four review recommendations:
`REVIEW_FRAMING`, `REQUEST_COUNTEREVIDENCE`,
`INCREASE_UNCERTAINTY_EXPLICITNESS`, or
`CHECK_REINFORCEMENT_PATTERN`.

## Deterministic acceptance

- 99 checks PASS;
- 10 policy cases;
- 6 active-trigger cases;
- 4 NO_ACTION cases;
- rules were SHA-256 locked before acceptance execution;
- default-OFF behavior, exact thresholds, composite predicates, rule priority,
  support bounding, canonical schema rejection and raw-field rejection passed;
- `ModelCalls=0`;
- `AutomaticR1Writes=0`;
- `ProductionMemoryTouched=False`.

## Private curated sanity

A separate read-only replay over the existing private curated A2 research store
also passed. The corpus matched the frozen A2 aggregate: 5 source turns,
10 observations, 5 linked FINAL responses (3 CORRECTED, 2 CHALLENGED), and
0 two-edge chains. The resulting policy decision was `NO_ACTION` and carried
no supporting observation IDs, which is consistent with the frozen rare-trigger
rules. Private source text, store identity, credential material and host paths
are not published.

## Interpretation boundary

P1 predicates are engineering review rules over stored annotation structure.
They do not establish behavioral prevalence, a stable user/model trait,
psychological diagnosis, detector accuracy, causal influence, or intervention
efficacy. P1 does not rewrite an answer, write R1, or create persistent user
state.

## Reopen policy

Do not retune P1 thresholds against this acceptance corpus. Reopen only for a
demonstrated material policy defect or a separately versioned policy scope with
new evidence.

## Next milestone

Proceed to **L4-P2 - bounded intervention experiment**. Any actual response
intervention requires a new explicit contract and evidence.