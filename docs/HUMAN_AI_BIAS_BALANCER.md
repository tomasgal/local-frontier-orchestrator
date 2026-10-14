# Balancing the Loop

## Testing a Local Epistemic Balancer in Human–Frontier-LLM Interaction

**Status:** research concept / protocol under development; the supporting LFO L2-L4 substrate is implemented/frozen far enough to host bounded research prototypes, while validated debiasing efficacy remains an open research question.

For the narrowed **generic, non-personalized mediation** workstream focused on operationalization, bias magnitude, benchmark design, and a bounded engineering prototype, see [GENERIC_EPISTEMIC_MEDIATOR.md](GENERIC_EPISTEMIC_MEDIATOR.md).

**Reference implementation:** Local Frontier Orchestrator **v9.6.2** (Zenodo software archive DOI [`10.5281/zenodo.23373391`](https://doi.org/10.5281/zenodo.23373391)). The software archive establishes a reproducible implementation boundary; it is not itself evidence that the proposed mediator reduces bias.

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

## 4. L4 research-analysis substrate

LFO now has an implemented L4 substrate for this research rather than only a
planned layer. The operational/frozen boundary is:

```text
L0  raw interaction evidence
L1  conversational working memory
L2  structured factual state
L3  retrieval & resolution
L4  epistemic observations / bounded analytics
```

The current canonical L4 record is an event-scoped `EpistemicObservation`
stored in SurrealDB and linked back to exact L0 provenance. Observations remain
annotations, not external-world facts or permanent user traits.

v9.6.2 preserves the v9.6.1 operational behavior: only a conservative subset of USER-side signals
after L0 persistence and exposes explicit `/analyze` A1/A2 reads. The broader
D1 detector remains offline; P1/P2 response intervention remains OFF.

For the research program, the important causal/evaluation chain remains:

```text
event
  -> observation
  -> intervention
  -> outcome
```

A later longitudinal hypothesis must remain conditional, provenance-linked and
revisable. It must not be silently promoted to L2 factual state or automatically
injected into ordinary conversational memory.

L3 or external adapters such as DokuWiki may supply evidence/context to an
analysis, but retrieved context is not itself a bias label. L3 retrieval
relevance and L4 analytical validity are separate questions.

The generic, non-personalized operationalization is consolidated in
[GENERIC_EPISTEMIC_MEDIATOR.md](GENERIC_EPISTEMIC_MEDIATOR.md); current runtime
details are in
[L4_RECORDING_MANUAL_ANALYSIS.md](L4_RECORDING_MANUAL_ANALYSIS.md).

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

This document is intentionally shorter than the full study design. The project is not yet a preregistered experiment and the implementation does not claim validated debiasing efficacy.

The infrastructure boundary has advanced materially since the original concept note. In the accepted LFO line:

- L2 is frozen at `v9.4-l2-frozen`;
- L3 is frozen at `v9.5-l3-frozen`;
- L4 R1/R2/A1/D1/A2/P1/P2 have frozen evidence boundaries;
- v9.6.2 operationally preserves conservative post-L0 T1 recording of `FRAMING` / `ASYMMETRIC_EVIDENCE_REQUEST` and explicit bounded `/analyze` A1/A2 reads;
- the broader D1 detector remains offline;
- P1/P2 response intervention remains disconnected/OFF.

The next research problem is therefore no longer to invent the L4 substrate. It is to validate a separately versioned **mediator research contract** on top of that substrate without retrofitting the frozen storage/retrieval layers around a desired result.

The immediate research sequence is:

1. define phenomenon-specific **bias magnitude** against explicit reference/control conditions;
2. build paired/counterbalanced direct-versus-framed-versus-mediated benchmarks;
3. evaluate a generic, non-personalized mediator first;
4. measure false-intervention rate, appropriate reliance, evidence preservation, distortion, latency and model-call overhead;
5. treat the existing R1 `confidence` field only as detector metadata, not as a bias-magnitude score;
6. consider adaptive/personalized mediation only after the generic condition has defensible measurement and falsification criteria.

Controlled human-subject and personalized-mediation studies should be frozen only after these operational definitions, benchmark conditions and intervention policies are stable enough to support preregistration or an equivalent protocol.

## Selected background

- Rastogi et al. (2022), *Deciding Fast and Slow: The Role of Cognitive Biases in AI-assisted Decision-making*.
- Sharma et al. (2024), *Towards Understanding Sycophancy in Language Models*.
- Schemmer et al. (2023), *Appropriate Reliance on AI Advice: Conceptualization and the Effect of Explanations*.
- Glickman & Sharot (2025), *How human–AI feedback loops alter human perceptual, emotional and social judgements*.
- Jain et al. (2026), *Interaction Context Often Increases Sycophancy in LLMs*.
- Dubois et al. (2026), *Ask don't tell: Reducing sycophancy in large language models*.
