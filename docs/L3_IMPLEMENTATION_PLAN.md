# L3 implementation plan — selective tagged SQL retrieval

## Status

**Design direction agreed 2026-10-12. L3-R1 is offline-validated PASS; L3-R2 deterministic tagging is implemented on branch `v9.5-l3-selective-index` and awaits Windows offline acceptance.**

L3 is the next milestone after the immutable L2 baseline `v9.4-l2-frozen`. It does not reopen L2 and it does not replace L0, L1 or L2 authority. L3 is a separate, reconstructible SQLite database and software layer whose job is to **reduce the amount of memory/context work that reaches the LLM**.

The intended hierarchy is:

```text
L0  raw interaction evidence / authoritative history
L1  bounded conversational orientation
L2  typed current factual state + provenance
L3  selective tagged index + retrieval/context planner
L4  annotation and research-analysis layer over the interaction log
```

L3 organizes and filters. L4 interprets and annotates.

## 1. Core objective

L3 should move as much memory organization as practical **before model inference** into deterministic, auditable SQL operations.

For an eligible turn, L3 should:

1. identify a small set of topical/entity/function metadata from the current request and known memory state;
2. use those metadata to narrow the candidate set;
3. retrieve the best L0/L2 evidence;
4. remove redundant representations where a more authoritative/compact representation already exists;
5. compile a smaller model-visible context packet;
6. fall back safely to the existing L0/L1/L2 path when classification or retrieval is uncertain.

The primary optimization target is not “more retrieved memory”. It is:

> **more relevant information per model-visible token, with no loss of answer correctness or provenance.**

## 2. Physical and logical boundary

L3 uses a **separate SQLite database** from L2.

L2 remains the factual state store. L3 stores only derived/reconstructible organization metadata and source references. Loss or rebuild of L3 must not destroy interaction history, current facts, corrections or provenance.

Illustrative L3 records may include:

```text
source_layer      L0 | L2
source_ref        stable source/turn/fact reference
topic_id          controlled topic identifier
entity_ref        optional L2 entity reference or normalized external key
kind              decision | configuration | result | preference | question | ...
temporal_state    current | historical | superseded | unknown
retrieval_state   normal | priority | exclude | unknown
classifier_rule   rule/version that produced the metadata
```

The exact schema is an implementation decision. The invariant is that L3 metadata are **not authoritative facts**.

## 3. Tagging model

L3 uses **faceted, bounded metadata**, not free-form hashtag generation.

Initial dimensions:

- **topic** — what broad workstream/domain the information belongs to;
- **entity** — which known entity/entities it concerns;
- **kind** — functional role such as decision, configuration, result or preference;
- **temporal/status** — current, historical, superseded or unknown where deterministically available;
- **retrieval state** — optional priority/exclusion state.

A record may belong to more than one topic. Topics are not namespaces and do not form a mandatory tree.

Each tag dimension must distinguish:

- positive membership;
- explicit negative membership where justified;
- unknown/unclassified.

Absence of a tag must not silently mean exclusion.

### Anti-bloat invariant

L3 tags are **internal SQL metadata**. They are not appended to the model prompt.

> **L3 metadata must not increase model-visible context unless a specific metadata field replaces a larger raw-context representation and the replacement is measured as beneficial.**

The online classifier must remain bounded. The initial design target is approximately:

- 0–2 topic candidates;
- 0–3 entity candidates;
- at most one primary `kind`;
- optional temporal/status filter;
- otherwise `unknown`.

This is a design bound, not a frozen schema constant.

## 4. Online critical path

The preferred online path contains **no additional LLM call**:

```text
USER PROMPT
    |
    v
cheap deterministic normalization
    |
    v
query topic/entity/kind candidates
    |
    v
L3 SQLite filtering/ranking
    |
    +----> L2 exact/current state lookup
    |
    +----> L0 lexical/exact retrieval
    |
    v
deduplication + relevance/budget rules
    |
    v
minimal context packet
    |
    v
Qwen
```

FTS5 is a possible retrieval primitive, not the definition of L3. The preferred order is **metadata narrowing first, lexical/full-text ranking inside the reduced candidate space second**.

Embeddings, a vector database, graph traversal or an LLM reranker are not part of the initial implementation. They may be evaluated later only against measured retrieval failures.

## 5. Maintenance path outside the critical turn

Operations that do not have to block the current answer should be moved out of the online path where practical, including:

- rebuilding derived indexes;
- merging or retiring synonymous topic identifiers;
- reclassifying older records after rule changes;
- compacting/rebuilding FTS structures;
- validating/reconciling derived references;
- future expensive semantic enrichment if it is ever justified.

This follows the same architectural principle as L2/DEV5 optimization: reduce critical-path model/data traffic before pursuing hardware-specific tuning.

## 6. Expected savings

### 6.1 Smaller retrieval search space

Without L3, lexical retrieval may score a broad historical set. L3 first narrows the candidate domain by topic/entity/kind and then searches within it.

Expected effect:

- less JSONL/history scanning as the corpus grows;
- fewer false-positive hits;
- more stable retrieval cost with long-lived conversations.

### 6.2 Fewer model-visible tokens

L3 should reject irrelevant candidates before prompt construction.

Illustrative mechanism:

```text
baseline:
  L1 orientation
  + several L0 lexical hits
  + L2 facts
  + recent turns

L3:
  only the topic/entity-compatible evidence
  + bounded recent context required for continuity
```

The exact savings must be measured; no percentage is assumed in advance.

### 6.3 Cross-layer deduplication

When L0, L1 and L2 contain overlapping representations, L3 may prefer the most useful representation for the current query.

Example:

```text
L1: ORION now uses Debian 13
L0: We changed ORION from Debian 12 to Debian 13
L2: ORION.os = Debian 13
```

For a simple current-state query, L2 may be sufficient; L0 remains available as provenance/fallback rather than automatically consuming model context.

### 6.4 Optional deterministic fact fast path

A later L3 stage may bypass Qwen for narrowly defined, unambiguous exact factual lookups whose answer can be rendered safely from one current L2 fact.

This could save an entire model call, but it is **not required for the first L3 MVP** and must have a conservative eligibility contract.

### 6.5 Offline maintenance

Moving consolidation/reindexing work outside the interactive path prevents long-term organization from consuming turn latency.

## 7. Performance model and break-even condition

Prompt shortening reduces model work, but it does **not mathematically guarantee** a lower total turn time because L3 itself has non-zero overhead.

Let:

- `N` = baseline model-visible input size;
- `N'` = input size after L3, with `N' < N`;
- `F(N)` = model-side cost for an input of size `N`;
- `H` = added L3 online preprocessing/retrieval cost.

Then:

```text
baseline:  T0 = F(N)
L3:        T3 = H + F(N')
```

L3 is faster iff:

```text
H < F(N) - F(N')
```

Under a simple locally linear approximation `F(N)=aN+b`, this becomes:

```text
H < a (N - N')
```

This break-even inequality was independently checked with Wolfram Language while preparing this plan.

The practical expectation for LFO is favorable because SQLite operations are normally much cheaper than local-model prompt evaluation, especially on constrained hosts. Nevertheless, the project will **measure rather than assume** the sign of total latency change.

The acceptance gate is therefore not “any added milliseconds fail L3”. It is:

- L3 must reduce model-visible work on eligible cases or eliminate a model call;
- answer correctness/provenance must not regress;
- the added deterministic overhead must remain below the model work saved on the target workload, within measurement uncertainty;
- cases with no useful narrowing may safely fall back to the baseline path.

## 8. Quality and safety invariants

L3 must preserve:

- L0 raw-history authority;
- L2 current-state/correction semantics;
- source-turn/fact provenance;
- scope separation;
- safe handling of ambiguous entities;
- visible/fail-safe misses rather than guessed identity;
- current explicit user evidence over retrieved stale state;
- the frozen L2 write contract.

L3 must not:

- write bias interpretations or psychological labels;
- silently mutate L2 facts;
- turn retrieval frequency into epistemic confidence;
- require a new per-turn model call;
- make its derived index a source of truth;
- require a vector/graph database by default.

## 9. Relationship to L4

L3 topic/entity grouping is intentionally useful to later L4 research, but the layers remain separate.

L3 may expose neutral organizational metadata such as:

```text
topic=lfo
kind=decision
entity=L3
period=2026-Q4
```

L4 can later query such groups when creating **event-scoped, revisable annotations** about bias, intervention or outcome.

L3 must not produce records such as:

```text
bias=confirmation_bias
user_trait=...
```

Those are interpretations and belong to L4 with explicit evidence, confidence, method/version and contradictory evidence.

## 10. Research inspiration

### Primary: LightMem — ICLR 2026

[LightMem: Lightweight and Efficient Memory-Augmented Generation](https://proceedings.iclr.cc/paper_files/paper/2026/hash/a05b72653ec5b473732129829ae04195-Abstract-Conference.html) is the closest architectural inspiration.

Relevant ideas transferred at the principle level:

- lightweight early filtering of irrelevant information;
- grouping information by topic;
- topic-aware short-term organization;
- moving expensive long-term consolidation to an offline “sleep-time” update path;
- treating efficiency/token traffic as a first-class memory-system objective.

LFO does **not** claim to reproduce LightMem or transfer its benchmark gains. L3 adapts the principle to a deterministic local-first PowerShell/SQLite architecture and deliberately avoids an extra LLM call for online tagging.

### Secondary: SeCom — ICLR 2025

[SeCom: On Memory Construction and Retrieval for Personalized Conversational Agents](https://proceedings.iclr.cc/paper_files/paper/2025/hash/e56f394bbd4f0ec81393d767caa5a31b-Abstract-Conference.html) provides a closely related motivation: natural-language redundancy can hurt retrieval, and topical segmentation plus compressed memory units can improve retrieval quality.

LFO differs by favoring bounded SQL metadata and source references rather than making an LLM segmentation/compression model a required online component.

### Evaluation/indexing influence: LongMemEval — ICLR 2025

[LongMemEval: Benchmarking Chat Assistants on Long-Term Interactive Memory](https://proceedings.iclr.cc/paper_files/paper/2025/hash/d813d324dbf0598bbdc9c8e79740ed01-Abstract-Conference.html) separates memory systems into **indexing, retrieval and reading** and reports gains from better indexing keys and time-aware query expansion.

L3 adopts this separation as an evaluation lens. Candidate tests should cover at least information extraction, multi-session reasoning, temporal reasoning, updates and abstention/no-hit behavior.

### Secondary architectural analogy: H-MEM

[Hierarchical Memory for High-Efficiency Long-Term Reasoning in LLM Agents](https://arxiv.org/abs/2507.22925) motivates index-based routing through structured memory rather than exhaustive similarity search. L3 is flatter and more deterministic, but shares the principle of narrowing before expensive retrieval/inference.

### Deliberate contrast: A-MEM / Zettelkasten

[A-MEM: Agentic Memory for LLM Agents](https://arxiv.org/abs/2502.12110) demonstrates the usefulness of structured attributes such as context, keywords and tags. Its Zettelkasten-inspired dynamic linking and agentic memory evolution are **not** adopted for L3.

For LFO, explicit knowledge-network construction is considered too strong for this layer and overlaps conceptually with wiki/knowledge-graph functionality and later analytical structures. L3 borrows the idea of useful metadata, not the agentic linking architecture.

## 11. MVP implementation sequence

### L3-R0 — baseline and corpus

Freeze an evaluation corpus from isolated fixtures covering:

- exact current L2 fact;
- lexical L0 recall;
- paraphrased/topic-consistent query;
- ambiguous entity;
- cross-topic lexical collision;
- correction/superseded value;
- multi-session decision;
- temporal query;
- no-hit/abstention;
- mixed case requiring fallback.

Record baseline context characters/tokens, retrieved items, correctness and phase timing.

### L3-R1 — separate SQLite metadata store

Implement a reconstructible L3 database and thin access layer. No model calls and no change to L2 schema.

### L3-R2 — bounded deterministic tagging

Implement the first controlled topic/entity/kind rules and provenance references. Measure false positive, false negative and unknown rates.

### L3-R3 — retrieval planner / context compiler

Use L3 metadata to narrow L0/L2 candidates, deduplicate overlapping evidence and enforce an explicit context budget.

### L3-R4 — eligible live pilot

Compare baseline vs L3 on isolated memory with unchanged model/runtime settings. Record:

- model-visible input chars/tokens;
- L3 SQL/preprocessing time;
- L0/L2 items considered and emitted;
- answer correctness;
- provenance fidelity;
- total turn time;
- model calls.

### L3-R5 — optional FTS5 within narrowed candidates

Only if the corpus shows lexical retrieval weaknesses or L0 scan cost that justify it.

### L3-R6 — optional deterministic factual fast path

Only after the retrieval/index contract is stable and narrowly safe eligibility can be specified.

Embeddings/reranking remain a later evidence-triggered option, not an assumed milestone.

## 12. Acceptance decision

Classify each tested mechanism as **PASS, FAIL or INCONCLUSIVE**.

L3 MVP should be accepted when the bounded evaluation demonstrates:

1. no material correctness/provenance regression against the baseline;
2. lower model-visible context on eligible cases;
3. zero new mandatory LLM calls;
4. reconstructible/optional failure behavior;
5. deterministic online overhead below the saved model work for the target cases, or results that are clearly favorable but timing remains inconclusive because of runtime noise;
6. no contamination of L2 authority or L4 analytical semantics.

If a tag dimension or retrieval rule does not improve selection, compression, scalability or downstream L4 grouping, remove it rather than preserve it for architectural elegance.


## 13. Implementation checkpoint — L3-R1

The first code increment deliberately stops before runtime integration.

Implemented on `v9.5-l3-selective-index`:

- `src/LfoL3Store.ps1`: separate SQLite schema and thin metadata access layer;
- `l3_items`: scoped L0/L2 source references only;
- `l3_facets`: bounded dimensions `topic/entity/kind/temporal/retrieval`, polarity `+1/-1`, absence = unknown;
- indexed facet lookup and source/scope indexes;
- transaction helpers and deterministic key normalization;
- `tests/Test-LfoL3Store.ps1`: TEMP-only isolation, positive/negative/unknown semantics, scope isolation, idempotent source upsert, restart persistence, L2 file non-mutation and reconstructibility;
- `tests/Invoke-L3R1Offline.ps1`: bounded acceptance runner that also re-runs the L2 store and L2 retrieval regressions.

Not implemented yet:

- no QwenMemory/QwenChat integration;
- no automatic topic/entity/kind classifier;
- no context reduction;
- no FTS5;
- no embeddings/reranker;
- no L3 production-data path;
- no model calls.

R1 is **PASS**. User-supplied Windows PowerShell 5.1 evidence on commit `16836f5997dfc58eca3206b768710be527525c6c` completed all three bounded TEMP-only tests:

- `Test-LfoMemoryStore.ps1`: PASS;
- `Test-Dev4L2Retrieval.ps1`: PASS;
- `Test-LfoL3Store.ps1`: PASS;
- `ModelCalls=0`;
- `ProductionMemoryTouched=False`.

This accepts the physical L3 storage boundary without claiming any retrieval-quality gain yet.


## 14. Implementation checkpoint — L3-R2

R2 adds a controlled SQL-backed tag dictionary and deterministic bounded classifier.

### Mechanism

```text
input text
  -> bounded normalized 1-4-gram keys (max 96)
  -> indexed l3_terms lookup
  -> strongest controlled matches
  -> max 2 topics / 3 entities / 1 kind
  -> optional persistence as internal L3 facets
```

The classifier does not scan arbitrary conversation memory, does not generate free-form labels and does not call an LLM. Unknown remains absence. Automatic classification writes only positive matches; negative membership remains an explicit separate operation.

Schema v2 adds `l3_terms(dimension,value_key,term_key,priority,rule_id,active)` with an index beginning on `term_key`. Rule vocabularies are data, not hard-coded topic ontologies; tests seed a small synthetic registry.

R2 also deliberately does **not** carry an active-topic heuristic across turns yet. Elliptical follow-ups and topic continuity belong in later retrieval-planner evaluation because adding stateful topic carry-over can improve recall but can also create false routing.

### R2 bounded corpus

`tests/Test-LfoL3Tagger.ps1` uses a small explicit corpus covering:

- one-topic + entity + configuration;
- decision;
- retrocomputing topic/entity;
- result;
- preference;
- no-match/unknown;
- two-topic selection;
- entity + result;
- Slovak diacritic normalization;
- >2 topic candidates to verify the hard cap;
- disabled-rule suppression;
- persistence of only the selected facets.

The corpus reports exact-case count and facet TP/FP/FN. These figures validate the deterministic fixture only; they are **not** claims about general-language classifier precision/recall.

R2 is **IMPLEMENTED / VALIDATION PENDING** until `tests/Invoke-L3R2Offline.ps1` passes under Windows PowerShell 5.1.
