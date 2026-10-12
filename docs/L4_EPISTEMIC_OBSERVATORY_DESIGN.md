# L4 design — Epistemic Observatory & Balancer

Status: **design/scoping accepted; implementation not started**

Date: 2026-10-12

L4 is the next active LFO milestone after the frozen L2 and L3 contracts. It must
build above those layers without reopening their accepted semantics.

## Purpose

L4 is an **epistemic event, analytics and rare-event policy layer**. It records
epistemically relevant events in human–AI interaction, supports longitudinal and
offline analysis, and may provide a small bounded policy signal to the online
orchestrator when an explicit or otherwise rare trigger justifies reading L4.

Bias is an important subclass of L4 observations, but it does **not** define the
layer. Strong framing, presupposition or asymmetric evidence requests are not
automatically biases.

A useful summary is:

> **OBSERVE → ANALYZE → optionally INTERVENE**

The default online mode is **write-mostly, read-rarely**.

## Layer boundary

```text
L0  authoritative raw conversation/evidence
L1  semantic working memory
L2  current factual state
L3  relevance / selective retrieval metadata
L4  epistemic observations, analytics and rare-event policy
```

L4 observations never become factual evidence merely because they exist. L4 may
change how evidence is sought or how cautiously an answer is framed; it must not
change the truth value of propositions.

## Goals and non-goals

| Goals | Non-goals |
| --- | --- |
| Record epistemically relevant events in USER, LOCAL, FRONTIER and FINAL stages. | Do not build a psychological profile or persistent diagnosis of the user. |
| Represent events such as framing, presupposition, bias candidates, overconfidence, sycophantic reinforcement and counterevidence handling. | Do not classify every strong or leading question as a bias. |
| Track interaction dynamics: introduced, reinforced, ignored, challenged or corrected. | Do not use L4 observations as factual evidence about the external world. |
| Build a longitudinal dataset suitable for offline analysis and research tools. | Do not inject L4 history into every prompt. |
| Support explicit analytic questions about epistemic interaction history. | Do not require a second LLM critic/rewrite call on every turn. |
| On rare triggers, produce a bounded Epistemic Policy Signal/Capsule. | Do not reopen or merge L4 semantics into frozen L2/L3. |
| Preserve detector provenance, confidence and later re-analysis/reclassification. | Do not add vector, graph or agentic complexity before measured need. |
| Keep the normal online path low-overhead and avoid a mandatory extra model call. | Do not optimize L4 primarily to imitate generic agentic-memory SOTA. |

## Core record: EpistemicObservation

The first-class L4 object is `EpistemicObservation`, not `BiasObservation`.

Candidate fields:

```text
id
timestamp
turn_id / source reference
actor: USER | LOCAL | FRONTIER | FINAL
stage: INPUT | LOCAL_RESPONSE | FRONTIER_RESPONSE | FINAL_RESPONSE
observation_type
confidence
detector
detector_version
status
optional bounded evidence excerpt
optional links to related observations
```

Initial observation types may include, without treating the list as final:

- `FRAMING`
- `PRESUPPOSITION`
- `ASYMMETRIC_EVIDENCE_REQUEST`
- `BIAS_CANDIDATE`
- `OVERCONFIDENCE`
- `UNCERTAINTY_SUPPRESSION`
- `SYCOPHANTIC_REINFORCEMENT`
- `COUNTEREVIDENCE_IGNORED`
- `COUNTEREVIDENCE_INTRODUCED`
- `BIAS_REINFORCED`
- `BIAS_CHALLENGED`
- a neutral/general `EPISTEMIC_RISK_SIGNAL` where a stronger label is not justified.

Observation is not diagnosis. Repeated observations may support a derived
longitudinal pattern, but not an unqualified statement such as
`user.confirmation_bias = true`.

## Interaction model

L4 should be able to represent relationships such as:

```text
USER event
   ↓
LOCAL reinforces / ignores / challenges
   ↓
FRONTIER or FINAL may correct / preserve / amplify
   ↓
optional intervention and outcome
```

This interaction dynamic is a central research object. A user-side event and a
model-side response event are distinct records that may be linked.

## Online lifecycle

```text
USER INPUT
   ↓
cheap L4 preflight observation path
   ↓
possible event?
   ├─ no  → normal LFO path
   └─ yes → write observation
                 ↓
              read trigger?
              ├─ no  → normal LFO path
              └─ yes → query relevant L4 analytics
                            ↓
                     bounded policy capsule
                            ↓
                         L2/L3
                            ↓
                          MODEL
                            ↓
                   optional post-observation
```

Detection and intervention are separate decisions. Most observations should be
logged without changing the current response.

## Rare read triggers

L4 history is **not continuously injected**. A read should occur only for a
defined trigger, initially:

1. **Explicit analytic request** — the user asks about prior epistemic behaviour,
   e.g. how often the model reinforced a premise.
2. **High-confidence current epistemic event** — the current event crosses a
   conservative policy threshold.
3. **Relevant recurrence** — a current event matches a repeated recent pattern
   strongly enough to justify a bounded policy check.
4. **Severe model-side event** — a model response exhibits a sufficiently strong
   epistemic risk; later versions may support a bounded repair path.
5. **Epistemic retrieval need** — L4 requests broader or counterevidence-oriented
   retrieval rather than deciding the answer itself.

The normal path remains observation/write only.

## Read modes

### ANALYTIC_READ

Used when the user explicitly asks about epistemic interaction history. L4 may
return observations, counts, patterns and links to source turns.

### POLICY_SIGNAL

Used implicitly after a rare trigger. The model should receive only a small,
derived **Epistemic Policy Capsule**, not raw L4 history, for example:

```text
current:
  confirmation-seeking risk: elevated

recent pattern:
  recurrence: moderate

policy:
  test the premise
  include materially relevant counterevidence
  distinguish evidence from interpretation
```

### INTERVENE

Reserved for later work. A detected event does not automatically imply an
intervention or response rewrite.

## Offline analysis

The observation store is intentionally useful outside the online LFO loop.
Offline analysis may use:

- deterministic/statistical analysis;
- another local model;
- a frontier evaluator;
- external research tools;
- human review.

Offline analysis may confirm, reject or reclassify an observation while
preserving the original detector, version, confidence and provenance.

## Technology decision: SurrealDB

L4 will use **SurrealDB** as its canonical data service rather than a second
SQLite database or a file-based JSONL/Parquet pipeline. The intended initial
layout is:

```text
namespace: lfo
database: epistemic

tables:
  observations
  # later only when justified:
  interventions
  outcomes
  analyses
```

Reasons for the choice:

- document-style records without one-file-per-event storage;
- explicit namespace/database organization;
- direct SurrealQL querying and aggregation;
- self-hosted/local operation;
- future native record links/graph relations if interaction analysis justifies
  them;
- room for pre-computed analytic views, full-text/vector features, extensions or
  MCP access later without requiring them in R1.

The existence of these features is **not** a commitment to use them. L4 follows
the same measured-need rule as L3: add complexity only after a demonstrated
requirement.

## Storage contract

The authoritative conversation text remains in **L0**. L4 stores epistemic
annotations and source references, not duplicate transcripts. An observation
should normally contain a `turn_id`/source reference and optionally a short
bounded evidence excerpt for inspection or export.

SurrealDB is the canonical L4 store:

```text
lfo / epistemic / observations
```

Derived counts, rolling patterns, recurrence scores and policy summaries are
analytics, not authoritative facts. They must be reconstructible from the
underlying observations.

## L4 sublayers

Conceptually:

```text
L4-O  Observation Store
      record epistemic events

L4-A  Epistemic Observatory
      query and derive longitudinal / interaction patterns

L4-P  Epistemic Balancer / Policy
      optionally alter retrieval or response policy after rare triggers
```

This does not require three separate services. It is a semantic separation of
responsibilities within L4.

## R1 — recommended first implementation milestone

**L4-R1: Epistemic Observation Store**

R1 should deliberately stop before active balancing. It should implement:

- local SurrealDB development/runtime contract;
- namespace `lfo`, database `epistemic`;
- `observations` schema/record contract;
- append/create API from the orchestrator;
- source-turn provenance;
- actor/stage/type/confidence/detector metadata;
- read/query API sufficient for explicit analytic inspection;
- basic tests for persistence, restart, source linkage and isolation;
- no production-memory mutation during isolated tests;
- no mandatory extra LLM call.

R1 should **not** yet implement:

- automatic response rewrites;
- persistent user profiling;
- graph traversal;
- vector search;
- WASM/plugin logic;
- continuous L4 prompt injection;
- generalized intervention policy.

Only after real observations exist should L4-A analytics and L4-P intervention
thresholds be designed and evaluated against measured data.

## Research invariant

A concise design invariant for the layer is:

> **L4 history is not continuously injected context. It is a write-mostly
> epistemic event record and an event-triggered control signal.**

And the evidence boundary is:

> **Observation history may change the degree of epistemic caution or the
> retrieval policy; it does not determine factual truth.**
