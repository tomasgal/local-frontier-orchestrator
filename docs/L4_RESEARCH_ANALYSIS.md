# L4 research analysis

## Status

L4 is a **planned research-analysis layer**, not part of the current v9.4 implementation milestone.

The active v9.4 work remains focused on **L2 structured factual state**. L3 and L4 define later architectural boundaries so that retrieval, factual state, and research interpretation do not collapse into one store.

The intended hierarchy is:

```text
L0  raw evidence / authoritative interaction history
L1  semantic conversational working memory
L2  structured factual state
L3  retrieval & resolution fabric
L4  research / epistemic analysis output
```

L4 is primarily an **analytical output layer**. It may persist research observations for longitudinal study and replay, but it is not an authoritative factual store and should not silently become an active user profile.

## 1. Why L4 exists

The Human–AI Bias Balancer research needs to represent claims that are neither raw events nor ordinary current-state facts.

Examples include:

- a particular interaction event appears compatible with confirmation/myside bias;
- a model response appears compatible with sycophancy;
- an intervention was applied;
- an outcome changed after the intervention;
- several events form a tentative longitudinal pattern.

These are **derived interpretations**.

They should therefore not be written directly into L2 as facts such as:

```text
user has_bias confirmation_bias
```

A more defensible representation is event-scoped, provenance-preserving, confidence-bearing, and explicitly defeasible.

## 2. L4 as output, L3 as input fabric

The conceptual data flow is:

```text
L0 raw events --------------------+
                                  |
L2 structured state --------------+--> L3 retrieval / resolution
                                  |         |
external knowledge adapters ------+         |
                                            v
                                     selected evidence
                                            |
                                            v
                                  L4 research analysis
                                            |
                       +--------------------+--------------------+
                       |                    |                    |
                 observation          intervention           outcome
                       |
                 hypothesis / pattern
```

L3 answers **what evidence or context should be considered**.

L4 answers **what analytical interpretation is being proposed from that evidence**.

This separation matters because retrieval relevance and analytical validity are different questions.

## 3. L3 retrieval & resolution fabric

L3 should be understood broadly as a retrieval/resolution fabric, not necessarily as a vector database.

Possible L3 mechanisms include:

- exact lexical retrieval from L0;
- selective L2 entity/predicate lookup;
- alias resolution;
- fuzzy entity matching;
- entity linking;
- reranking;
- embeddings if real retrieval failures justify them;
- read-only adapters to external knowledge sources.

External sources remain external. For example:

```text
DokuWiki
documents
Git repositories
web
```

may be queried through L3 adapters, but they do not become L3 storage and are not themselves L4.

## 4. DokuWiki search as an L3 adapter

The DokuWiki search subsystem is useful to L4 precisely because L4 analysis can require conceptual, methodological, or historical context.

A possible path is:

```text
current interaction event
        |
        v
L3 retrieves:
  - analogous L0 events
  - relevant L2 state
  - DokuWiki segments
        |
        v
L4 analysis
```

The DokuWiki adapter may use:

- explicit page/segment graph structure;
- headings and hierarchy;
- bold retrieval hints;
- the compact high-information lexical rescue index.

The search subsystem therefore helps **assemble evidence and context for analysis**. It is not the L4 output itself.

## 5. Core L4 objects

A useful first conceptual model contains:

```text
InteractionEvent
Actor
BiasObservation
BiasType
Intervention
Outcome
LongitudinalHypothesis
```

The key design choice is to represent bias as an **observation about an event and actor**, not as a permanent actor property.

Prefer:

```text
(:BiasObservation)
  -[:ABOUT_EVENT]->(:InteractionEvent)
  -[:ABOUT_ACTOR]->(:Actor)
  -[:BIAS_TYPE]->(:BiasType)
```

over:

```text
(:Actor)-[:HAS_BIAS]->(:BiasType)
```

The latter is too easy to reinterpret as a stable psychological trait.

## 6. BiasObservation

A bias observation should carry enough metadata to remain inspectable and defeasible.

Example:

```text
BiasObservation:
  event_ref              turn:918
  actor                  human
  bias_type              confirmation_bias
  confidence             0.64
  method                 balancer-v1
  supporting_evidence    [...]
  contradicting_evidence [...]
  status                 hypothesis
  created_at             ...
```

Model-side observations can use the same pattern:

```text
BiasObservation:
  event_ref     turn:919
  actor         local_model
  bias_type     sycophancy
  confidence    0.81
  method        balancer-v1
  status        hypothesis
```

The project does not assume that human and model biases share the same psychological mechanism. L4 records interaction-level analytical observations.

## 7. Intervention and outcome

For Balancing the Loop, detecting a possible bias is not enough.

The research-relevant chain is:

```text
event
  -> observation
  -> intervention
  -> outcome
```

An intervention may record:

- policy or strategy used;
- target actor or interaction loop;
- trigger;
- model/policy version;
- whether the intervention was generic or personalized.

An outcome may record:

- final task correctness;
- verification behavior;
- confidence change;
- uptake of correct advice;
- resistance to incorrect advice;
- later unaided performance;
- other appropriate-reliance measures.

This supports research questions about whether an intervention improves the Human–AI loop rather than merely changing surface agreement.

## 8. Longitudinal hypotheses

Repeated observations may justify a higher-level analytical hypothesis, for example:

```text
LongitudinalHypothesis:
  actor                  human
  pattern                confirmation-bias-like response
  condition              evidence-evaluation tasks
  supporting_events      [...]
  contradicting_events   [...]
  confidence             0.71
  method                 analysis-v2
  status                 hypothesis
```

Such a record is still **not an L2 fact**.

It must remain conditional, provenance-linked, revisable, and distinguishable from direct evidence.

## 9. Epistemic boundary

The intended authority relationship is:

```text
L0  evidence of what happened
L1  lossy working orientation
L2  deterministic current factual state
L3  candidate retrieval / resolution
L4  derived research interpretation
```

Therefore:

- L4 must not silently overwrite L2;
- L4 hypotheses must not become factual user attributes;
- confidence is not truth;
- repeated detection is not proof of a stable trait;
- model labels require provenance and method/version metadata;
- contradictory evidence must be representable;
- L4 output should not automatically be injected into ordinary conversation context.

If future mediation uses prior L4 observations, they should be retrieved explicitly and with provenance rather than treated as hidden persistent beliefs about the user.

## 10. Relationship to the experimental user model

The Bias Balancer may eventually maintain interpretable longitudinal research variables such as:

- verification propensity;
- confidence calibration;
- response to correction;
- reliance when AI agrees;
- reliance when AI disagrees.

These belong conceptually with L4 research analysis rather than ordinary conversational memory.

The system should avoid learning or preserving a hidden profile of **what the user believes** merely to personalize agreement. That would create the confirmation-machine failure the research is intended to study.

## 11. Implementation direction

L4 does not require a specific physical database yet.

Possible implementations include:

- structured JSONL research records;
- SQLite tables;
- a property graph;
- a combination of event records plus derived graph projections.

The logical contract should be stabilized before choosing a heavier backend.

A first implementation should prioritize:

1. immutable event references;
2. explicit actor identity;
3. reified observations;
4. provenance;
5. confidence and method/version;
6. supporting and contradicting evidence;
7. intervention/outcome linkage;
8. clear separation from L2 factual state.

## 12. Non-goals

L4 is not intended to:

- diagnose psychological traits;
- create a hidden ideological or belief profile;
- turn one model classification into an enduring user property;
- replace raw interaction evidence;
- decide L2 supersession;
- treat external knowledge as proof of an event-level bias;
- optimize for agreement or user satisfaction.

Its purpose is to make research interpretation **explicit, queryable, revisable and auditable**.
