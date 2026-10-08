# Generic Epistemic Mediator

## Interaction-level bias measurement and mitigation in Human–LLM systems

**Status:** narrowed research/design workstream under [Balancing the Loop](HUMAN_AI_BIAS_BALANCER.md).  
**Implementation status:** not frozen; the current priority is theoretical operationalization, benchmark design, and interface specification while the LFO L2/L3/L4 boundaries are still evolving.

This document defines a narrower, non-personalized engineering research track within the broader Human–AI Bias Balancer program.

The focus is not to diagnose stable psychological traits in users and not to assign a generic "bias risk score." The focus is to identify **observable interaction-level effects**, measure their magnitude relative to an explicit reference condition, apply auditable interventions, and evaluate whether those interventions improve the interaction.

## 1. Research aim

The main research question is:

> Can a generic, auditable mediation layer reduce measurable framing- and sycophancy-related distortions in Human–LLM interaction while preserving useful model assistance and appropriate human reliance?

The mediator is intentionally **non-personalized** in the first implementation. It should operate on the current interaction and explicitly retrieved evidence rather than on a hidden profile of the user's beliefs.

A minimal conceptual flow is:

```text
user request
    |
    v
pre-response interaction analysis
    |
    v
local/frontier LLM
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

The broader longitudinal and personalized questions remain part of [Balancing the Loop](HUMAN_AI_BIAS_BALANCER.md), but are outside this narrowed workstream.

## 2. Theoretical scope

The theory section should concentrate on Human–AI / Human–LLM interaction rather than expanding into a broad catalogue of cognitive biases.

The central concepts are:

1. **confirmation / myside bias and framing** on the human side;
2. **sycophancy / agreement bias** on the model side;
3. **automation bias and appropriate reliance** as interaction outcomes;
4. **mitigation strategies** that can intervene before or after an LLM response;
5. **limits of automatic detection**, especially the difference between an observable interaction signal and a psychological interpretation.

Authority-related effects and anthropomorphism remain relevant background topics, but they are secondary unless a defensible operational measure is defined.

## 3. Observation before interpretation

The mediator should distinguish direct evidence from a stronger research interpretation.

Prefer an event-scoped record such as:

```text
event_ref: turn_123
observable_signal: leading_question
evidence:
  - explicit preferred conclusion in the user prompt
interpretation:
  compatible_with: confirmation_or_myside_bias
status: hypothesis
```

over:

```text
user has confirmation bias
```

Likewise, a model response can be described as agreement with a false premise, answer reversal under changed framing, or omission of counter-evidence without assuming a human-like psychological mechanism inside the model.

This is consistent with the planned L4 research-analysis boundary: bias-related outputs are **derived, defeasible observations about events**, not permanent user attributes and not L2 factual state.

## 4. Bias strength, not generic risk

The first implementation should **not** output a generic low/medium/high "bias risk."

A more useful quantity is **bias magnitude / bias strength**: the measured deviation from an explicit reference or control condition.

The reference must be defined for the specific phenomenon. Depending on the task, it may be:

- independently verifiable ground truth;
- a neutralized version of the same prompt;
- a balanced evidence set;
- an expert- or benchmark-defined reference answer;
- a counterbalanced experimental condition;
- the response distribution before versus after a controlled framing manipulation.

For example:

```text
neutral prompt  -> response distribution A
framed prompt   -> response distribution B

bias magnitude = measured shift attributable to the framing manipulation
```

Possible measures include:

- change in agreement with a false prior;
- change in factual correctness;
- change in selected option or ranking;
- change in expressed confidence;
- change in inclusion of counter-evidence;
- semantic movement toward the user's stated position;
- effect size across repeated samples.

There is no assumption that one universal scalar can represent all forms of bias.

"Unbiased objectivity" should therefore be treated carefully. When ground truth exists, correctness can be the reference. When it does not, the experiment must define a defensible neutral, balanced, counterfactual, or counterbalanced condition rather than silently assuming a universal objective answer.

## 5. Candidate phenomena

### 5.1 User framing / confirmation-seeking signals

Observable candidates include:

- explicit prior or preferred conclusion;
- leading question;
- assertion phrased as a request for confirmation;
- selective request for supporting evidence;
- asymmetric request that excludes counter-evidence.

Possible interventions:

- neutral rewrite;
- convert assertion into an open question;
- request counter-evidence;
- request alternative hypotheses;
- obtain an independent answer before exposing the model to the user's preferred conclusion.

### 5.2 Model sycophancy / agreement bias

Observable candidates include:

- agreement with an incorrect or unsupported user premise;
- answer reversal when the user's stated position changes while evidence remains fixed;
- selective omission of counter-evidence after the user expresses a preference;
- increased agreement under first-person or high-certainty framing.

Possible interventions:

- neutralized re-query;
- independent-answer first pass;
- explicit counter-evidence request;
- critique or contradiction check;
- preserve the distinction between evidence and user preference.

### 5.3 Automation bias / appropriate reliance

Automation bias is less suitable as a one-turn text classification target because the relevant phenomenon is how the user acts on automated advice.

It is better represented as an **outcome variable**, for example:

- uptake of correct AI advice;
- resistance to incorrect AI advice;
- verification when verification is useful;
- confidence change after AI exposure;
- persistence of AI-induced shifts on later unaided tasks.

The goal is not maximal trust or maximal distrust. The target is **appropriate reliance**.

### 5.4 Unsupported certainty and over-coherence

A secondary model-side signal is the production of a stronger or more settled conclusion than the available evidence supports.

Observable candidates include:

- categorical language without adequate support;
- loss of explicit uncertainty;
- omission of plausible alternatives;
- rhetorical closure of a genuinely unresolved problem.

The system should not display pseudo-calibrated numerical confidence unless the measurement method actually supports calibration.

## 6. Candidate research questions

1. Which interaction-level signals can be operationalized reliably without inferring stable psychological traits?
2. How strongly does controlled user framing shift model outputs relative to neutral or counterbalanced conditions?
3. Can a generic mediator reduce sycophancy or false-prior agreement without suppressing justified agreement?
4. Can the mediator improve appropriate reliance on AI advice in tasks with defensible ground truth?
5. What false positives, false interventions, latency costs, and other trade-offs are introduced by the mediation layer?

These questions intentionally precede implementation details. The exact detector and intervention design should follow from the operational definitions and benchmark.

## 7. Experimental / benchmark design

The first evaluation should prefer tasks with independent ground truth or defensible scoring criteria.

Useful paired or counterbalanced prompt conditions include:

```text
neutral prompt
leading prompt

correct prior
incorrect prior

question
assertion / belief / conviction

request for independent judgement
request for affirmation

same evidence + different stated user position
```

A direct comparison can then use:

```text
A. direct LLM interaction
B. framed interaction without mediator
C. framed interaction with generic mediator
```

Candidate measurements include:

- false-prior agreement rate;
- sycophancy rate;
- factual accuracy;
- answer shift under controlled framing;
- counter-evidence coverage;
- unsupported-certainty frequency;
- appropriate-reliance measures;
- false-intervention rate;
- latency;
- token overhead;
- extra local/frontier calls.

The evaluation should preserve stochastic variation. A fixed seed can be useful diagnostically, but the research target is a comparable **distribution of behaviour**, not bitwise-identical output.

## 8. Candidate mediator contract

Before the LFO implementation is frozen, a technology-neutral contract is preferable.

Candidate inputs:

```text
user_prompt
model_response
optional_reference_condition
optional_ground_truth_or_evidence
optional_retrieved_context
```

Candidate outputs:

```text
observable_signals[]
derived_observations[]
bias_magnitude_measures[]
intervention_applied
intervention_rationale
evaluation_metadata
```

A structured observation should preserve:

- event reference;
- actor;
- phenomenon / signal type;
- supporting evidence;
- contradicting evidence where applicable;
- measurement or confidence metadata;
- method/version;
- status such as observation or hypothesis.

The exact schema should converge with [L4_RESEARCH_ANALYSIS.md](L4_RESEARCH_ANALYSIS.md) once the L3/L4 implementation boundary is stable.

## 9. Relationship to LFO layers

The current intended hierarchy is:

```text
L0  raw interaction evidence
L1  semantic conversational working memory
L2  structured factual state
L3  retrieval & resolution fabric
L4  research / epistemic analysis output
```

The generic mediator fits conceptually as:

```text
L0 interaction event ----------------+
                                     |
L2 relevant factual state -----------+--> L3 selected evidence/context
                                     |          |
external knowledge adapters ---------+          v
                                           mediator analysis
                                                |
                               +----------------+----------------+
                               |                                 |
                        L4 observation                    intervention
                               |                                 |
                               +---------------+-----------------+
                                               |
                                               v
                                            outcome
```

Important boundaries:

- a bias observation is not an L2 fact;
- an L4 hypothesis must not silently become an active user profile;
- retrieved context is evidence/context, not itself a bias label;
- ordinary conversational memory should not automatically contain derived bias labels;
- L3 retrieval relevance and L4 analytical validity are separate problems.

The LFO implementation should not be forced prematurely around this research track. The current preparation can proceed through theory, operationalization, benchmark design, and interface specification while the underlying L2/L3/L4 interfaces mature.

## 10. Staged work plan

### Phase 1 — theory and operationalization

For each selected phenomenon:

- define the phenomenon from current Human–AI / LLM literature;
- separate direct observation from interpretation;
- identify the reference/control condition;
- define a measurable bias magnitude;
- identify known mitigation strategies;
- identify confounds and false positives.

### Phase 2 — analytical specification and benchmark

- select two or three phenomena for the first implementation;
- define paired/counterbalanced test cases;
- define structured detector output;
- define intervention policies;
- define evaluation metrics and falsification criteria.

### Phase 3 — prototype

- implement a bounded generic mediator;
- integrate pre- and/or post-response hooks into LFO;
- preserve provenance and research traces;
- avoid hidden user profiling.

### Phase 4 — evaluation and discussion

- compare direct and mediated conditions;
- quantify effect sizes and false interventions;
- measure engineering overhead;
- document limitations and cases where the mediator should abstain.

## 11. Expected contribution

A useful contribution from this workstream does not require discovering a new cognitive bias or inventing a new machine-learning algorithm.

A defensible contribution can consist of:

- a rigorous operationalization of selected Human–LLM interaction effects;
- a generic mediator design;
- a structured observation/intervention contract;
- a working prototype integrated with LFO;
- a reproducible benchmark;
- an empirical comparison of direct versus mediated interaction;
- evidence about where the mediator helps, fails, or introduces new distortions.

## 12. Non-goals

The first generic mediator should not:

- diagnose stable psychological traits;
- assign a universal "bias risk score";
- build a hidden profile of user beliefs;
- personalize interventions from long-term user preferences;
- claim universal debiasing;
- treat model sycophancy as psychologically identical to human confirmation bias;
- make political persuasion, clinical advice, or identity-sensitive persuasion the primary experimental domain;
- depend on L3/L4 implementation details before those interfaces are stable.

## Core reading

1. **Glickman, M. & Sharot, T. (2025).** *How human–AI feedback loops alter human perceptual, emotional and social judgements.* Nature Human Behaviour, 9, 345–359.  
   DOI: https://doi.org/10.1038/s41562-024-02077-2

2. **Sharma, M. et al. (2024).** *Towards Understanding Sycophancy in Language Models.* International Conference on Learning Representations (ICLR 2024).  
   Proceedings: https://proceedings.iclr.cc/paper_files/paper/2024/hash/0105f7972202c1d4fb817da9f21a9663-Abstract-Conference.html

3. **Schemmer, M., Kühl, N., Benz, C., Bartos, A. & Satzger, G. (2023).** *Appropriate Reliance on AI Advice: Conceptualization and the Effect of Explanations.* IUI 2023.  
   DOI: https://doi.org/10.1145/3581641.3584066

4. **Jain, S., Park, C., Viana, M., Wilson, A. & Calacci, D. (2026).** *Interaction Context Often Increases Sycophancy in LLMs.* CHI 2026.  
   DOI: https://doi.org/10.1145/3772318.3791915

5. **Dubois, M., Ududec, C., Summerfield, C. & Luettgau, L. (2026).** *Ask don't tell: Reducing sycophancy in large language models.*  
   arXiv: https://arxiv.org/abs/2602.23971

## Relationship to the broader research program

This workstream intentionally narrows [Balancing the Loop](HUMAN_AI_BIAS_BALANCER.md) to the **generic, non-personalized mediation problem**.

The broader program still includes:

- longitudinal Human–AI feedback loops;
- adaptive/personalized mediation;
- confidence calibration over time;
- confirmation-machine failure modes;
- human-subject appropriate-reliance studies.

Those questions should be treated as separate layers rather than silently expanding the first generic mediator into the whole research agenda.
