# L4-R2 synthetic seed corpus — engineering evidence

Status: **R2-B engineering corpus candidate**.

This fixture is deliberately synthetic and public. It is not presented as a
sample of user behavior and must not be used for prevalence, detector-accuracy
or psychological claims.

The fixture exists to test whether the frozen R1 store plus the R2-A explicit
annotation workflow can represent a small but interaction-diverse corpus without
changing L0-L3 or requiring a model call.

## Fixture

`tests/fixtures/l4-r2-seed/` contains:

- six synthetic persisted L0 turns with USER/LOCAL/FRONTIER/FINAL stage sources;
- one explicit `human.manual` annotation plan;
- 17 observations;
- all four actors;
- all five R1 interaction values;
- multiple observation classes including framing, presupposition, asymmetric
  evidence request, sycophantic reinforcement, overconfidence, uncertainty
  suppression, counterevidence introduced/ignored, bias challenged and a
  general epistemic-risk signal;
- 11 explicit related-observation links.

The scenarios intentionally include both reinforcement and correction paths.

## Acceptance gate

`tests/Test-LfoEpistemicSeedCorpus.ps1`:

1. copies the synthetic L0 fixture to a new TEMP directory;
2. registers a fresh R1 L0 store identity;
3. starts a new isolated real SurrealDB 3.3.0 instance on a random loopback port;
4. validates the annotation plan without writing;
5. writes the full corpus through `Invoke-LfoEpistemicAnnotationPlan`;
6. reads all observations back;
7. resolves every stored observation back to exact L0 provenance;
8. checks actor/type/interaction diversity and related links;
9. retries the same plan and requires `ALREADY_EXISTS` for every observation;
10. verifies the L0 JSONL bytes are unchanged;
11. writes an aggregate evidence report under TEMP.

The aggregate report is engineering evidence only. Counts in this synthetic
fixture are constructed coverage, not observed prevalence.

## Boundary before R2-C

Passing this gate means the storage and annotation workflow can represent a
small linked corpus reproducibly. It does **not** yet establish that the
taxonomy is sufficient for natural conversations.

R2-C may run minimal deterministic analytics over this reproducible corpus to
exercise query shapes, but any design claim about real Human-AI interaction
must later be checked against explicitly curated non-synthetic observations.
No automatic detector or Balancer is introduced here.
