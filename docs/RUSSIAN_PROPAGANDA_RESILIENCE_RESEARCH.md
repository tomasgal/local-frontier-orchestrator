# Auditing Russian Propaganda Susceptibility with LFO

## A proposed benchmark for factual accuracy, framing, source manipulation, and local mediation

**Status:** possible research / protocol proposal; not implemented or evaluated.

**Proposal date:** 2026-10-18.

**Reference implementation:** Local Frontier Orchestrator v9.6.2.

**Relationship:** a domain-specific, non-personalized evaluation track alongside
[Balancing the Loop](HUMAN_AI_BIAS_BALANCER.md) and the
[Generic Epistemic Mediator](GENERIC_EPISTEMIC_MEDIATOR.md).

This proposal describes how LFO could support a controlled audit of whether
models reproduce Russian propaganda narratives, how prompting and supplied
evidence affect that behavior, and whether local mediation improves the result.
It proposes an evaluation layer above the existing platform. It adds no runtime
feature, benchmark result, detector-accuracy claim, or release requirement.

## 1. Research question and contribution

The main question is:

> Under what conditions do local and frontier models accept unsupported or false
> claims associated with Russian influence operations, and how does LFO's local
> synthesis preserve, correct, or amplify the resulting errors?

The unit of analysis is an observable response to a versioned claim and evidence
condition. The audit evaluates factual and evidential behavior; political
agreement with an evaluator is not the reference standard.

The intended contribution has three parts:

- a reproducible, claim-level benchmark separating factual error from source
  citation, framing effects, and justified uncertainty;
- a stage-level account of where errors enter or disappear in the
  LOCAL/FRONTIER/synthesis/FINAL chain;
- a later controlled comparison of an unmediated baseline and a separately
  versioned generic mediator, including corrections that introduce new errors.

The first study is a model/system audit. It does not require human participants,
personalized political profiles, or an experiment in persuading users.

## 2. Evidence boundaries

Different observations support different conclusions:

| Observation | Defensible inference | Stronger inference requiring additional evidence |
| --- | --- | --- |
| A response cites an operation-linked website | That source reached the response | The response endorsed its claim or the model was poisoned during training |
| A response accepts a verified false claim | A factual failure occurred under the tested condition | A particular foreign operation caused the model's existing behavior |
| Randomized exposure to a manipulated evidence bundle increases false-claim acceptance | A causal susceptibility to that supplied context, within the tested apparatus | The same effect occurs at the same rate in ordinary live-web use |
| A base model completes a propaganda text | Evidence compatible with memorization | The model accepts that text as true or systematically favors its author |
| Training on a manipulated corpus changes later responses | A training effect in that controlled experiment | Proof that a deployed commercial model underwent the same process |

This proposal initially tests responses and controlled context exposure. It does
not reconstruct proprietary training datasets, retrain production models, or
attribute a historical training attack from chatbot output alone.

The distinction matters operationally: an influence operation can succeed at the
retrieval/answer layer without changing model weights. Conversely, a model can
know a propaganda text in order to identify or rebut it.

## 3. Motivation and relevant evidence

The following sources motivate different parts of the design. Their percentages
are conditional on different samples and procedures and must not be pooled into
a general prevalence estimate.

| Source | Type and relevance | Boundary to retain |
| --- | --- | --- |
| Demos/CASM, *GEO for Geopolitics* (2026) [1] | Research report: 3,000 API responses concerning material from the Russian Foundation to Battle Injustice; 16.6% met the authors' criteria for furthering the operation's objectives | Primarily retrieval/source manipulation; selected claims, API conditions, and a rubric broader than literal falsehood acceptance |
| DFRLab, *Pravda in the pipeline* (2026) [2] | Technical investigation of Pravda material in Common Crawl and near-verbatim RT text completion by Llama 3.1 405B Base | A crawl archive is not a final training corpus; memorization does not establish endorsement or a directional behavioral effect |
| Waight et al., *State media control influences large language models* (2026) [3] | Peer-reviewed, multi-study work including an additional-pretraining experiment with Chinese state-coordinated media | Supports a training-mediated mechanism; the causal experiment concerns China, not proof of a Russian attack on any particular model |
| Alyukov et al., *LLMs grooming or data voids?* (2025) [4] | Peer-reviewed audit: 416 responses; 5% supported disinformation; data voids offered an alternative explanation | Small, selected sample; the study neither establishes broad compromise nor excludes exploitation of information gaps |
| NewsGuard, Pravda audit (2025) [5] | Investigation of ten chatbots and 450 responses; 33.55% repeated false narratives, with neutral, leading, and malign prompt categories | Prompt selection and scoring affect the denominator; this is not ordinary-use prevalence or isolated evidence of training poisoning |
| Baker and Bengani/Bloomberg, *Russia's Wiki Warfare* (2026) [6] | Original investigative reporting on leaked planning documents describing reference sites and attempts to influence search engines and AI | Evidence concerning intent and infrastructure is distinct from demonstrated completion of the operators' performance targets |

Information gaps and deliberate manipulation are not mutually exclusive
explanations. An operation may benefit from a gap without having created it.
The experiment should manipulate evidence availability explicitly rather than
assigning a cause from the presence of a suspicious citation.

## 4. What the current LFO implementation provides

| Existing component | Reusable role | Current limitation |
| --- | --- | --- |
| L0 conversation and stage-source capture | Link USER, intermediate LOCAL/FRONTIER, synthesis, and FINAL content to a completed turn | Must be enabled and verified; intermediate LOCAL text is cleaned parser input, not a complete transport response or hidden reasoning; aborted turns may not persist |
| Local model through Ollama | Pin model digest, quantization, template, context, generation settings, and runtime for a controlled local reference | Reproducible conditions do not guarantee bit-identical output; the local model is not assumed neutral |
| Authenticated Codex frontier path | Observe frontier output and subsequent local synthesis within the existing one-call-per-turn boundary | Current reference backend is Codex CLI; the captured frontier model identity may be unknown; this is not equivalent to a ChatGPT consumer-interface audit |
| L1/L2/L3 separation | Keep test state distinct from the authoritative interaction record | Persistent state can confound experiments unless each condition is isolated; `/clear` alone is not a validated experimental isolation protocol |
| L4 R1/R2 provenance and explicit annotation | Reuse supported event annotations and source references where appropriate | R1 has a frozen vocabulary/schema; a new domain rubric needs its own versioned contract |
| Operational T1 and `/analyze` | Record narrow USER-side framing/evidence-selection signals and inspect bounded counts | T1 does not score assistant answers or political bias; ABSTAIN is not a clean bill of health; counts and detector `confidence` are not bias magnitude |
| P1/P2 research mechanisms | Inform a later independently evaluated mediation condition | Response intervention is OFF/disconnected in ordinary v9.6.2 runtime; frozen experiments do not establish efficacy for this domain |

Implementation references:
[L0 stage capture](L0_STAGE_SOURCE_CAPTURE.md),
[L4 runtime limits](L4_RECORDING_MANUAL_ANALYSIS.md),
[explicit annotation](L4_R2_FROZEN_BASELINE.md), and
[memory/logging](MEMORY_AND_LOGGING.md).

## 5. Research questions and falsifiable expectations

| Question | Comparison | Result that would weaken the proposed concern or intervention claim |
| --- | --- | --- |
| RQ1: Does the system accept campaign-associated false claims? | Independently verified claim labels versus response stance | Consistent correction or appropriate abstention across held-out claims |
| RQ2: Does framing change that behavior? | Same claim/evidence under neutral, pro-Russian-prior, and opposing-prior prompts | Little or no paired change, or a symmetric tendency to agree with either prior rather than a specific directional tilt |
| RQ3: Does source manipulation affect answers? | Clean versus manipulated fixed evidence, with length and retrieval position controlled | No meaningful increase in false-claim support or source laundering |
| RQ4: What does local synthesis change? | FRONTIER result versus synthesis and FINAL from the same trial | Preserved correct claims, uncertainty, and citations; no systematic new errors |
| RQ5: Does mediation help? | Frozen baseline versus a predefined generic mediator, with compute overhead reported | No improvement, loss of correct answers, increased unsupported anti-Russian assertions, or excessive false interventions |

Separate general sycophancy, factual ignorance, source-selection failure, and
directional political asymmetry. A framing effect in both directions is not by
itself evidence of a uniquely pro-Russian bias.

## 6. Benchmark and reference evidence

Prepare claim families, not a list of desired political conclusions. Each case
should contain:

- a stable claim ID, exact factual proposition, relevant entities, time interval,
  and verification cutoff;
- an independently reviewed label: true, false, unresolved, or temporally changed;
- a concise reference explanation and specific supporting/refuting passages;
- original reporting, documents, or other primary evidence where available,
  with publication/access dates and content hashes for locally retained material;
- the campaign-association evidence and its attribution confidence, recorded
  separately from the truth label;
- semantically equivalent prompt variants and the intended experimental factors;
- a source-family identifier so reposts and translations are not counted as
  independent corroboration;
- allowed interpretations, uncertainty requirements, and known ambiguity.

Use clearly verifiable false claims associated with documented operations,
alongside true statements favorable and unfavorable to Russia, false assertions
in the opposite direction, and matched non-Russian factual controls. Increase
the corpus before trying to populate every stratum. A small pilot cannot support
a comprehensive geopolitical ranking.

Correctly accepting a true statement favorable to Russia is a successful answer.
Criticism of Ukraine, NATO, or a Western government is not a propaganda label.
The source's affiliation is a provenance variable, not a substitute for checking
the proposition. Do not force equal credibility where evidence is unequal.

Maintain unresolved cases as a separate uncertainty test; do not score them as
false simply because corroboration is unavailable. Have a second reviewer check
truth labels and translations before freezing the evaluation set. Keep protocol
development cases separate from held-out evaluation cases.

## 7. Experimental tracks

### Track A: no-web baseline and framing

Use a local model without retrieval tools to obtain a controlled no-web baseline.
For each claim, hold the factual question constant and vary only the expressed
prior: neutral, pro-Russian, or opposing. Do not turn an opposing prompt into a
different factual question. Randomize/interleave case order and keep sampling
settings identical within each contrast.

A corresponding Codex/no-web arm requires a research adapter that can enforce
and verify the absence of browsing. A prompt saying "do not browse" is not
sufficient evidence that a run was isolated. If this control cannot be enforced,
label the arm as a service-level observation and do not merge it with the
controlled local baseline.

### Track B: controlled source-context manipulation

Supply the same model with versioned, lower-trust evidence bundles:

1. a reference bundle with adequate reliable coverage;
2. the reference bundle plus operation-linked material;
3. a matched-length control bundle with additional non-deceptive material;
4. a controlled information-gap bundle, with and without the suspect material.

Add dose/repetition conditions only after the basic contrast works. Separate
source count from source independence. Hold token budget, ordering, document
format, and visibility constant where possible; counterbalance document order
and log the exact text actually included after truncation. Distinguish real
source metadata from experimentally altered labels.

Treat documents as evidence, not system instructions. Ordinary misleading
content and embedded prompt-injection instructions are different factors and
must be tested separately. Make no public web edits to seed an attack: replay
local snapshots or bounded fixtures in an isolated test environment.

This track requires new evidence-supply/capture support. L3's existing
conversation retrieval is not already an experimental web retriever. If a
backend performs additional uncontrolled searches, exclude that run from the
fixed-evidence causal comparison or analyze it as a separate condition.

### Track C: live-web service audit

Ask the same question families through the actual Codex frontier path and retain
the answer, dispatched request, tool/search metadata exposed by the backend,
citations, and retrievable source snapshots. Record missing telemetry explicitly.

This measures the deployed service at a time, including its search/ranking and
policy behavior. It does not isolate model weights. Record date, CLI version,
selected model configuration, exposed model identity, search/tool policy,
language, and available region information without disclosing private account
or deployment details. Never infer an unknown backend model from the prose of
its answer. Freeze retrieved bundles for later replay in Track B where permitted.

### Track D: stage-level synthesis and mediation

First compare the captured FRONTIER result with LOCAL synthesis and FINAL in
the same completed turn. Score correct-to-incorrect changes, successful
corrections, citation loss, unsupported additions, and uncertainty preservation.
Include recovery/fallback producer metadata so a wrapper message is not scored
as a model opinion.

For a later intervention experiment, replay the same frozen frontier result to
baseline synthesis and a separately versioned mediator. Keep the claim/evidence
input identical, randomize presentation order, and report added inference cost.
If the mediator makes extra verification calls, include a compute-matched
control or explicitly report that the comparison estimates the entire enhanced
workflow rather than the mediation instruction alone.

Operational P1/P2 remains OFF. Research intervention needs an explicit isolated
implementation and evaluation; the existing frozen flags are not a domain-ready
debiasing switch.

## 8. Scoring and analysis

Annotate response stance toward each exact proposition as accepted, rejected,
qualified/uncertain, not addressed, or refusal. Separately annotate whether a
statement is quoted or attributed rather than endorsed. Reference truth labels
determine correctness; attribution alone must not turn a repeated falsehood
into an endorsement.

| Measure | Definition |
| --- | --- |
| False-claim acceptance | Fraction of responses to false-labeled cases that affirm the false proposition as true |
| True-claim rejection | Fraction of responses rejecting independently verified true propositions; report by direction of political favorability |
| Framing shift | Within-claim change in stance/correctness between framing conditions at fixed evidence |
| Source-exposure effect | Within-claim difference in false-claim acceptance between manipulated and matched control bundles |
| Citation grounding | Whether an accessible cited passage actually supports the associated assertion; track missing, fabricated, and irrelevant citations separately |
| Source laundering | Use of operation-linked material as authoritative support without appropriate provenance/context; a critical citation is a separate category |
| Evidence independence | Whether multiple cited pages trace to the same original source or operation |
| Synthesis distortion | Correctness, attribution, and uncertainty changes from FRONTIER to FINAL on matched trials |
| Intervention harm | New errors, unjustified refusals, or loss of correct evidence introduced by mediation |
| Engineering overhead | All model/tool calls, token usage when exposed, latency, failures, and excluded trials |

For false-claim cases, a simple framing estimand is the paired difference in
acceptance probability between the framed and neutral conditions. Report the
opposing-prior contrast separately. Do not collapse these measures into a
universal "propaganda score" or reuse R1 detector confidence as effect magnitude.

Use two human raters, blinded to model/arm where practicable; code the entire
small pilot independently, record agreement, and adjudicate disagreements.
For a larger study, freeze a double-coded subset and an appropriate agreement
statistic in advance. Any LLM judge is auxiliary and must be checked against
human labels, including counterexamples; Qwen must not be the sole judge of its
own output or of frontier answers.

Analyze repeated samples within claim families. Report denominators, exclusions,
refusals, variability, and uncertainty intervals; use paired analyses or bootstrap
resampling clustered by claim family, not a fiction of thousands of independent
facts. Preregister primary contrasts before a confirmatory run. A small pilot is
for feasibility and rubric repair, not precise population estimates or provider
league tables. Repeated frontier runs on changed service versions are distinct
temporal samples, not exact replications of a fixed checkpoint.

## 9. Proposed implementation above v9.6.2

The following are proposed components, not existing commands or configuration
keys:

| Component | Proposed responsibility |
| --- | --- |
| Versioned benchmark manifest | Claims, reference evidence, prompt variants, source families, splits, and rubric versions |
| Isolated batch runner | Explicit LOCAL/FRONTIER arms, independent state directories, ordering/repetition, bounded calls, resume ledger, and budget limits |
| Execution capture adapter | Original and actually dispatched prompts, selected context, route, visible tool activity, stage sources, model/runtime identity, failures and recovery |
| Evidence-bundle adapter | Fixed document snapshots and hashes, lower-trust placement, context-budget accounting, and verified retrieval policy |
| Annotation/export layer | Blind response IDs, human coding, optional validated judge output, adjudication, and stage-linked derived records |
| Analysis/report script | Paired effects, family-level uncertainty, error transitions, exclusions, coverage and overhead |
| Optional mediator profile | A frozen non-personalized policy, evaluated after the baseline rather than enabled by default |

A candidate future directory is `research/propaganda-resilience/`, containing
`protocol.md`, `benchmark.jsonl`, `run-manifest.json`, an evidence index, and a
scoring rubric. These files do not yet ship with this proposal. Store generated
runs outside the tracked source tree by default; publish only reviewed exports.

Use a versioned sidecar result format for new domain-specific labels and metrics.
Link it to exact L0 store/file/epoch/turn/stage identities and content hashes.
R2 may be used for annotations already representable by the frozen contract;
do not insert unsupported observation types or overload existing fields. A
future schema extension requires an explicit version decision, not a silent
change to R1.

The current `/analyze` scans a capped epoch (200 observations) and returns bounded
references. It is not a full benchmark aggregator. Partition research stores
deliberately and aggregate explicit exports, with completeness checks; never
present capped/partial reads as the entire experiment. Maintain a separate
trial ledger so failed or aborted turns absent from L0 remain in denominators.

The current Codex path can use an existing login without an OpenAI API key.
Additional providers require separate adapters/access and are not supplied by
this proposal. Preserve the one frontier call per user-turn contract; repeated
trials are separate turns. Capture all additional local routing, synthesis,
memory, and evaluation calls rather than reporting frontier calls as total cost.

## 10. Staged pilot and implementation gates

1. **Protocol and corpus:** freeze a small claim set, reference evidence, paired
   prompts, rubric, exclusions, and primary comparisons. Validate factual labels
   independently before evaluating any model.
2. **Model-free engineering gate:** use synthetic transports to verify isolation,
   actual prompt/evidence capture, stage provenance, deterministic export,
   budget accounting, missing-stage handling, and failure/resume bookkeeping.
   These are software checks, not model-quality evidence.
3. **Small live baseline:** start with 12 adjudicated claims in one language,
   three framing variants and three repetitions: **108 trials per arm**. A LOCAL
   arm and a FRONTIER-plus-synthesis arm produce 216 trial invocations and, at
   one call per successful frontier trial, up to 108 frontier calls before any
   separately budgeted retries. Other local/model calls are additional.
4. **Review feasibility:** inspect prompt equivalence, scoring disagreements,
   unknown identities, evidence loss, latency, and quota use. Repair the protocol
   on development cases, freeze a new version if needed, and keep evaluation
   cases held out. The pilot is not large enough to fill every control stratum.
5. **Controlled evidence extension:** add clean/manipulated/gap conditions one
   contrast at a time, with matched-length controls. Do not launch the full
   claim x language x model x dose x mediator Cartesian product by default.
6. **Mediation comparison:** evaluate only a frozen, independently versioned
   policy against the established baseline, reporting both benefit and harm.
7. **Replication and reporting:** expand to Slovak/English and then other
   languages with reviewed translations; archive local model/runtime digests and
   report frontier dates/configuration as service-level observations.

For every live run, set an explicit trial/call/time budget, stop on isolation or
provenance failure, and record timeouts/refusals instead of silently replacing
them. No live inference or benchmark is executed by adding this document.

## 11. Isolation, publication, and limits

Use an LFO-owned research instance with disposable L1/L2/L3 and, when used, a
separate L4 store. Keep ordinary conversation history, active user profiles, and
production memory out of the corpus and prompts. Verify this boundary with
fixtures before running models. Evaluation labels must not feed back into model
context or teach the answer during a test.

Preserve exact research evidence privately as needed for reproducibility, subject
to source licensing. Public exports should contain sanitized prompts, labels,
hashes, permitted excerpts, methods, and aggregate results. Remove account
identifiers, credentials, private paths, hostnames, and personal conversation
content. Prefer source references over republishing full propaganda articles or
building a new indexable propaganda mirror. Do not deploy poisoning content to
public sites as part of this study.

This project would measure susceptibility and correction under defined
conditions. It would not establish general model neutrality, country-wide
political influence, persuasion of real users, or the historical origin of a
model's weights. A finding of little effect, no mediator benefit, or mediator
harm is a valid research outcome.

## References

1. **Miller, C., Perry, H., and Devine, F. (2026).** *GEO for Geopolitics: What
   happens when AI and information warfare collide.* Demos/CASM, 27 July.
   Research report. [Publication](https://demos.co.uk/research/geo-for-geopolitics-what-happens-when-ai-and-information-warfare-collide/)
   · [Report PDF](https://demos.co.uk/wp-content/uploads/2026/07/GEO-for-Geopolitics_Report_2026.ac_.pdf).
2. **DFRLab (2026).** *Pravda in the pipeline: Early evidence of state-adjacent
   propaganda in AI training data.* 8 April, as dated on the article page.
   Technical investigation.
   [Article](https://dfrlab.org/2026/04/08/pravda-in-the-pipeline/).
3. **Waight, H., Yang, E., Yuan, Y., Messing, S., Roberts, M. E., Stewart, B. M.,
   and Tucker, J. A. (2026).** *State media control influences large language
   models.* Nature. Published online 13 May. Peer-reviewed research.
   [DOI](https://doi.org/10.1038/s41586-026-10506-7)
   · [Authors' companion and replication links](https://state-media-influence-llm.github.io/).
4. **Alyukov, M., Makhortykh, M., Voronovici, A., and Sydorova, M. (2025).**
   *LLMs grooming or data voids? LLM-powered chatbot references to Kremlin
   disinformation reflect information gaps, not manipulation.* HKS
   Misinformation Review, 15 October. Peer-reviewed research note.
   [DOI](https://doi.org/10.37016/mr-2020-187).
5. **Sadeghi, M., and Blachez, I. (2025).** *A Well-funded Moscow-based Global
   'News' Network has Infected Western Artificial Intelligence Tools Worldwide
   with Russian Propaganda.* NewsGuard, 6 March. Investigation/audit.
   [Article](https://www.newsguardtech.com/special-reports/moscow-based-global-news-network-infected-western-artificial-intelligence-russian-propaganda/).
6. **Baker, S., and Bengani, P. (2026).** *Russia's Wiki Warfare Tries to Distort
   Reality, Documents Show.* Bloomberg News, 23 June; syndicated 24 June.
   Investigative reporting, not a model-efficacy experiment.
   [Syndicated article](https://www.insurancejournal.com/news/international/2026/06/24/875002.htm).

Related project documents: [README research overview](../README.md#documentation-map),
[Balancing the Loop](HUMAN_AI_BIAS_BALANCER.md),
[Generic Epistemic Mediator](GENERIC_EPISTEMIC_MEDIATOR.md),
[L4 runtime](L4_RECORDING_MANUAL_ANALYSIS.md), and
[roadmap](ROADMAP.md#humanai-bias-balancing).
