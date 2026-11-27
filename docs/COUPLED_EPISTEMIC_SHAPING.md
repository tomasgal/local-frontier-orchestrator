# Coupled Epistemic Shaping (CES)

**Status:** living research and design document for G2, LFO v9.7.x. Initial draft: 2026-11-27. No strategy in this document is automatically enabled or accepted for production.

Related: [G2 epistemic controller](G2_EPISTEMIC_CONTROLLER_V97.md), [Human–AI Bias Balancer](HUMAN_AI_BIAS_BALANCER.md), [G2 research](../research/g2/README.md), [Pilot 09](../research/g2/COMPILER09.md), [Pilot 10](../research/g2/SEMANTIC10.md). Immutable v9.6.8 and the accepted L2/L3 contracts remain unchanged.

## 1. Purpose and scope

The unit of analysis is a distributed Human–AI cognitive complex, not a diagnosis of a user or an assertion that an LLM has human cognitive mechanisms. CES proposes a context-dependent joint control model for six epistemic functions. They are working functional coordinates, not validated independent psychometric dimensions, not necessarily exhaustive, and not a set of quantities to maximize independently.

The motivation is interference between interventions: an intervention that improves one function may improve, impair, or leave unchanged another function. Its direction can reverse with task, evidence, prior commitment, presentation, or time. Correcting a false claim can increase confidence in unchecked claims; expanding evidence can produce false balance; greater scrutiny of AI advice can improve rejection of bad advice or induce rejection of good advice. Such mechanisms motivate the architecture; they do not establish that CES works.

The objective is a proportionate, evidence-sensitive configuration that preserves the user's legitimate task, agency and preferences, while reducing material epistemic errors. No universal ideal shape, aggregate bias score, mandatory equalization of coordinates, or unsupported numeric coupling matrix is assumed.

## 2. Functional coordinates

| ID | Function | Operational question | Example failure |
|---|---|---|---|
| E1 | Integrity | Are claims, sources, provenance and runtime actions represented faithfully? | False claim of web verification; lost source attribution. |
| E2 | Selection | Is material evidence selected and weighted appropriately for the task? | Selective omission; irrelevant counterevidence; false balance. |
| E3 | Inference | Do conclusions follow from the evidence and assumptions? | Causal leap; metric confusion; unsupported generalization. |
| E4 | Independence | Is judgment appropriately independent of undue pressure while responsive to warranted advice? | Sycophancy, anchoring, uncritical reliance, reflexive contrarianism. |
| E5 | Calibration | Does expressed confidence match the available evidence and reliability? | Unwarranted certainty, excessive skepticism, uncalibrated trust. |
| E6 | Revision | Is a warranted correction incorporated without losing valid content or history? | Persistence of a corrected claim; unnecessary revision of a correct answer. |

For observable measurements, define the direction of improvement for each endpoint in advance. These coordinates describe quality, not intensity of skepticism, amount of text, detector sensitivity or frequency of interventions. E4 does not mean isolation; E2 does not mean maximizing the number of sources; E6 does not mean maximizing change. E1 runtime provenance invariants are not tradeable quality preferences.

## 3. Formal working model

Let x_t be a six-component latent or partially observed epistemic state at turn t; y_t the observed task-specific endpoints; c_t context; u_t a vector of intervention actions/doses (not necessarily six); and w_t unobserved variation.

    x_(t+1) = F(x_t, u_t, c_t, w_t)
    y_t = H(x_t, c_t) + measurement_error

Local interventional response, where meaningful:

    J_ij(x,c,u) = partial E[y_i | do(u), x,c] / partial u_j

In discrete experiments use randomized finite contrasts rather than pretend to estimate derivatives. Positive, negative, zero and context-reversing effects are all admissible. A pair of effects may be asymmetric, delayed, saturating, non-monotone, or contingent on another action. An unmeasured edge is UNKNOWN, not zero. Correlation between scores is not causal evidence of a coupling. The intervention space and measurement space need not have the same dimension.

A signed conditional graph is the initial representation. A node is a functional endpoint or a well-defined action; distinguish action-to-outcome edges from speculative state-to-state relationships. Every proposed edge has a mechanism, a moderator, a source, a counterexample and a test. Do not assign arbitrary coefficients or infer a geometric metric from a radar plot. A 2D radar figure is only an illustration of a six-component state; polygon area is not epistemic quality.

The controller should choose a minimally burdensome action or action bundle satisfying hard constraints and context-specific acceptance criteria. Use Pareto comparisons (quality, preservation, latency, token and human effort cost) when tradeoffs cannot be justified on a common scale. Never compensate a known provenance violation by improving another dimension. Retain the option of abstention, original answer, explicit qualification, or user clarification. Unknown intent is legitimate: intent is nullable and not a user trait.

## 4. Evidence-grounded shapes and conditional couplings

The labels below describe temporary interaction regimes, not personality types, diagnoses or measured six-dimensional coordinates. They are hypotheses for LFO. Citations support the stated mechanism in the original setting, not a numerical CES deformation.

| Shape / regime | Real-world evidence and mechanism | Candidate shaping response | Counterforce / boundary |
|---|---|---|---|
| CES-S01: Confirmation / defensive justification loop | Accountability can promote flexible scrutiny, audience conformity, or defense of a prior commitment depending on social conditions [R1]. LLM agreement with user views is documented [R2]. | E4 scrutiny coupled to E2 material counterevidence, E3 evaluation and E5 qualified confidence. | Do not oppose a correct user conclusion; justification alone can reinforce the anchor. |
| CES-S02: False balance | Presenting conflicting expert comments can distort perceived consensus despite aggregate expert counts [R3]. | Couple evidence broadening to evidence strength/weight and calibration (E2/E3/E5). | Equal airtime for unequally supported claims can worsen inference and confidence calibration. No mandatory counterargument quota. |
| CES-S03: Social convergence / productive information exchange | Sharing estimates reduced diversity and increased confidence without improved collective error in one experiment [R4]; decentralized information exchange improved collective accuracy in another [R5]. | Preserve independently formed judgments when informative; integrate new evidence according to its provenance and quality. | Information sharing can improve or impair accuracy; agreement is neither independent confirmation nor necessarily an error. |
| CES-S04: Overreliance / underreliance | Cognitive forcing reduced overreliance but reduced subjective preference for the strongest interventions [R6]; algorithm aversion can cause rejection of superior forecasts after observed errors [R7]. | Couple E4 to E5, and test appropriate acceptance of good advice and rejection of bad advice separately. | Scrutiny can increase user effort or inappropriate rejection; there is no universal skepticism optimum. |
| CES-S05: Warning-induced implied truth | Selective misinformation warnings can increase perceived accuracy of unlabelled headlines [R8]. | Couple E1 warnings to E5 coverage/status communication: distinguish contradicted, verified within scope, unchecked and abstained. | Silence must not be interpreted as validation. Additional warnings may also impose effort. |
| CES-S06: Reconstructive revision | Correct alternative explanations can reduce continued influence of misinformation relative to retraction alone [R9]. | Couple E1 correction to E3 reconstruction and E6 revision when the task requires a coherent explanation. | A plausible but invented alternative creates new integrity/inference errors; unresolved explanations may need to stay unresolved. |
| CES-S07: Task-dependent human–AI complementarity | A meta-analysis of 106 human-participant experiments found heterogeneous human–AI combination performance, on average below the stronger solo performer [R10]. | Select strategies by task and compare human-only, AI-only and mediated human–AI where appropriate. | Improvement over unaided human performance alone is not proof of synergy. |
| CES-S08: Memory-mediated amplification (project hypothesis) | Continued influence research motivates testing persistence after correction [R9, R11]; LFO memory-specific effect is unestablished. | Couple L1/L2 provenance and epistemic scope to relevant current evidence and revision. | Memory is not independent confirmation; repeated or corrected content must retain its scope. Projection can also remove useful information or distort intent. |

### Signed candidate relationships

These are action-to-outcome hypotheses, not a fitted matrix. A plus or minus below denotes an expected direction in the stated situation only.

| Action | Candidate beneficial response | Candidate opposing response / moderator |
|---|---|---|
| Broaden evidence selection | +E2/+E3 when material independent evidence is recovered | -E3/-E5 if unreliable claims receive equal weight or relevant context is displaced |
| Request independent reconsideration | +E4/+E6 when anchored to a false answer | -E3/-E5 if correct advice is discarded; higher cost |
| Require detailed justification | +E3 under open inquiry | -E4/-E2 under known audience preference or prior commitment; defensive rationalization |
| Show a targeted warning | +E1 for the identified defect | -E5 for unchecked content via implied truth; possible reliance shift |
| Correct a claim and reconstruct explanation | +E3/+E6 when supported | -E1/-E3 if reconstruction invents a cause; preserve uncertainty |
| Increase revision frequency | +E6 when new evidence warrants correction | -E1/-E3 if correct content is overwritten, -E5 if needless doubt is induced |
| Integrate prior context | +E2/+E6 for relevant correction continuity | -E4/-E5 if repetition/consensus is mistaken for independent support |

No obligation to activate every neighbor of an intervention. Explicitly exclude cascading closure through all nodes. Coupling is conditional and bounded by the specific task, evidence, risks and cost.

## 5. Mandatory source and methodology gate

**No CES shaping strategy, new coupling, changed sign, threshold, weight, propagation rule, or default may be promoted on geometric intuition, an LLM's recommendation, a single development fixture, or a loosely analogous citation alone.**

Each proposed change MUST have:

1. A traceable, non-obscure scholarly or standards-based foundation: a recognized peer-reviewed primary study, a high-quality systematic review/meta-analysis, or an established authoritative methods text (e.g. NIST/SEMATECH). Prefer stable DOI, publisher, academic repository or official institutional source, with exact edition/version and section/page/experiment locator. Author prestige or citation count alone is insufficient. Verify the actual text and method before acceptance; a search snippet or AI-generated paper summary is not the final evidence.
2. A documented rationale linking the source's manipulation, population, outcome, mechanism and boundaries to the precise LFO intervention. Explicitly distinguish direct evidence, transferable analogy, and novel project hypothesis. An authoritative methodology can justify how to test an original strategy; it does not automatically establish its mechanism or efficacy. Where the source supports only an analogy, keep the strategy experimental.
3. An established experimental methodology that can distinguish the proposed effect from confounds and measure countereffects. Prefer randomized/block-matched factorial designs with preregistered endpoints, interaction contrasts, uncertainty and failure/abstention reporting [M1–M3]. Specify scale, comparison, context moderators and smallest practically useful effect before examining confirmatory results.
4. Evidence of preservation of legitimate preferences, explicitly hypothetical assumptions, fiction, quotations, correct agreement and scope. No inference of hidden user intention or psychological state. Hard integrity and provenance constraints must pass; any new critical error must be examined, not averaged away.
5. A versioned acceptance record: candidate ID, exact implementation SHA, model digest/profile, corpus hash, study design, raw evidence references, results, limitations, acceptance decision, rollback condition and applicable contexts. Inconclusive or negative results remain recorded. Default behavior stays unchanged until explicit promotion.

If a credible mechanistic source or adequate methodology is not yet available, register the proposal as HYPOTHESIS / SOURCE_REQUIRED. It may be explored in isolation but must not be treated as justified production shaping. For each new strategy, preserve this gate even when versioning through 9.7.x.

## 6. Implementation strategies and boundaries

* **Input shaping:** semantic compiler separates task, evidence, hypotheses, scope, preferences and assumptions; intent optional. Annotations alone do not guarantee that the main model disregards misleading directives. Keep exact source evidence and original L0; never promote an inferred stance to a fact. No general regex taxonomy.
* **Context shaping:** read-side epistemic projection of selected L1/L2 and, later, L3 content. Keep source reference, modality, verification and correction status when available. Do not silently rewrite L1/L2, change durable write authority, or suppress material evidence. Source integrity must survive both projection and fallback.
* **Inference shaping:** compose a bounded bundle of task-specific epistemic obligations in a single request where possible. No mandatory extra model call per axis; no global reduction of generation or context budget merely for shaping.
* **Output shaping:** use authoritative runtime metadata for claims about actual tool execution; qualify unsupported claims, patch exact local defects when appropriate, or re-solve independently when a full reconstruction is necessary. A structurally valid patch is not necessarily semantically valid.
* **Interaction shaping:** explicit warnings or requests for human reflection only when justified; test appropriate reliance and possible implied-truth effects. OBSERVE does not imply a verified response. No hidden personalization or persistent user bias profile.

Keep current modes and policies (OFF/OBSERVE/ADVISE/INTERVENE; MINIMAL/STANDARD/CASCADE). CES is an experimental intervention-selection concept, not a fourth policy or immediate configuration migration. Default OBSERVE; existing detector sensitivity and intensity of intervention are separate. L0 stays authoritative for original user and assistant text; record derived request representation, action, source spans, status and outcome separately. Use the existing cascade bounds; do not silently add calls.

## 7. Candidate strategy registry — v9.7.x

This is an append-only conceptual register with stable identifiers and explicit version/status updates. No production version is assigned until a candidate is accepted. Existing experiment protocols remain authoritative for their actual arms and fixtures.

| ID | Candidate strategy | Initial empirical/methodological basis | Intended functions and countereffects | Status / next discriminating test |
|---|---|---|---|---|
| CES-C01 | Semantic transformation of current prompt | R1, R2; P09/P10 internal screening | E4/E2/E3/E5; risk of intent/scope distortion and loss of evidence | EXPERIMENTAL: P09 manual transform promising; P10 exact tagging weak. Test matched raw, oracle transform, automated transform; null intent, exact evidence, controls. |
| CES-C02 | Read-only L1/L2 epistemic context projection | R9, R11; M1/M2 | E1/E2/E5/E6; possible loss of valid context or unnecessary skepticism | HYPOTHESIS: fixed-memory 2x2 current-prompt transform x memory projection, including corrected, uncertain and accurate states. |
| CES-C03 | Evidence diversity + evidential weighting | R3–R5; M1/M2 | E2/E3/E5; false balance or excessive filtering | HYPOTHESIS: 2x2 diversity x weighting, high-consensus versus genuinely disputed cases. |
| CES-C04 | Appropriate independence + calibration | R6/R7/R12; M1/M2 | E4/E5; overreliance versus underreliance, cognitive effort | HYPOTHESIS: 2x2 independent judgment x reliability information; correct/incorrect AI advice; human phase required. |
| CES-C05 | Runtime-owned provenance and status visibility | R8; existing LFO provenance contract | E1/E5; implied truth and false confidence in unchecked content | HYPOTHESIS for shaping effects: compare warnings-only versus explicit checked/unchecked statuses. Deterministic reporting is an integrity requirement, not proof of verified claims. |
| CES-C06 | Evidence-grounded reconstructive revision | R9/R11; P08/P09 | E1/E3/E6; new invented explanation or unnecessary rewrite | EXPERIMENTAL: compare targeted correction, independent re-solve, and evidence-grounded reconstruction with clean/noisy controls. |
| CES-C07 | Bounded local epistemic patch | P08 internal evidence; M1/M2; specific external mechanistic rationale still required | E1/E6; over-large replacements, unresolved global inference, new errors | EXPERIMENTAL / SOURCE_REQUIRED for production shaping: assess preservation, semantic repair, costs and escalation. |
| CES-C08 | Contextual selection of coupled action bundles | R10; M1–M3 | All; intervention overload and antagonistic effects | HYPOTHESIS: compare single actions, bundles and cost-matched controls before introducing a policy. |

For every future entry include: ID and version; date; hypothesis; sources with exact locators and evidence grade; context/eligibility; independent variables; endpoint and expected signed effects; protected constraints; likely adverse effects; preregistered contrast and decision criteria; compute/human costs; provenance; results and status. Status vocabulary: HYPOTHESIS, SOURCE_REQUIRED, EXPERIMENTAL, INCONCLUSIVE, REJECTED, ACCEPTED_FOR_BOUNDED_SCOPE, PROMOTED. Never delete an adverse or rejected result to improve the appearance of progress.

## 8. Experimental methodology

Start with pairwise 2x2 factorial tests rather than an unjustified six-by-six matrix. For two binary actions A and B, let m_ab be the mean of a predeclared higher-is-better endpoint in a specified context. The additive interaction contrast is:

    I_AB = m_11 - m_10 - m_01 + m_00

Positive means superadditivity on that scale; negative means subadditivity, not necessarily net harm. A genuine adverse effect is a deterioration against an appropriate comparator (e.g. m_11 < m_10). Test direction reversal by stratifying/manipulating the hypothesized moderator; do not infer it from different uncontrolled pilot runs. For binary endpoints choose and report the risk-difference scale or a predeclared alternative, since interaction depends on scale. Report uncertainty, raw denominators, both marginal and conditional effects. A negative interaction can coexist with beneficial main effects. For continuous dose-response questions add levels only after basic effects are supported.

Use matched prompts and frozen responses for engineering screens; randomize/counterbalance arms and block by case, model, language and seed where appropriate. Replicate with multiple seeds and independent held-out cases; treat repeated observations within prompts/participants as clustered, not independent. Predefine case exclusions, critical-error rubric, multiple-comparison handling, sample-size/power and meaningful improvement/noninferiority margins for confirmatory studies. Blind raters to arm; report inter-rater agreement and adjudication. Include cost-matched and representation-matched comparators where feasible. Record failed model responses and abstentions. Consider fractional factorial designs only with known alias structure and explicit assumptions [M2], not as an excuse to conflate interactions.

Suggested initial tests (not yet run):

| Test | Factor A | Factor B | Context moderator / guard | Outcomes |
|---|---|---|---|---|
| T-CES01 | Material alternative evidence | Evidential weighting | Strong consensus vs genuinely ambiguous evidence | Evidence completeness, weighted inference, uncertainty |
| T-CES02 | Independent reconsideration | Calibrated reliability cues | Advice correctness and relative competence | Correct acceptance, correct rejection, effort |
| T-CES03 | Targeted correction | Supported alternative explanation | Correct vs incorrect draft; explanation available vs absent | Critical-error repair, preserved valid content, new errors |
| T-CES04 | Warning on detected error | Explicit unchecked/checked status | Label coverage, true and false unlabelled claims | Human belief accuracy, inappropriate trust |
| T-CES05 | Current prompt transformation | L1/L2 context projection | Hypothesis, stale fact, explicit correction, legitimate preference | Fidelity, inference, persistence over subsequent turns |

Separate detection accuracy, conditional correction efficacy, and end-to-end efficacy. Engineering experiments on model responses cannot establish human cognitive outcomes. The human phase must use appropriate reliance and decision quality measures, and, for claims of synergy, compare against both human-only and AI-only [R10/R12]. Respect consent and research ethics. Report computational overhead, latency distribution (including actual interleaved model loads), input/output tokens, extra calls, user effort and preservation of correct responses separately.

## 9. Source anchors and limitations

Initial literature was scoped through SciSpace and primary/institutional bibliographic records. These established sources motivate the candidate mechanisms; the entire CES theory is novel and unvalidated. This initial draft records abstract-level findings and methods anchors, not a completed full-text systematic review. Before accepting a particular strategy, record the exact supporting method and result locator from the source text and its transfer boundary.

### Methodology anchors (normative engineering process)

- **[M1]** NIST/SEMATECH, *e-Handbook of Statistical Methods*, [5.3.3.3 Full factorial designs](https://itl.nist.gov/div898/handbook/pri/section3/pri333.htm). Use all combinations to separate factors and interaction effects.
- **[M2]** NIST/SEMATECH, *e-Handbook of Statistical Methods*, [5.4.3 How to model DOE data](https://itl.nist.gov/div898/handbook/pri/section4/pri43.htm). Specify model from design and objectives; full factorial interaction terms and fractional factorial aliasing.
- **[M3]** NIST/SEMATECH, *e-Handbook of Statistical Methods*, [5.5.9.4 Interaction effects matrix plot](https://itl.nist.gov/div898/handbook/pri/section5/pri594.htm). Interpret interactions with explicit aliasing limits. These sources justify the experimental method, not the CES functional taxonomy.

### Empirical foundations

- **[R1]** Tetlock, P. E., Skitka, L. & Boettger, R. (1989). Social and cognitive strategies for coping with accountability: conformity, complexity, and bolstering. *Journal of Personality and Social Psychology*, 57(4), 632–640. [PubMed](https://pubmed.ncbi.nlm.nih.gov/2795435/). Abstract: three conditional responses to accountability. Human social judgment; transfer to an LLM is a hypothesis.
- **[R2]** Sharma et al. (2024). Towards Understanding Sycophancy in Language Models. ICLR. [OpenReview](https://openreview.net/forum?id=tvhaxkMKAn). Experiments on model agreement with user views; not evidence of human belief change.
- **[R3]** Koehler, D. J. (2016). Can journalistic "false balance" distort public perception of consensus in expert opinion? *Journal of Experimental Psychology: Applied*. [PubMed](https://pubmed.ncbi.nlm.nih.gov/26752513/). Abstract: opposing expert comments vs aggregate count alone; perception of consensus, not direct LLM performance.
- **[R4]** Lorenz, J., Rauhut, H., Schweitzer, F. & Helbing, D. (2011). How social influence can undermine the wisdom of crowd effect. *PNAS*. [PubMed](https://pubmed.ncbi.nlm.nih.gov/21576485/). Abstract: repeated estimates with social information, convergence and confidence without corresponding accuracy improvement.
- **[R5]** Becker, J., Brackbill, D. & Centola, D. (2017). Network dynamics of social influence in the wisdom of crowds. *PNAS*. [Article record](https://www.jstor.org/stable/26485009). Abstract: network structure moderates the accuracy effect of information exchange. Human group estimation, not directly two-agent conversational inference.
- **[R6]** Buçinca, Z., Malaya, M. B. & Gajos, K. Z. (2021). To Trust or to Think: Cognitive Forcing Functions Can Reduce Overreliance on AI in AI-assisted Decision-making. *Proceedings of the ACM on Human-Computer Interaction*. [DOI](https://doi.org/10.1145/3449287). Abstract: controlled human-participant comparison, N=199; overreliance and subjective evaluation tradeoff.
- **[R7]** Dietvorst, B. J., Simmons, J. P. & Massey, C. (2015). Algorithm aversion: people erroneously avoid algorithms after seeing them err. *Journal of Experimental Psychology: General*. [Paper record](https://scispace.com/papers/algorithm-aversion-people-erroneously-avoid-algorithms-after-3tn58idk12). Forecasting experiments; avoid assuming all algorithm rejection is irrational.
- **[R8]** Pennycook, G., Bear, A., Collins, E. T. & Rand, D. G. (2020). The implied truth effect: Attaching warnings to a subset of fake news headlines increases perceived accuracy of headlines without warnings. *Management Science*, 66(11), 4944–4957. [DOI](https://doi.org/10.1287/mnsc.2019.3478). Studies 1–2: warning coverage and perceived accuracy/sharing; not evidence about the LFO UI yet.
- **[R9]** Guo, S., Chen, D. & Hu, X. (2025). Providing an alternative explanation improves misinformation rejection and alters event-related potentials during veracity judgements. *Brain and Cognition*. [DOI](https://doi.org/10.1016/j.bandc.2025.106290). Abstract: retraction-only vs retraction plus correct alternative cause, ERP and veracity outcomes. Do not infer neural mechanisms for LLMs.
- **[R10]** Vaccaro, M., Almaatouq, A. & Malone, T. W. (2024). When combinations of humans and AI are useful: A systematic review and meta-analysis. *Nature Human Behaviour*, 8, 2293–2303. [DOI](https://doi.org/10.1038/s41562-024-02024-1). Preregistered meta-analysis, 106 experiments, 370 effects; task-dependent performance and comparison to stronger solo performer.
- **[R11]** Ecker, U. K. H. et al. (2022). The psychological drivers of misinformation belief and its resistance to correction. *Nature Reviews Psychology*. [Paper record](https://scispace.com/papers/the-psychological-drivers-of-misinformation-belief-and-its-2x2d8re6). Review of continued influence and correction mechanisms; not direct evidence of LFO memory behavior.
- **[R12]** Schemmer, M. et al. Should I Follow AI-based Advice? Measuring Appropriate Reliance in Human-AI Decision-Making. [Preprint record (2022)](https://scispace.com/papers/should-i-follow-ai-based-advice-measuring-appropriate-3b67a2dk). Two-dimensional appropriate reliance measurement; use acceptance of correct AI advice and retention of correct human judgment as distinct outcomes. Verify publication version and exact denominator definitions before human study.

## 10. Decision log

- 2026-11-27: Establish CES as a living hypothesis and strategy registry on v9.7-dev. Retain E1–E6 as functional coordinates; distinguish quality, sensitivity, intervention action and observed response. Permit signed and context-reversing couplings. No coefficient matrix, production integration, new defaults or accepted geometric measurement. Require substantive scholarly support and recognized methodology before promoting any shaping change. Future strategies will be added to this document with versioned evidence and decisions.
