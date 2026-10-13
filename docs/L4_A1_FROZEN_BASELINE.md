# L4-A1 Frozen Baseline — Observatory Analytics

**Closure date:** 2026-10-13  
**Development branch:** `v9.6-l4-a1-observatory`  
**Immutable tag:** `v9.6-l4-a1-frozen`  
**Dependency:** `v9.6-l4-r2-frozen`  
**Status:** CLOSED for the explicit read-only Observatory scope.

## Decision

A1 is accepted as the smallest useful explicit Observatory layer above frozen
R1/R2.

It formalizes and implements five bounded analytic questions:

1. explicit source-turn window summary;
2. semantic antecedent → response linked transitions;
3. recurrence across at least two distinct source turns;
4. descriptive comparison of two ordered non-overlapping windows;
5. bounded provenance drill-back to L0 locators/hashes.

A1 does not add automatic annotation, detector calls, prompt injection,
response intervention, persistent psychological profiling or mandatory model
inference.

## A1-A contract evidence

The machine-readable/human-readable analytic contract passed 20 deterministic
checks with `ModelCalls=0` and `ProductionMemoryTouched=False`.

Conversation chronology is `source.epoch + source.turn_id` with numeric
`stage_id` as a within-turn tie-break. `observed_at` remains annotation
metadata and is not used as conversation chronology.

## A1-B implementation evidence

The Q1-Q5 read-only implementation passed 24 deterministic checks on a
synthetic fixture using real SurrealDB 3.3.0.

The fixture explicitly exercised:

- keyset pagination;
- annotation timestamps intentionally out of conversation order;
- semantic parent/related → child/current link direction;
- a cross-window link excluded from one window and included in another;
- recurrence across distinct turns;
- descriptive window comparison;
- bounded provenance references without raw source text.

`ModelCalls=0`; `ProductionMemoryTouched=False`.

## A1-C curated non-synthetic evidence

A separate private research L0 store was built from exact excerpts of five real
development interactions from the L4 workstream. The source text and annotation
plan remain local and are not committed to the public repository.

Aggregate result:

- 5 real interaction excerpts;
- 10 explicit human/manual observations;
- exact provenance resolution for all stored observations;
- repeated USER→FINAL linked-response structure across distinct turns;
- recurrence visible for generic epistemic-risk annotations;
- explicit early-vs-late window comparison;
- bounded provenance drill-back successful.

The persistent development SurrealDB was used for this curated corpus so the
research observations survive process restarts. The store is isolated by its
own L0 `store_id` and epoch.

The curated pilot demonstrates practical usefulness of the **analytic surface**,
not correctness of the annotation taxonomy. It does not establish behavioral
prevalence, user traits, detector quality, longitudinal causation or
intervention efficacy.

## Usefulness assessment

- **Q1 Window summary — ACCEPTED.** Gives a compact bounded description of the
  selected annotation window without reading raw history into a prompt.
- **Q2 Linked transitions — ACCEPTED.** Direct R1 links support auditable
  antecedent→response interaction analysis without inferring unlinked causes.
- **Q3 Recurrence — ACCEPTED WITH BOUNDARY.** Useful only as repeated stored
  annotation structure across distinct turns; never a persistent trait.
- **Q4 Window comparison — ACCEPTED WITH BOUNDARY.** Useful as descriptive
  B-minus-A differences only; no trend, improvement or causal interpretation.
- **Q5 Provenance drill-back — ACCEPTED / REQUIRED.** Aggregate claims remain
  auditable without exposing source text by default.

## Frozen invariants

- R1 and R2 remain unchanged.
- L0 remains authoritative source evidence.
- Observations remain annotations, not facts.
- A1 reads exactly one store and epoch at a time.
- Analytic windows are explicit and turn-bounded.
- Recurrence does not create a user profile.
- Raw source text is not returned by aggregate analytics.
- No automatic detector exists in A1.
- No ordinary prompt receives Observatory history.
- No user-visible answer is automatically changed by A1.
- No mandatory model call is added.

## Known limitations

- The curated non-synthetic pilot is intentionally small.
- It uses exact excerpts in a separate research L0 store, not a production
  transcript migration.
- Annotation consistency/inter-rater agreement is unmeasured.
- The current analytics surface is bounded and in-process; it is not a general
  OLAP/high-scale Observatory backend.
- No detector precision/recall/calibration is known.
- No policy/Balancer intervention effect is known.

## Reopen policy

Do not reopen A1 for ordinary tuning.

Reopen only for a demonstrated material analytic defect or a new explicitly
versioned Observatory requirement.

## Next milestone

Proceed to **L4-D1 — bounded detector experiment**.

A1 has now made the analytic targets explicit enough that a detector can be
evaluated against stored human/manual annotations without coupling detection to
intervention. D1 must remain offline/bounded first; no automatic Balancer or
ordinary prompt injection is implied.
