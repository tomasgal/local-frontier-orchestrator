# Generic Epistemic Mediator

## Interaction-level bias measurement and mitigation in Human–LLM systems

**Status:** first-stage research specification under [Balancing the Loop](HUMAN_AI_BIAS_BALANCER.md).

**Implementation boundary:** LFO v9.6.2 provides a reproducible L0–L4 substrate. The mediator policy and its efficacy remain experimental. P1/P2 intervention is not enabled in the normal runtime.

## 1. Scope

The first mediation study should be **generic and non-personalized**.

Its purpose is to determine whether observable interaction-level distortions can be measured against explicit controls and mitigated by an auditable local policy without introducing more error than it removes.

The first-stage mediator should not infer a permanent psychological profile of the user and should not optimize for agreement, satisfaction, or preservation of the user’s beliefs.

```text
user request
    |
    v
pre-response analysis / optional rewrite
    |
    v
frontier advice or frozen response
    |
    v
post-response analysis / optional intervention
    |
    v
user-facing answer
```

## 2. Use the existing LFO substrate

The research layer should build on, not duplicate, the existing architecture:

```text
L0  raw evidence and exact interaction provenance
L1  conversational working memory
L2  structured factual state
L3  retrieval / resolution
L4  event-scoped epistemic observations and bounded analytics
```

Important boundaries:

- an L4 observation is not an L2 fact;
- a bias-related signal is not a permanent user trait;
- retrieved context is evidence/context, not itself a bias label;
- ordinary conversational memory should not automatically contain derived bias labels;
- study-specific participant/trial data can use an additional store when needed, but a second complete provenance system is unnecessary if LFO already records the required evidence.

Current runtime details are documented in [L4_RECORDING_MANUAL_ANALYSIS.md](L4_RECORDING_MANUAL_ANALYSIS.md).

## 3. Observation before interpretation

Prefer event-scoped descriptions:

```text
event_ref: turn_123
observable_signal: leading_question
evidence:
  - explicit preferred conclusion in user prompt
interpretation:
  compatible_with: confirmation_or_myside_bias
status: hypothesis
```

Avoid promoting this to:

```text
user has confirmation bias
```

Likewise, model behaviour can be described as agreement with a false premise, answer reversal under changed framing, or omission of counter-evidence without assuming a human-like psychological mechanism inside the model.

## 4. Bias magnitude, not one universal “bias level”

The mediator should not produce one generic low/medium/high bias score.

For each selected phenomenon, the researcher should define a **phenomenon-specific magnitude** relative to an explicit reference or control.

Possible references include:

- independently verifiable ground truth;
- a neutralized version of the same prompt;
- a balanced evidence set;
- a benchmark-defined reference answer;
- a counterbalanced condition;
- the response distribution before versus after a controlled framing manipulation.

Example:

```text
neutral prompt  -> response distribution A
framed prompt   -> response distribution B

framing magnitude = measured shift attributable to the framing manipulation
```

The existing L4/R1 `confidence` field is detector metadata. It must **not** be reused as a bias-magnitude score.

There is no assumption that one scalar represents all forms of bias.

## 5. Researcher-controlled mediator parameters

The mediator configuration should expose the assumptions that materially determine behaviour.

A useful experiment-level parameter set is:

```text
phenomenon
reference_condition
magnitude_metric
detector_profile / detector_sensitivity
intervention_threshold
intervention_weight_or_intensity
abstention_rule
false_intervention_budget
policy_version
```

Not every phenomenon needs every field, and the implementation names can differ. The important requirement is that the choices are explicit and auditable.

The researcher should:

1. choose and justify the operational definitions;
2. tune only during development/pilot work;
3. document failure cases;
4. freeze the mediator configuration before confirmatory data collection.

This makes the **choice of bias magnitude, sensitivity, thresholds, weights, and abstention rules part of the scientific contribution**, rather than an opaque property of the LLM.

## 6. Candidate phenomena

### 6.1 User framing / confirmation-seeking signals

Observable candidates:

- explicit preferred conclusion;
- leading question;
- assertion phrased as a request for confirmation;
- selective request for supporting evidence;
- asymmetric request that excludes counter-evidence.

Candidate interventions:

- neutral rewrite;
- convert assertion into an open question;
- request counter-evidence;
- request alternative hypotheses;
- obtain an independent answer before exposing the model to the user’s preferred conclusion.

### 6.2 Model sycophancy / agreement bias

Observable candidates:

- agreement with an incorrect or unsupported premise;
- answer reversal when the user’s stated position changes while evidence remains fixed;
- selective omission of counter-evidence after a preference is expressed;
- stronger agreement under first-person or high-certainty framing.

Candidate interventions:

- neutralized re-query;
- independent-answer first pass;
- explicit counter-evidence request;
- critique or contradiction check;
- preserve the distinction between evidence and user preference.

### 6.3 Appropriate reliance

Automation bias is best treated mainly as a behavioural outcome rather than a one-turn text label.

Candidate measures:

- uptake of correct AI advice;
- resistance to incorrect AI advice;
- verification when useful;
- confidence change after AI exposure;
- reliance discrimination;
- persistence of AI-induced shifts on later unaided tasks.

### 6.4 Unsupported certainty / over-coherence

Observable candidates:

- categorical language without adequate support;
- loss of explicit uncertainty;
- omission of plausible alternatives;
- rhetorical closure of a genuinely unresolved problem.

Do not display pseudo-calibrated numerical confidence unless the measurement method actually supports calibration.

## 7. P1/P2 as a reference intervention, not a requirement

The existing LFO P1/P2 work provides a bounded intervention reference and evidence boundary. It is useful for research because it gives a concrete starting point without claiming efficacy.

A study may:

- validate the current P1/P2 mechanism;
- change its thresholds or other parameters;
- retain the same measurement contract but replace the intervention;
- propose a better intervention policy and compare it against P1/P2.

A negative result is informative. If P1/P2 has no effect, distorts correct advice, or creates too many false interventions, that is a valid empirical result rather than a failed project.

## 8. Diagnostic task and replay bank

The first controlled study should use tasks with independent ground truth or a defensible scoring rule.

Useful paired/counterbalanced manipulations include:

```text
neutral prompt        vs leading prompt
correct prior         vs incorrect prior
question              vs assertion / conviction
independent judgement vs request for affirmation
same evidence + different stated user position
```

The preferred confirmatory design uses a **Frozen-Response / Replay Mode**.

Frontier prompts and validated outputs are generated and archived in advance. During the human experiment, the same stored advice is delivered through the direct or mediated pipeline.

Benefits:

- participants receive comparable advice;
- provider/model drift is removed from the primary manipulation;
- the same responses can be re-evaluated under multiple mediator policies;
- the experiment remains reproducible after a commercial model changes.

A live-frontier run can be used later as an ecological-validity extension, not as the primary controlled condition.

## 9. Pilot

The pilot should answer practical and falsification questions, not merely demonstrate that the interface opens.

Check at least:

- task difficulty and ceiling/floor effects;
- whether diagnostic traps work as intended;
- pipeline and replay correctness;
- provenance and study-specific logging;
- participant burden and timing;
- intervention frequency;
- obvious false positives / false interventions;
- whether the analysis variables can actually be reconstructed;
- whether the generic mediator shows enough signal to justify a larger study.

A very small pilot is suitable for these checks. It should not be treated as a precise standalone estimate of the main effect size.

## 10. Confirmatory generic-mediator experiment

The clean first comparison is:

### A. Direct

```text
User <-> frozen frontier advice
```

### B. Generic mediator

```text
User <-> generic LEB <-> frozen frontier advice
```

Candidate primary outcomes:

- reliance discrimination;
- uptake of correct advice;
- resistance to incorrect advice;
- calibration;
- verification behaviour;
- factual/task accuracy.

Candidate mediator-quality outcomes:

- false-intervention rate;
- evidence preservation;
- distortion of correct advice;
- missed interventions;
- latency;
- token/model-call overhead.

Analysis should normally operate at the trial level and preserve repeated-measures structure where the design requires it.

## 11. Sample-size logic

Do not choose an (N) and then use power analysis to justify it.

The sequence should be:

```text
research question
 -> smallest effect of interest / defensible effect assumption
 -> variance / design assumptions
 -> alpha and desired power
 -> a priori power analysis
 -> required N
 -> feasibility and attrition allowance
```

If the required (N) is infeasible for the available project window, narrow the hypothesis, redesign the study, or explicitly treat it as pilot/exploratory. Do not reverse-engineer assumptions solely to preserve a preferred sample size.

## 12. Protocol freeze

Before confirmatory data collection, freeze and version at least:

- task/replay bank;
- ground-truth/scoring rules;
- mediator phenomenon definitions;
- magnitude metrics;
- detector sensitivity/profile;
- intervention thresholds/weights;
- abstention criteria;
- outcome definitions;
- exclusion rules;
- analysis plan;
- software/model/policy versions.

Changes after the freeze should be logged and separated from confirmatory analysis.

## 13. Gate before personalization

Personalization is a second-stage experiment.

Proceed only when the generic condition has:

- a defensible operational definition;
- stable task and replay bank;
- acceptable pipeline reliability;
- measurable mediator behaviour;
- an understood false-intervention profile;
- pre-specified falsification criteria.

The first personalization model should adapt to **metacognitive behaviour**, not belief content.

Before a large human personalized study, run an offline/adversarial confirmation-machine stress test. A critical question is whether personalization increases agreement with the user independently of correctness or suppresses valid disagreement.

## 14. Reproducibility and dissemination

Record the exact apparatus:

- LFO commit/release;
- local model/checkpoint and quantization;
- runtime;
- prompts/policies;
- mediator configuration;
- task-bank and replay-bank versions;
- analysis code.

A clean public code/protocol release is encouraged where appropriate, but it is not part of the causal evidence. A GitHub release can optionally be archived through Zenodo to obtain a persistent DOI.

## 15. Non-goals

The first generic mediator should not:

- diagnose stable psychological traits;
- learn or preserve the user’s political, moral, or factual beliefs as preferences;
- assign a universal bias score;
- claim universal debiasing;
- treat model sycophancy as psychologically identical to human confirmation bias;
- optimize for user agreement or satisfaction;
- make live-frontier variability part of the primary confirmatory manipulation when replay can provide a cleaner control;
- treat the existence of LFO/L4 as evidence that the mediator is valid.

## Core reading

1. **Glickman, M. & Sharot, T. (2025).** *How human–AI feedback loops alter human perceptual, emotional and social judgements.* Nature Human Behaviour, 9, 345–359. DOI: https://doi.org/10.1038/s41562-024-02077-2
2. **Sharma, M. et al. (2024).** *Towards Understanding Sycophancy in Language Models.* ICLR 2024.
3. **Schemmer, M. et al. (2023).** *Appropriate Reliance on AI Advice: Conceptualization and the Effect of Explanations.* IUI 2023. DOI: https://doi.org/10.1145/3581641.3584066
4. **Jain, S. et al. (2026).** *Interaction Context Often Increases Sycophancy in LLMs.* CHI 2026.
5. **Dubois, M. et al. (2026).** *Ask don't tell: Reducing sycophancy in large language models.*

## Related documents

- [Balancing the Loop](HUMAN_AI_BIAS_BALANCER.md)
- [L4 recording and manual analysis](L4_RECORDING_MANUAL_ANALYSIS.md)
- [LFO architecture](ARCHITECTURE.md)
