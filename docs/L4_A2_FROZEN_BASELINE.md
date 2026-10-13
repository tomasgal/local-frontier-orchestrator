# L4-A2 Frozen Baseline — Recurrence and Interaction Analytics

**Closure date:** 2026-10-13  
**Development branch:** `v9.6-l4-a2-interaction`  
**Immutable tag:** `v9.6-l4-a2-frozen`  
**Dependency:** `v9.6-l4-d1-frozen`  
**Status:** CLOSED for the bounded recurrence/interaction analytics scope.

## Decision

A2 is accepted as a deterministic read-only extension of the frozen A1
Observatory.

It adds recurrence-density normalization, explicit two-edge chain motifs,
linked-response balance, adjacent-window signature presence, and bounded
provenance support. It does not create detector labels, user profiles, causal
edges, prompt injections or interventions.

## Deterministic evidence

The public synthetic fixture contains 8 turns and 25 explicit human/manual
annotations. It deliberately includes repeated motifs and one cross-window
related chain.

Acceptance demonstrates:

- exact recurrence-density counts and turn normalization;
- 9 explicit two-edge chain occurrences in the full window;
- repeated `USER→LOCAL→FINAL` motifs;
- response-balance counts/fractions by child actor;
- a selected 5–8 window with one excluded boundary link and one excluded
  boundary chain;
- exact adjacent-window signature status totals `12 PRESENT_BOTH / 1 ONLY_A /
  4 ONLY_B`;
- bounded provenance drill-back;
- unchanged L0;
- `ModelCalls=0` and `ProductionMemoryTouched=False`.

## Private curated non-synthetic sanity evidence

A2 was also run read-only over the existing private A1 curated research store
containing real L4-development excerpts.

Aggregate result:

- 5 real source turns;
- 10 human/manual observations;
- recurrence-density rows were produced for repeated USER/FINAL structures;
- linked FINAL response balance: 5 responses, including 3 `CORRECTED` and
  2 `CHALLENGED`;
- no two-edge chain existed in this small real corpus, and A2 returned zero
  rather than inventing one;
- adjacent-window presence comparison succeeded;
- provenance drill-back succeeded;
- no model call and no persistent-store mutation occurred.

The private source text and store identity are not published.

## Interpretation boundary

A2 establishes that the analytic machinery can describe recurrence and linked
interaction structure. It does **not** establish:

- behavioral prevalence;
- a stable user or model trait;
- causal influence between actors;
- detector accuracy;
- longitudinal improvement/deterioration;
- intervention efficacy.

D1 predictions are not promoted into R1 and are not mixed silently with the
human/manual evidence used here.

## Reopen policy

Do not reopen A2 for ordinary threshold or presentation tuning. Reopen only for
a demonstrated material analytic defect or a newly versioned analytic
requirement with new evidence.

## Next milestone

Proceed to **L4-P1 — rare-trigger Policy Capsule**.

P1 may consume explicit bounded Observatory summaries only under a separately
defined policy contract. Detection, analytics and intervention remain separate.
