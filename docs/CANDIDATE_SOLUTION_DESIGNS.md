# Candidate solution designs for the Human–AI Bias Balancer

**Status:** working design notes / non-binding candidates

This document captures candidate implementation directions for the Human–AI Bias Balancer research track. It is deliberately more concrete than the research overview in `HUMAN_AI_BIAS_BALANCER.md`, but it is **not** a frozen implementation specification.

The purpose is to preserve promising design ideas while L2/L3/L4 interfaces are still evolving.

## 1. Starting concept

A useful baseline concept is a mediation layer placed between a user and a conversational LLM.

The mediator may inspect:

- the user request before model execution;
- the model answer after execution;
- selected contextual evidence when retrieval is available;
- the intervention and its measurable outcome.

A simple conceptual flow is:

```text
user request
    |
    v
pre-response interaction analysis
    |
    v
LLM / frontier model
    |
    v
post-response interaction analysis
    |
    v
optional intervention
    |
    v
user-facing answer
```

Candidate functions include:

- detecting leading or affirmation-seeking formulations;
- detecting explicit user priors relevant to the task;
- detecting model agreement/sycophancy;
- detecting unsupported certainty;
- detecting omission of relevant alternatives or counter-evidence;
- requesting or presenting verification when warranted;
- neutralizing framing before a frontier call;
- requesting counter-evidence or alternative hypotheses;
- explaining why an intervention was triggered.

The mediator should not replace user judgement. Its role is to make interaction-level epistemic effects observable and experimentally testable.

## 2. Observation before psychological interpretation

The first implementation should distinguish observable interaction features from stronger psychological interpretations.

Prefer:

```text
event: turn_123
observation: leading_question
evidence: explicit preferred conclusion in user prompt
interpretation: compatible_with_confirmation_or_myside_bias
status: hypothesis
```

over:

```text
user has confirmation bias
```

The same applies to model-side behavior. For example, a response may be classified as agreement with a false premise or as framing-sensitive output without assuming a human-like psychological mechanism inside the model.

This matches the intended L4 design: bias-related records are event-scoped, provenance-preserving, defeasible analytical observations rather than permanent user properties.

## 3. Bias strength, not risk score

The mediator should not produce a generic "risk level" such as low/medium/high merely from an interaction.

A potentially useful research quantity is instead **bias magnitude / bias strength**: the measured deviation from a defined reference condition.

This requires an explicit baseline. "Unbiased objectivity" must not be treated as an assumed universal ground truth when the task has no unique objective answer.

Possible reference conditions include:

- independently verifiable ground truth;
- a neutralized version of the same prompt;
- a balanced evidence set;
- an expert- or benchmark-defined reference answer;
- a counterbalanced experimental condition;
- a model's response distribution before versus after controlled framing.

Example:

```text
neutral prompt -> model answer A
leading prompt -> model answer B

bias magnitude = measured shift attributable to the framing manipulation
```

Depending on the task, the metric may capture:

- change in probability or score assigned to an answer;
- change in factual correctness;
- change in agreement with a false prior;
- change in selected option;
- change in expressed confidence;
- omission/addition of counter-evidence;
- semantic movement toward the user's stated position.

The exact metric must be defined per phenomenon. A single universal scalar "bias score" is not assumed.

## 4. Candidate phenomena for the first generic mediator

### 4.1 User-side framing / confirmation-seeking signals

Observable candidates:

- explicit prior or preferred conclusion;
- leading question;
- assertion phrased as a request for confirmation;
- selective request for supporting evidence;
- resistance to requested counter-evidence.

Possible interventions:

- neutral rewrite;
- request for counter-evidence;
- request for alternative hypotheses;
- independent answer before exposing the model to the user's preferred conclusion.

### 4.2 Model-side sycophancy / agreement bias

Observable candidates:

- agreement with an incorrect or unsupported user premise;
- answer reversal when user framing changes while evidence remains constant;
- selective omission of counter-evidence when the user states a preference;
- excessive rhetorical alignment not justified by evidence.

Possible interventions:

- independent answer generation before user-position exposure;
- explicit counter-evidence request;
- critique pass;
- neutralized re-query.

### 4.3 Unsupported certainty / over-coherence

Observable candidates:

- strong categorical language without adequate support;
- failure to preserve known uncertainty;
- compression of a genuinely ambiguous problem into one definitive answer.

Possible interventions:

- preserve caveats;
- request evidence/provenance;
- expose competing hypotheses;
- trigger verification.

The system should not present a pseudo-calibrated probability unless the underlying method actually supports calibration.

### 4.4 Automation bias / appropriate reliance

Automation bias is less suitable as a one-turn text classifier because it concerns how the user relies on automated output.

It is better treated as an **outcome variable** in experiments, for example:

- whether correct AI advice is accepted;
- whether incorrect AI advice is resisted;
- whether the user verifies when verification is useful;
- whether confidence changes appropriately after AI exposure.

### 4.5 Authority and anthropomorphism

These remain relevant theoretically, but they may be harder to operationalize robustly in an initial engineering implementation.

They can remain secondary phenomena until a defensible observable signal and evaluation protocol is defined.

## 5. Candidate relation to LFO layers

The intended architecture is:

```text
L0  raw interaction evidence
L1  conversational working memory
L2  structured factual state
L3  retrieval / resolution fabric
L4  research / epistemic analysis
```

A future mediator can use:

```text
L0 event -----------------------+
                                |
L2 state -----------------------+--> L3 selected evidence/context
                                |          |
external knowledge adapter -----+          v
                                      analytical component
                                             |
                                             v
                                     L4 BiasObservation
                                             |
                                     optional Intervention
                                             |
                                             v
                                           Outcome
```

Important boundaries:

- L4 observations are not L2 facts.
- Bias labels must not silently become persistent conversational memory.
- A retrieved wiki/document segment is evidence/context, not itself a bias label.
- L3 retrieval relevance and L4 analytical validity are separate problems.

## 6. Candidate benchmark design

A first engineering benchmark should prefer tasks with independent ground truth or defensible scoring.

Useful paired or counterbalanced cases include:

```text
neutral prompt
leading prompt

correct prior
incorrect prior

request for independent judgement
request for affirmation

same evidence + different user position
```

Potential measurements:

- agreement with false prior;
- factual accuracy;
- answer shift between neutral and framed conditions;
- sycophancy rate;
- counter-evidence coverage;
- unsupported-certainty frequency;
- false-intervention rate;
- latency;
- token overhead;
- number of additional frontier/local calls.

The generic mediator should first be evaluated offline/replay or in tightly controlled prompt experiments before adaptive personalization is introduced.

## 7. Candidate implementation boundary

A first implementation does not need to solve the entire research program.

A defensible initial engineering scope is:

1. define a small set of observable interaction signals;
2. define structured detector output;
3. define explicit intervention policies;
4. integrate pre- and/or post-response hooks into LFO;
5. record provenance and outcomes;
6. compare direct versus mediated interaction on a controlled benchmark.

Personalized user modelling, longitudinal human-subject experiments, hidden belief profiling and adaptive intervention thresholds are outside this initial generic-mediator scope.

## 8. Preparatory theory work before implementation

Before freezing code, the implementation owner should be able to answer for each selected phenomenon:

- What is the phenomenon in the current Human–AI / LLM literature?
- What part is directly observable in text or behavior?
- What part is only an interpretation?
- What is the relevant neutral/control/reference condition?
- How can the magnitude of the effect be measured?
- Which intervention is theoretically justified?
- What are the likely false positives and confounds?
- What benchmark or experimental manipulation can reproduce the phenomenon?
- What evidence would count against the detector or intervention working?
- Which output fields must be preserved for later L4 analysis?

The main preparatory gap is therefore **operationalization and current mitigation literature**, not another broad survey of cognitive-bias definitions and not generic software-engineering study in isolation.

Software design should follow once the measurable phenomenon, reference condition and intervention contract are sufficiently clear.

## 9. Open design questions

- Which two or three phenomena should define the first implementation?
- Should pre-response and post-response analysis use the same classifier contract?
- When is a deterministic rule preferable to an LLM-based classifier?
- Which measurements are robust enough to support a "bias magnitude" claim?
- How should neutral/control prompts be generated and validated?
- How should counter-evidence be sourced without introducing a new systematic bias?
- Which L3 interfaces are actually required for the first implementation?
- What minimum L4 schema is needed before implementation starts?
- Can a useful generic mediator be evaluated entirely offline before human-subject testing?
