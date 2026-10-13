# L4-I1 Accepted Integration Evidence

Date: 2026-10-13

Status: **ACCEPTED INTEGRATION EVIDENCE**

L4-I1 is the first accepted end-to-end walkthrough of the bounded L4 research
stack using a real SurrealDB persistence boundary and a real local Ollama model.
It is an integration result, not a new detector benchmark, policy retuning
exercise, deployment authorization, or ecological-efficacy claim.

## Bound implementation state

The walkthrough was executed against canonical public `main`:

`51a7b2a01fdccd36718a7429b0c13d9e2a484204`

This includes the merged P2 integrity compatibility-v1 contract. Frozen
milestone tags were unchanged.

The reviewed Windows runner had SHA-256:

`a747a322415a7b1db28f76245d8768dd71be979ba7a462eacb11e203b8ef71cd`

The review bundle bound its run to the same canonical main commit and reported
no production-memory mutation.

## Accepted evidence

The reviewed run passed all declared integration gates:

- host/runtime boundary checks: **91/91 PASS**;
- deterministic pre-inference gate: **108/108 PASS**;
- complete integrated walkthrough: **128/128 PASS**;
- exactly **18** predeclared explicit synthetic R1 annotations were written;
- exactly **5** planned local-model calls were completed;
- all five P1 decisions were exercised:
  `NO_ACTION`, `REVIEW_FRAMING`, `REQUEST_COUNTEREVIDENCE`,
  `INCREASE_UNCERTAINTY_EXPLICITNESS`, and
  `CHECK_REINFORCEMENT_PATTERN`;
- SurrealDB participated in the walkthrough and acknowledged data survived an
  owned-process restart/reconnect check;
- reverse drill-back was proven from active intervention through P1
  rule/reason, bounded A1/A2 support, R1 records and exact L0 provenance;
- `NO_ACTION` preserved complete request identity;
- unplanned R1 write attempts: **0**;
- detector calls: **0**;
- no persistent profile/trait schema was created;
- no automatic answer rewrite was introduced;
- runtime intervention remained **OFF by default**;
- existing external service processes were not stopped.

The integrated path demonstrated by I1 is:

```text
L0 provenance
  -> R1 SurrealDB observations
  -> A1/A2 bounded analytics
  -> P1 Policy Capsule
  -> P2 intervention mapping
  -> local Ollama model
  -> auditable outcome and reverse provenance
```

## Model outcomes

The five model outcomes are descriptive integration observations rather than an
efficacy estimate. Four matched the predeclared descriptive target. The
`REQUEST_COUNTEREVIDENCE` case returned `SUPPORT_ONLY` rather than the target
`BOTH_SIDES`.

This does **not** invalidate the I1 integration gate: the deterministic evidence,
policy, intervention mapping and resulting model request were correct and fully
auditable before inference. The miss is retained as evidence that a bounded
intervention does not guarantee a particular stochastic model response.

P2's separately frozen paired experiment remains the efficacy evidence for its
bounded scope; I1 does not replace or extend that claim.

## Scope and limitations

I1 establishes engineering integration over explicit synthetic annotations on
one reference Windows host. It does not establish:

- human-label reliability;
- ecological or longitudinal efficacy;
- universal intervention efficacy;
- cross-host replication;
- deployment authorization;
- a system-wide filesystem write audit.

The five unpaired model calls are intentionally not treated as an efficacy
sample. Runtime intervention remains default-OFF.

## Engineering decision

I1 closes the previously missing end-to-end integration evidence gap. No
additional research experiment is required before constructing the first
complete L0-L4 Windows build.

The next engineering gate is a **clean bootstrap/build acceptance**:

1. bootstrap prerequisites and runtime services on a clean Windows environment;
2. obtain the canonical LFO source and generic launch/configuration scripts;
3. start visible Ollama and SurrealDB service consoles;
4. verify the normal L0-L3 baseline with L4 intervention OFF;
5. verify explicit L4 activation through the integrated path without unintended
   memory/store mutation;
6. perform the acceptance from the installed/bootstrap environment rather than
   from a development checkout.

Cross-host replication remains valuable follow-up evidence but is not a
prerequisite for this implementation-cycle build gate.
