# L4-A2 Recurrence and Interaction Analytics

**Dependency:** `v9.6-l4-d1-frozen`

A2 extends the frozen A1 Observatory without changing R1/R2 or introducing a
detector/runtime hook.

## Analytic surface

A2 answers five bounded questions:

- **Q6 recurrence density:** repeated `actor|type` and linked-response
  signatures, normalized by explicit source-turn span and by annotated turns.
- **Q7 two-edge chain motifs:** explicit `related_observation_id` chains of
  three stored observations, reported as actor/interaction and type motifs.
- **Q8 response balance:** counts/fractions of `REINFORCED`, `CHALLENGED`,
  `CORRECTED`, and `IGNORED` linked responses by child actor.
- **Q9 adjacent-window signature presence:** `PRESENT_BOTH`, `ONLY_A`, or
  `ONLY_B` for two exactly adjacent turn windows.
- **Q10 provenance backing:** every aggregate exposes bounded observation IDs
  compatible with the frozen A1 provenance drill-back.

## Semantic boundary

These outputs describe **stored annotation structure**, not behavioral
prevalence or a latent psychological state. In particular:

- recurrence density is annotation density inside an explicit bounded window;
- direct links are the only edges analyzed;
- two-edge chains do not create causal edges that are not stored;
- adjacent-window presence is not called improvement, deterioration,
  persistence of a trait, emergence of a trait, or cessation of a trait;
- cross-window parent/grandparent chains are excluded and counted explicitly.

A2 is read-only and requires no model calls.
