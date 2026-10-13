# L4-D1 Frozen Baseline — Bounded Detector Experiment

**Closure date:** 2026-10-13
**Development branch:** `v9.6-l4-d1-detector`
**Immutable tag:** `v9.6-l4-d1-frozen`
**Dependency:** `v9.6-l4-a1-frozen`
**Status:** CLOSED as an offline detector experiment.

## Decision
D1 compared the deterministic zero-model-call baseline with the Core LOCAL model `qwen3.5-4b-core-cpu5k:latest` using protocol `schema`.
Decision: **DOES_NOT_YET_BEAT_RELIABLE_BASELINE**.

The earlier local closure candidate that treated protocol/schema failures as empty predictions was discarded before publication and is not part of the frozen evidence.

## Accepted evidence
- deterministic baseline: 15 checks PASS;
- 30 scored public text-local cases + 4 relational abstention cases;
- baseline micro F1 0.8421; exact-set accuracy 0.8000;
- two complete valid local-model public runs;
- public average micro F1: 0.8000;
- public average exact-set accuracy: 0.7333;
- prediction stability: 1.0000;
- private real-conversation sanity cases: 10;
- private model micro F1: 0.2500;
- valid D1-C model calls: 9;
- accepted transport/schema failures: **0**.

## Frozen boundary
Detector output remains candidate annotation evidence, not truth. No automatic R1 write, runtime hook, prompt-history injection, response rewrite, Balancer intervention, or persistent user profile is introduced.

## Reopen policy
Do not tune against the same cases. A new detector version requires a new versioned experiment and fresh held-out evidence.

## Next milestone
Proceed to **L4-A2 recurrence/interaction analytics**.