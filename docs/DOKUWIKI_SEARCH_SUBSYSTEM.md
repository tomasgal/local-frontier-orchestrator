# DokuWiki search subsystem

## Status

This document describes an **optional external knowledge-retrieval subsystem** that can be used alongside Local Frontier Orchestrator (LFO).

It is not required by the LFO runtime, it remains outside LFO's internal L0-L4 architecture, and it should not be interpreted as a new authoritative memory layer.

The reference design was developed for a human-curated DokuWiki corpus mirrored to Git. Its purpose is to let an agent recover small, precise pieces of canonical wiki content without treating the wiki itself as model memory and without requiring a large vector/RAG stack.

## 1. Design goal

A personal or research wiki often already contains several strong retrieval signals:

- page titles and namespaces;
- explicit internal links and backlinks;
- section headings;
- editorial emphasis such as short bold spans;
- recurring technical identifiers;
- names, organizations, products and other named entities;
- rare domain-specific words.

A conventional full-text system can index all text, but for LLM-assisted retrieval that is not always the most efficient first step. Much of the useful structure is already present in the wiki.

The subsystem therefore uses a **marginal-utility approach**:

> Prefer the cheapest deterministic signal that already exposes the relevant content, and add lexical indexing mainly where structure leaves a retrieval gap.

The goal is not exhaustive search-engine recall. The goal is a compact candidate generator that makes hard-to-find wiki segments cheaply recoverable.

## 2. Canonical-source boundary

The DokuWiki source remains authoritative.

Derived structures are disposable retrieval aids:

```text
DokuWiki pages / Git mirror
          |
          +--> page-link graph
          +--> section/segment index
          +--> heading and bold retrieval hints
          +--> compact lexical rescue index
                    |
                    v
             candidate segments
                    |
                    v
          exact canonical source range
```

A graph edge, ranking score, lexical hit, or inferred candidate does **not** become a factual source merely because the retrieval system produced it.

The final factual interpretation must be based on the canonical wiki text that the candidate points to.

This keeps the retrieval layer rebuildable and inspectable.

## 3. Segment-aware retrieval

Pages are split deterministically at DokuWiki H1-H5 headings.

Each segment has:

- a stable internal segment ID;
- page ID;
- heading;
- heading hierarchy/path;
- DokuWiki fragment;
- source line range;
- direct body only, excluding child-section body text;
- bounded lexical signature;
- short bold retrieval hints;
- explicit links originating in that segment.

The segment index does not need to persist another full copy of the wiki body text. Once a candidate is known, the client loads the corresponding source range from the canonical page.

This gives a useful distinction:

```text
page graph       -> where topics are explicitly connected
segment index    -> which section is likely relevant
source range     -> what the wiki actually says
```

## 4. Bold as a hint, not ontology

Short bold spans are treated as editorial retrieval hints.

They can be useful because a human author often bolds:

- model numbers;
- conclusions;
- key concepts;
- current decisions;
- warnings;
- important names.

They are deliberately **not** converted into graph relationships or authoritative taxonomy.

A bold phrase can improve retrieval ranking without asserting that the author intended a formal semantic relationship.

## 5. High-information lexical rescue index

The lexical layer is intentionally small and is **not a full-text search engine**.

It focuses on terms that add recall beyond page titles, headings, bold hints and explicit graph topology.

Three classes receive priority:

### 5.1 Technical identifiers

Examples:

```text
M1541
S82093AA
PC100
440LX
E5450
AP133AAS3-B257C
```

These often have low document frequency and very high retrieval value.

### 5.2 Named entities and titles

Examples include:

- people;
- organizations;
- product families;
- project names;
- named documents;
- institutions;
- historical events.

This class is particularly useful for **secondary entities** that are mentioned only once in prose and never promoted to a heading or bold span.

### 5.3 Rare content-bearing terms

Ordinary terms are considered mainly when they have high information value and low document frequency.

Very common corpus terms are poor rescue keys because they return too many segments and are usually already reachable through normal page/section structure.

## 6. Structural-gap optimization

The index is complementary rather than duplicative.

If a term is already visible through a segment heading, heading path or bold hint, the lexical layer does not need to duplicate that same occurrence.

However, a useful special case exists when a term is structurally visible **somewhere** but occurs only in body text elsewhere.

For example:

```text
Page A:
  heading/bold -> SDRAM

Page B:
  body only    -> SDRAM
```

The Page B occurrence has high marginal value: the structural layer proves that the term is meaningful in the corpus, while the lexical rescue posting closes a concrete recall gap.

This is one reason the subsystem can remain small while still improving retrieval materially.

## 7. Compact retrieval budget

The reference implementation is deliberately bounded.

A representative production configuration uses:

```text
soft target:        5,000 lexical keys
hard cap:          10,000 lexical keys
term shards:            16
```

The selected keys are split across technical identifiers, named entities and rare content terms.

The exact allocation is not intended as a universal optimum. It is an engineering budget chosen to capture the steep part of the usefulness curve:

```text
first useful keys        -> large retrieval gain
next few thousand        -> still useful
large full-text tail     -> progressively smaller marginal gain
```

This should be tuned organically as the corpus and retrieval failures evolve, not treated as a fixed research benchmark.

## 8. Term-sharded access

Lexical keys are partitioned deterministically into small term-hash shards.

A lookup therefore does not require downloading the entire index.

Conceptually:

```text
query term
   |
hash(term)
   |
   v
one small lexical shard
   |
matching segment IDs
   |
segment/page metadata
   |
exact source range
```

This design is convenient when the canonical/wiki mirror is hosted in Git and accessed remotely by an agent or connector.

The wiki web server does not need to become the runtime search backend.

## 9. Graph plus lexical retrieval

The lexical layer is only one input to candidate generation.

A composite preflight can combine:

- page and segment structural matches;
- lexical rescue hits;
- explicit backlinks;
- bounded graph paths;
- bridge pages;
- simple overlap/redundancy heuristics.

The resulting graph remains deterministic with respect to explicit wiki links and parsed structure.

Semantic similarity, embeddings or inferred `RELATED_TO` relationships should remain a separate layer if they are ever added, with explicit provenance.

## 10. Relationship to LFO

This subsystem is relevant to LFO because it follows the same broad engineering principle as the orchestrator:

> Use the cheapest layer that can reliably solve the current problem, and escalate only when necessary.

A possible retrieval flow is:

```text
user request
    |
    v
cheap structural retrieval
    |
    +--> sufficient -> load source segment
    |
    +--> insufficient
            |
            v
      lexical rescue
            |
            +--> sufficient -> load source segment
            |
            +--> insufficient
                    |
                    v
          broader graph traversal /
          stronger model / frontier / web
```

This is conceptually compatible with LFO's local-first and bounded-escalation philosophy.

### External knowledge, L3 and L4

A DokuWiki corpus is **not L4**.

The current architectural terminology is:

```text
L0  authoritative raw interaction history
L1  lossy conversational working memory
L2  structured current factual state
L3  retrieval & resolution fabric
L4  research / epistemic analysis output
```

DokuWiki is different from all five layers. It is an independently authored and curated external corpus with its own source history and revision lifecycle.

The useful connection is through **L3**:

```text
DokuWiki search subsystem
          |
          v
L3 external-knowledge adapter
          |
          v
selected canonical wiki segments
          |
          +--> ordinary LFO context when needed
          |
          +--> L4 research analysis
```

For L4, the search subsystem can retrieve conceptual or methodological context, previous project decisions, relevant definitions, or other canonical material needed to interpret an interaction event. The search result is input context for analysis; it is not itself an L4 observation.

This distinction is deliberate:

- **DokuWiki** stores curated external knowledge;
- **L3** finds/resolves relevant evidence and context;
- **L4** records derived research interpretations such as bias observations, interventions, outcomes or longitudinal hypotheses.

Calling the wiki "L4 memory" would collapse an external source into a derived analytical layer and would again turn memory levels into a taxonomy of data sources.

## 11. Why this is not conventional RAG by default

The design does not require:

- embeddings;
- a vector database;
- semantic chunk generation;
- an external search service;
- a second LLM pass for indexing;
- a large duplicated document store.

Those mechanisms can be added later if measured retrieval failures justify them.

For a highly linked, human-curated wiki, deterministic structure already provides substantial retrieval information. The compact lexical layer is intended to cover the remaining high-value gaps first.

This is not a claim that the approach is superior to BM25, Lucene, Elasticsearch, vector search or hybrid RAG in general.

It is a deliberately narrow architecture for a small-to-medium curated knowledge corpus where transparency, rebuildability and low retrieval overhead matter.

## 12. Epistemic rules

The subsystem follows several strict distinctions:

- **link frequency is not importance**;
- **document frequency is not truth**;
- **rarity is not importance**;
- **graph centrality is not authority**;
- **bold text is not ontology**;
- **a lexical hit is not factual evidence**;
- **an inferred candidate is not an explicit author assertion**.

The retrieval system proposes where to look.

The source text determines what can actually be claimed.

## 13. Scope for future integration

A future LFO integration could expose a narrow read-only knowledge interface such as:

```text
search_wiki(query)
get_wiki_segment(segment_id)
wiki_neighbors(page_id)
wiki_backlinks(page_id)
```

The interface should return bounded candidates and source locators rather than dumping the entire knowledge base into local-model context.

The adapter should also remain optional: LFO must continue to function when no external wiki is configured.

## 14. Summary

The DokuWiki search subsystem is best understood as a **small graph-aware retrieval layer over a canonical human-curated corpus**.

Its main design choices are:

- preserve DokuWiki/Git as the source of truth;
- parse pages into stable source-addressable segments;
- use explicit link topology before inferred semantics;
- treat headings and bold spans as retrieval signals;
- maintain a compact high-information lexical rescue index;
- favor technical identifiers, secondary named entities and rare content words;
- avoid duplicating occurrences already visible structurally;
- retrieve the exact source segment before interpretation;
- keep the subsystem outside LFO's L0-L4 internal architecture while exposing it through an optional L3 retrieval adapter.

This makes the subsystem compatible with LFO's broader philosophy without turning a wiki into model memory or making external knowledge retrieval a mandatory dependency of the core orchestrator.
