# L4-R2 — Explicit Annotation Pilot

Status: **R2-A implementation candidate**.

R2 starts only after the frozen L4-R1 store/API contract. It does not reopen R1.
The purpose of R2 is to create the first bounded, auditable annotation corpus
and learn which analytics are useful before adding automatic detection or policy.

## Three macro-steps

### R2-A — explicit annotation workflow

`src/LfoEpistemicAnnotationWorkflow.ps1` adds a human/offline plan workflow over
the frozen R1 API.

An annotation plan is JSON with:

- schema `lfo-epistemic-annotation-plan-v1`;
- one detector identity/version for the plan, initially `human.manual`;
- one explicit L0 monthly file and epoch;
- 1-200 ordered observations;
- a stable random 32-hex R1 observation ID and UTC `observed_at` per item;
- a local plan `key`;
- optional `related_key` pointing only to an earlier item in the same plan.

The workflow first canonicalizes every item through
`New-LfoEpistemicObservation`, so L0 provenance, actor/stage/producer, exact
excerpt and the frozen taxonomy remain R1-controlled. Only after the whole plan
validates does `Invoke-LfoEpistemicAnnotationPlan` write sequentially through
`Add-LfoEpistemicObservation`.

A write failure can therefore leave an already-created prefix. There is no
rollback or delete because R1 is append-only. Re-running the identical plan is
the recovery mechanism: stable IDs/payloads converge to `ALREADY_EXISTS`.
There is no automatic retry.

`-ValidateOnly` performs all source/taxonomy/link validation and no database
write.

R2-A does not:

- detect or classify turns automatically;
- call any model;
- hook the normal QwenChat path;
- modify L0/L1/L2/L3;
- inject L4 history into prompts;
- rewrite or intervene in answers.

### R2-B — curated seed corpus

Use the R2-A workflow against a small, interaction-diverse set of persisted L0
turns. Real/private L0 text, annotation plans and bounded excerpts are local
research data by default and must not be committed to the public repository.
Public evidence should use synthetic fixtures or aggregate/non-identifying
results unless a source has been explicitly approved for publication.

Cover useful USER/LOCAL/FRONTIER/FINAL interactions such as framing,
presupposition, reinforcement, challenge/correction and counterevidence
handling. Corpus size is evidence-driven rather than quota-driven.

### R2-C — first analytics and closure

Run minimal deterministic/SurrealQL analytics over the seed corpus: counts by
actor/type, interaction distributions and a small number of linked-stage
patterns. Evaluate the practical adequacy of taxonomy, links and query surfaces.

Frequency is not truth, importance or a psychological diagnosis. R2 alone does
not establish detector quality, longitudinal behavioral claims or intervention
effects.

## Plan example

```json
{
  "schema": "lfo-epistemic-annotation-plan-v1",
  "detector": "human.manual",
  "detector_version": "r2-v1",
  "source": {
    "file": "conversation-2026-10.jsonl",
    "epoch": 1
  },
  "observations": [
    {
      "key": "user-frame",
      "id": "11111111111111111111111111111111",
      "observed_at": "2026-10-13T08:00:00Z",
      "turn_id": 1,
      "stage_id": "s1",
      "observation_type": "FRAMING",
      "confidence": null,
      "excerpt": "exact bounded source substring",
      "interaction": "INTRODUCED",
      "related_key": ""
    }
  ]
}
```

The example ID is illustrative. Actual plans use generated random 32-hex IDs and
retain them unchanged for retries.

## R2-A acceptance

The isolated R2-A gate uses a synthetic L0 turn and real SurrealDB 3.3.0. It
must prove:

- dry-run validates without writing;
- one ordered USER→LOCAL→FRONTIER→FINAL plan creates correctly;
- exact retry is idempotent;
- local `related_key` becomes the correct R1 related observation ID;
- L0 remains byte-identical;
- malformed schema, duplicate keys, forward references and invented excerpts
  fail closed;
- ModelCalls=0 and ProductionMemoryTouched=False.

Passing R2-A validates the annotation workflow, not the quality of human
annotations or any automatic detector.
