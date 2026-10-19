# Balancing the Loop

## Testing a Local Epistemic Balancer in Human–Frontier-LLM Interaction

**Status:** research programme / protocol under development. The Local Frontier Orchestrator (LFO) provides a reproducible L0–L4 substrate, but validated debiasing efficacy is not assumed.

**Reference implementation:** Local Frontier Orchestrator **v9.6.2** (Zenodo Software DOI [10.5281/zenodo.23373391](https://doi.org/10.5281/zenodo.23373391)).

For the first, generic non-personalized mediation stage, see [GENERIC_EPISTEMIC_MEDIATOR.md](GENERIC_EPISTEMIC_MEDIATOR.md).

## 1. Research premise

Human–LLM interaction can form a reciprocal feedback loop.

A user approaches the system with prior beliefs, framing, confidence, habits of verification, and varying willingness to rely on automated advice. A conversational model can exhibit sycophancy, agreement bias, sensitivity to framing, unsupported certainty, or selective omission of counter-evidence. Repeated interaction can therefore amplify error rather than provide an independent correction.

The research target is not an “unbiased AI.” It is a controlled and auditable mediation layer that improves **appropriate reliance**: accepting useful AI guidance while resisting misleading guidance.

```text
Human prior / judgement
        |
        v
Local epistemic mediator
        |
        v
Frontier LLM or frozen frontier response
        |
        v
Local evaluation / intervention
        |
        v
Human final judgement
```

## 2. Current LFO substrate

The supporting platform is no longer hypothetical. LFO provides a reproducible local/frontier pipeline and a frozen-enough persistence and analysis boundary:

```text
L0  raw interaction evidence / provenance
L1  conversational working memory
L2  structured factual state
L3  retrieval and resolution
L4  event-scoped epistemic observations / bounded analytics
```

The operational v9.6.2 line preserves conservative post-L0 L4 recording and explicit `/analyze` reads. P1/P2 response intervention remains disconnected/OFF in the normal runtime.

This distinction is important: the **research substrate exists**, while the epistemic-balancing policy, its parameters, and its empirical efficacy remain research questions.

## 3. Biases and interaction outcomes of interest

### Human-side observable tendencies

- confirmation / myside bias;
- inappropriate reliance and automation bias;
- confidence miscalibration;
- framing or anchoring sensitivity;
- failure to verify when verification would be useful.

### Model-side observable tendencies

- sycophancy / agreement bias;
- mirroring of user framing;
- unsupported certainty;
- omission of plausible alternatives or counter-evidence;
- over-coherent answers that make uncertain problems appear settled.

Human and model biases are not assumed to share the same psychological mechanism. The object of study is the **interaction-level behaviour** and its consequences.

## 4. Primary research questions

1. Does a generic local epistemic mediator improve appropriate reliance on AI advice compared with direct interaction?
2. Can the mediator reduce framing- or sycophancy-related distortions without introducing an unacceptable false-intervention rate?
3. Does repeated interaction with systematically biased or sycophantic AI shift later unaided human judgement?
4. If personalization is introduced, does metacognitive personalization improve outcomes beyond a generic policy?
5. Under what conditions does personalization itself become self-reinforcing and turn the mediator into a second-order **confirmation machine**?

## 5. Staged research sequence

The programme deliberately separates the validation stages. A later stage should not be treated as mandatory before the earlier one is empirically defensible.

### Stage 0 — reproduce and freeze the apparatus

- reproduce the current LFO reference implementation;
- record exact software/runtime/model/policy versions;
- identify the pre-response and post-response intervention points;
- use the existing LFO provenance/observation substrate rather than rebuilding it unless the experiment requires additional study-specific variables.

### Stage 1 — generic mediator first

Define a **generic, non-personalized** Local Epistemic Balancer.

The researcher owns the phenomenon-specific operationalization:

- reference/control condition;
- bias-magnitude metric;
- detector sensitivity or profile;
- intervention threshold;
- intervention strength/weight where applicable;
- abstention criteria;
- acceptable false-intervention rate.

These parameters must be explicit, auditable, and frozen before confirmatory data collection.

The existing P1/P2 intervention work is a **reference candidate**, not a mandated solution. It can be validated as-is, re-parameterized, or replaced by a better justified intervention contract.

### Stage 2 — task/replay bank and pilot

Build and validate a diagnostic task bank with independent ground truth or a defensible scoring rule.

The pilot should primarily test:

- task validity and difficulty;
- pipeline correctness;
- logging and provenance;
- response timing and participant burden;
- intervention behaviour and obvious false positives;
- replay/frozen-response delivery;
- feasibility of the planned analysis.

A very small pilot should not be used as the sole source of a precise main-effect estimate.

### Stage 3 — controlled confirmatory experiment

The preferred primary design uses a **Frozen-Response / Replay Mode**: validated frontier outputs are generated and archived in advance and replayed through the same mediation pipeline.

This isolates the experimental manipulation from provider/model drift and makes participants comparable.

A live-frontier replication can be added as a later ecological-validity check. It should not be required for the primary controlled result.

Sample size must be determined by an **a priori power analysis** or another explicit design-justification framework. The analysis should start from the smallest effect of interest and defensible variance assumptions; it must not be used to retrospectively justify a preselected (N).

### Stage 4 — personalized mediation

Personalization is a conditional extension after the generic mediator has a defensible measurement model and acceptable failure profile.

The first personalization model should use **metacognitive behaviour**, not belief content. Candidate variables include:

- uptake of correct versus incorrect AI advice;
- verification propensity;
- confidence calibration;
- baseline task accuracy;
- response to disagreement or correction.

Personalization should remain interpretable and parameterized before considering weight-level fine-tuning.

## 6. Core experimental conditions

A full longitudinal study can compare:

### A. Direct condition

```text
User <-> frontier advice / frozen frontier response
```

No epistemic intervention.

### B. Generic mediator

```text
User <-> generic local mediator <-> frontier advice
```

Static, pre-frozen intervention policy.

### C. Personalized mediator

```text
User <-> adaptive local mediator <-> frontier advice
```

The same policy family, with pre-specified thresholds adapted from observable metacognitive behaviour.

Condition C is not required to establish whether the generic mediator works.

## 7. Outcome concept: appropriate reliance

The target is neither maximal trust nor maximal distrust.

A useful system should help a person discriminate between advice that should be followed and advice that should be questioned or rejected.

Candidate measures include:

- independent judgement before AI exposure;
- confidence before AI exposure;
- verification behaviour;
- final judgement and confidence;
- uptake of correct AI advice;
- resistance to incorrect AI advice;
- reliance discrimination;
- calibration error / Brier-style measures where appropriate;
- persistence of AI-induced shifts on later unaided tasks;
- false-intervention rate;
- latency, token, and model-call overhead.

Accuracy and epistemic autonomy must not be conflated: a person can be autonomously wrong or correctly rely on AI. Appropriate reliance and calibration are therefore central behavioural outcomes.

## 8. Confirmation-machine failure mode

Personalized debiasing is not automatically neutral.

A mediator can develop a second-order bias if adaptation increasingly tracks the user’s preferred conclusions, framing, or rhetorical style rather than the user’s metacognitive weaknesses.

```text
user tendency
   -> personalized mediator adapts
   -> evidence / advice is selectively framed
   -> user receives repeated confirmation
   -> future adaptation reinforces the same pattern
```

At minimum, personalization should undergo an offline/adversarial stress test asking whether adaptation increases agreement with the user **independently of correctness** or systematically suppresses valid disagreement.

A human-subject confirmation-machine study is valuable, but it is not required before this cheaper falsification layer has been attempted.

## 9. Study boundaries

Prefer initial tasks with independent ground truth or defensible scoring criteria, such as:

- probabilistic reasoning;
- evidence evaluation;
- source comparison;
- causal inference;
- quantitative estimation;
- short diagnostic reasoning tasks.

Avoid making political persuasion, clinical advice, identity-sensitive persuasion, or broad personality profiling the primary first-study domain.

## 10. Reproducibility and dissemination

The controlled apparatus should record or archive, as applicable:

- LFO version/commit;
- local model/checkpoint and quantization;
- runtime and context policy;
- system/policy prompts;
- decoding parameters;
- mediator configuration and parameter version;
- task-bank version;
- frozen frontier prompts and responses;
- scoring code and analysis specification.

A public code/protocol release is useful but is a dissemination output, not evidence of efficacy. Where appropriate, a GitHub release can be archived through Zenodo to obtain a persistent DOI.

## 11. Minimum defensible result

A bounded empirical project can be complete with:

1. a reproducible LFO setup;
2. an explicitly parameterized generic mediator;
3. a validated diagnostic/replay bank;
4. a pilot;
5. one properly controlled empirical study;
6. analyzable results and a documented analysis;
7. a final research report or paper-style write-up.

Personalization, a full longitudinal extension, live-frontier replication, and public archival release are valuable follow-ons where time, recruitment, ethics, and pilot results support them.

## Selected background

- Rastogi et al. (2022), *Deciding Fast and Slow: The Role of Cognitive Biases in AI-assisted Decision-making*.
- Schemmer et al. (2023), *Appropriate Reliance on AI Advice: Conceptualization and the Effect of Explanations*.
- Sharma et al. (2024), *Towards Understanding Sycophancy in Language Models*.
- Glickman & Sharot (2025), *How human–AI feedback loops alter human perceptual, emotional and social judgements*.
- Jain et al. (2026), *Interaction Context Often Increases Sycophancy in LLMs*.
- Dubois et al. (2026), *Ask don't tell: Reducing sycophancy in large language models*.

## Related documents

- [Generic Epistemic Mediator](GENERIC_EPISTEMIC_MEDIATOR.md)
- [L4 recording and manual analysis](L4_RECORDING_MANUAL_ANALYSIS.md)
- [LFO architecture](ARCHITECTURE.md)
- [Roadmap](ROADMAP.md)
