# Balancing the Loop

## Testing a Local Epistemic Balancer in Human–Frontier-LLM Interaction

**Status:** research concept / protocol under development

This research track uses Local Frontier Orchestrator as an experimental platform for studying reciprocal bias in Human–LLM interaction.

The core problem is not only that humans can be biased, or that language models can be biased. The more interesting system-level problem is that the two can become **coupled**.

A user may approach the system with an initial belief, framing, confidence level, or preference for confirming evidence. A conversational model may in turn exhibit sycophancy, agreement bias, sensitivity to framing, or fluent overconfidence. Repeated interaction can therefore create a feedback loop in which neither side is an independent correction of the other.

The working title for this research program is **Balancing the Loop**.

## 1. Research aim

To test whether an auditable local AI mediator can reduce reciprocal amplification of human-side and model-side biases while preserving the practical benefit of high-capability frontier-model assistance.

The mediator is not intended to be a more intelligent replacement for the frontier model. Its role is **metacognitive and regulatory**.

```text
Human prior
   |
   v
Local mediator
   |
   v
Frontier LLM
   |
   v
Local evaluation
   |
   v
Human final judgement
```

Longer-term versions can adapt from interaction traces, but personalization should initially remain explicit and inspectable. The orchestration and persistence substrate now exists as an empirical prototype; what remains experimental is the epistemic-balancing policy and the behavioural personalization layer.

## 2. Biases of interest

### Human-side

Initial work focuses on observable behavioural tendencies such as:

- confirmation / myside bias;
- automation bias and inappropriate reliance;
- confidence miscalibration;
- anchoring or framing sensitivity;
- failure to verify when verification would be useful.

### Model-side

The main conversational tendencies of interest include:

- sycophancy / agreement bias;
- mirroring of the user's framing;
- unsupported certainty;
- omission of plausible alternatives or counter-evidence;
- over-coherent answers that make an uncertain problem appear settled.

The project does not assume that human and model biases share the same psychological mechanism. The relevant object is the **interaction-level behaviour**.

## 3. Local Epistemic Balancer

A future bias-aware mode may turn the local layer into a Local Epistemic Balancer (LEB).

Possible functions include:

### Before the frontier call

- detect leading phrasing or an expressed prior;
- distinguish a question from a request for affirmation;
- neutralize framing where experimentally appropriate;
- ask the frontier model for counter-evidence or alternative hypotheses;
- decide whether external verification is warranted.

### After the frontier call

- detect agreement/sycophancy risk;
- preserve uncertainty and caveats;
- flag unsupported confidence;
- separate sourced evidence from interpretation;
- request critique or verification in future multi-pass variants;
- present disagreement without optimizing for user satisfaction.

### User model

Personalization should initially model **metacognitive behaviour**, not belief content.

Candidate variables:

- tendency to follow AI when it agrees;
- tendency to follow AI when it disagrees;
- verification propensity;
- confidence calibration;
- baseline task accuracy;
- response to correction;
- domain-level performance.

The mediator should **not** learn “what the user believes” as a preference that must be preserved. That would risk turning personalization into a self-reinforcing confirmation system.

Persistent conversational memory is therefore distinct from the experimental user model. Conversation state may preserve task goals, corrections, constraints, and interaction continuity, while inferred bias or metacognitive labels should remain separate research variables rather than being fed back into active conversational memory by default.

## 4. L4 research-analysis layer

The planned LFO **L4** layer gives the Bias Balancer a place to persist explicit research interpretations without contaminating operational factual memory.

The intended boundary is:

```text
L0  raw interaction evidence
L1  conversational working memory
L2  structured factual state
L3  retrieval & resolution
L4  research / epistemic analysis output
```

L4 is primarily an **output layer**. L3 may retrieve analogous historical events, relevant L2 state, and external conceptual context; L4 records the resulting analytical observation, intervention, outcome or longitudinal hypothesis.

The DokuWiki search subsystem can be useful during this analysis through an L3 read-only adapter. For example, it may retrieve methodological notes, bias definitions, prior experimental decisions or related project context. A retrieved wiki segment is context/evidence for analysis, not itself a bias label.

Bias should be represented at the interaction-event level. Prefer a reified observation such as:

```text
BiasObservation
  event_ref = turn:918
  actor = human
  bias_type = confirmation_bias
  confidence = 0.64
  status = hypothesis
  evidence = [...]
```

rather than a permanent relationship such as:

```text
User HAS_BIAS ConfirmationBias
```

The same structure can represent model-side observations such as possible sycophancy.

For intervention research, the important chain is:

```text
event
  -> observation
  -> intervention
  -> outcome
```

Repeated observations may later support a LongitudinalHypothesis, but such a hypothesis remains conditional, provenance-linked and revisable. It must not be silently promoted to L2 factual state or automatically injected into ordinary conversational memory.

See [L4_RESEARCH_ANALYSIS.md](L4_RESEARCH_ANALYSIS.md).

## 5. Primary research questions

1. Does a local epistemic mediator improve **appropriate reliance** on frontier-model advice compared with direct interaction?
2. Does personalization based on observable metacognitive behaviour improve outcomes beyond a generic non-personalized mediator?
3. Does repeated direct interaction with systematically biased or sycophantic AI shift later unaided human judgements?
4. Under what conditions does personalization itself become self-reinforcing?
5. Can a mediator reduce model-side sycophancy while preserving useful adaptation to genuine individual differences in knowledge and calibration?

## 6. Experimental comparison

A controlled longitudinal design can compare three conditions:

### A. Direct frontier

```text
User <-> Frontier LLM
```

No local epistemic intervention.

### B. Generic balancer

```text
User <-> Local mediator <-> Frontier LLM
```

A static, non-personalized policy can neutralize leading prompts, request counter-evidence, preserve uncertainty, and encourage verification under predefined triggers.

### C. Personalized balancer

```text
User <-> Adaptive local mediator <-> Frontier LLM
```

The same policy family is used, but intervention thresholds can adapt from prior reliance, verification, calibration, and task performance.

A separate offline stress test can compare this epistemic personalization with a deliberately preference-oriented policy optimized for agreement or short-term satisfaction. The latter is useful as a test of **confirmation-machine failure**, not as the desired deployed behaviour.

## 7. Outcome concept: appropriate reliance

The objective is not to maximize trust in AI or distrust of AI.

A useful mediator should improve the user's ability to discriminate between:

- AI advice that should be followed;
- AI advice that should be questioned or rejected.

Relevant behavioural measures can include:

- independent judgement before AI exposure;
- confidence before AI exposure;
- whether verification is requested;
- final judgement;
- final confidence;
- uptake of correct AI advice;
- resistance to incorrect AI advice;
- persistence of AI-induced shifts on later unaided tasks.

## 8. Why Local Frontier Orchestrator is a suitable platform

The architecture already contains the required intervention points:

```text
user
  |
local pre-processing / routing
  |
frontier model
  |
local post-processing / critique
  |
user
```

It also provides persistent conversational continuity and append-only interaction traces while keeping compact working memory separate from the exact historical record.

It also separates:

- local policy from frontier capability;
- deterministic gates from model judgement;
- sourced frontier evidence from local interpretation;
- machine-specific runtime profiles from common orchestration logic.

This makes it possible to alter mediator policy without retraining the frontier model.

## 9. Confirmation-machine risk

Debiasing is not automatically neutral.

A personalized correction system can itself develop a **second-order bias** if it increasingly learns the user's preferred framing, rhetorical style, or preferred conclusions.

The project therefore treats the following as a first-class failure mode:

```text
user bias
   -> personalized mediator adapts to user preference
   -> frontier output is selectively framed
   -> user experiences repeated confirmation
   -> mediator receives more confirming interaction data
```

For this reason, personalization should initially remain interpretable and parameterized rather than hidden in weight-level fine-tuning.

## 10. Study boundaries

The first controlled study should prefer tasks with independent ground truth or defensible scoring criteria, for example:

- probabilistic reasoning;
- evidence evaluation;
- source comparison;
- causal inference;
- quantitative estimation;
- short diagnostic reasoning tasks.

Initial work should avoid making political persuasion, clinical advice, identity-sensitive persuasion, or broad personality profiling the primary experimental domain.

## 11. Research status

This document is intentionally shorter than the full study design. The project is not yet a preregistered experiment and the implementation does not yet claim to provide validated debiasing.

The current prototype already provides auditable policy/config separation, persistent conversational state, raw interaction traces, local/frontier intervention points, and restart continuity across heterogeneous local hardware. The next engineering step is to validate exact historical retrieval and then freeze the behavioural interface needed for controlled mediator experiments.

Only after that should specific bias-balancing policies be frozen for controlled human-subject research.

## Selected background

- Rastogi et al. (2022), *Deciding Fast and Slow: The Role of Cognitive Biases in AI-assisted Decision-making*.
- Sharma et al. (2023), *Towards Understanding Sycophancy in Language Models*.
- Glickman & Sharot (2025), *How human–AI feedback loops alter human perceptual, emotional and social judgements*.
- Jain et al. (2026), *Interaction Context Often Increases Sycophancy in LLMs*.
- Dubois et al. (2026), *Ask don't tell: Reducing sycophancy in large language models*.
