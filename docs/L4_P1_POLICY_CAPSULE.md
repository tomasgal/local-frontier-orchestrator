# L4-P1 Policy Capsule

P1 is a small deterministic, default-OFF policy layer above the frozen A2
Observatory. It consumes only an explicit bounded A2 summary and emits either
NO_ACTION or one review recommendation.

## Boundary

P1 does not call a model or detector, read raw continuous history, write R1,
rewrite an answer, inject policy into an ordinary prompt, or create persistent
user state. It is an offline recommendation surface only.

Rules are external, versioned and hash-locked before acceptance execution.
The engine evaluates rules deterministically by ascending priority and returns
the first match. Every active capsule includes the rule ID/version, explicit
store/epoch/window, matched aggregate descriptors, bounded support IDs and a
reason code.

## Frozen rule set

- P1-R001 -> REQUEST_COUNTEREVIDENCE: repeated asymmetric evidence requests
  together with repeated FINAL counterevidence-ignored annotations.
- P1-R002 -> INCREASE_UNCERTAINTY_EXPLICITNESS: repeated LOCAL
  uncertainty-suppression annotations.
- P1-R003 -> CHECK_REINFORCEMENT_PATTERN: repeated LOCAL sycophantic
  reinforcement plus repeated USER->LOCAL REINFORCED links.
- P1-R004 -> REVIEW_FRAMING: repeated USER framing annotations.

The thresholds are engineering policy predicates over stored annotation
structure. They are not estimates of behavioral prevalence, psychological
traits, detector accuracy or intervention efficacy.

## Deployment

P1 remains default OFF. Runtime intervention is explicitly deferred to L4-P2.