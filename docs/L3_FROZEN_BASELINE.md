# L3 Frozen Baseline — v9.5 selective faceted retrieval

**Closure date:** 2026-10-12  
**Accepted runtime commit:** `d8f6c7522eeacda9044453fdeb4b0558352ec798`  
**Development branch:** `v9.5-l3-selective-index`  
**Planned immutable tag:** `v9.5-l3-frozen`  
**Status:** CLOSED for the accepted L3 scope.

## Decision

L3 is accepted and frozen as a reconstructible, deterministic, faceted SQLite
retrieval/index layer above authoritative L0/L2 memory.

No further L3 tuning, retesting or architectural expansion is required before
starting L4. A future L3 follow-up requires either a demonstrated defect or a
new explicitly versioned research scope.

## Frozen architecture

L3 does not replace authoritative memory:

- **L0** raw JSONL conversation history remains authoritative evidence/provenance.
- **L2** structured current/historical facts remain authoritative structured state.
- **L3** stores only reconstructible retrieval metadata and L0 source locators.

The accepted faceted dimensions are:

- `topic`
- `entity`
- `kind`
- `predicate`
- `temporal`
- `retrieval`

Structural axes additionally include `scope` and `source_layer`.

Schema v4 keeps the facet table extensible: SQLite no longer hard-codes the
dimension whitelist, while application-level validation remains bounded.

The online path is:

```text
query
 -> deterministic normalization
 -> bounded faceted classification
 -> L3 SQL candidate narrowing
 -> verified current L2 / referenced L0 evidence
 -> safe dedupe + hard item/character budget
 -> evidence-only model context
 -> local Qwen
```

Post-turn L3 maintenance is opt-in, runs after the user-visible answer and adds
no mandatory model inference.

## Frozen invariants

- L2 is authoritative for current structured facts.
- L3 is reconstructible and non-authoritative.
- Internal L3 tags are never model-visible.
- Unknown/unclassified reads fail open to the ordinary baseline retrieval path.
- Superseded L2 facts are historical and excluded from current retrieval.
- Explicit predicate matches may narrow same-entity L2 siblings.
- Same-entity L0 narration is shadowed only when current L2 fully covers the
  requested predicates; incomplete coverage keeps L0 available.
- L3 read/index switches remain default-OFF unless explicitly enabled.
- No vector database, graph database or additional model call is required.

## Accepted functional evidence

### Offline regression

Final closure commit under test:

`d8f6c7522eeacda9044453fdeb4b0558352ec798`

Final TEMP-only suite:

- **8/8 PASS**
- `ModelCalls=0`
- `ProductionMemoryTouched=False`

Covered areas include:

- L2 regression compatibility;
- L3 store/schema migration;
- deterministic bounded tagging;
- planner/context compilation;
- runtime adapter;
- post-turn indexing;
- predicate facet behavior;
- schema-v4 L0 byte locator;
- UTF-8 byte-offset handling;
- stale-locator rejection;
- authoritative scan fallback;
- restart persistence.

### LIVE2 broader retrieval corpus

Five retrieval shapes passed the mandatory pre-inference gate:

| Case | L3 retrieval shape |
|---|---|
| single current | `predicate=os`, L2=1, L0=0 |
| two current | `predicate=cpu_count,ram_gb`, L2=2, L0=0 |
| corrected current | `predicate=os`, L2=1, L0=0 |
| topic-only L0 | L2=0, L0=1 |
| no-match | `no_query_facets`, exact baseline fallback |

The 20-call AB/BA live corpus produced semantically correct answers in all
five cases. The original no-match harness reported a false negative because its
regex accepted `no information` but not the equivalent answer
`No specific information is available ...`.

A focused no-match retest then passed:

- 4/4 correct;
- baseline/L3 prompt parity: 1492 tokens / 6805 chars;
- L3 state: `no_query_facets`;
- production memory untouched.

### Prompt/context effect at matched correctness

| Case | Baseline prompt tokens | L3 prompt tokens | Delta |
|---|---:|---:|---:|
| single current | 1113 | 972 | **-12.67%** |
| two current | 1119 | 999 | **-10.72%** |
| corrected current | 1115 | 974 | **-12.65%** |
| topic-only L0 | 1522 | 1522 | 0% |
| no-match | 1492 | 1492 | 0% |

Model-visible characters also fell by about 7–8% in the three narrowed cases
and remained exactly non-increasing in the two parity cases.

These results establish selective prompt reduction at matched correctness for
the tested eligible retrieval shapes. They do **not** establish a universal
whole-workload speedup.

## L0 source-locator closure

A pre-optimization measurement demonstrated that linear JSONL L0 resolution
was material enough to justify one final optimization.

Schema v4 adds a reconstructible locator:

```text
L3 L0 item -> conversation file + byte offset + byte length
```

The runtime treats this only as a verified optimization hint:

1. resolve the referenced file and bounded byte range;
2. decode strict UTF-8 JSON;
3. verify `event=turn`, `epoch` and `turn_id`;
4. use the row only when all checks match;
5. otherwise fall back to the authoritative linear JSONL scan.

Final synthetic microbenchmark, 3 repetitions, exact evidence parity:

| Turns | JSONL size | Median scan | Median locator | Median saved | Ratio |
|---:|---:|---:|---:|---:|---:|
| 500 | 0.117 MiB | 81.56 ms | 5.62 ms | 75.94 ms | 14.52x |
| 5,000 | 1.189 MiB | 891.71 ms | 9.56 ms | 882.15 ms | 93.26x |
| 20,000 | 4.794 MiB | 9879.59 ms | 28.52 ms | 9851.07 ms | 346.41x |

This is a **source-resolution microbenchmark**, not a claim that complete
conversation turns become 346x faster.

Focused live `topic_l0` smoke after locator integration:

- 4/4 answers correct;
- baseline and L3 both 1522 prompt tokens / 6927 visible chars;
- L3 shape remained L0=1, L2=0;
- locator present;
- exact prompt parity;
- production memory untouched.

## Known limitations

1. **Classification is deterministic and bounded, not semantic-general.**
   Unknown vocabulary can fall back to the baseline rather than being
   intelligently inferred.

2. **Entity/predicate pairing is intentionally conservative.**
   The strongest predicate filtering is used for one recognized entity.
   Complex multi-entity questions may retain broader ranking to avoid unsafe
   cross-product assumptions.

3. **L0 locators are created for newly indexed turns.**
   Older/pre-v4 L3 data can lack locators; correctness is preserved by the
   scan fallback. Full historical locator backfill is not required for closure.

4. **Moved or externally edited conversation logs can stale a locator.**
   Verification rejects the stale pointer and reverts to authoritative scan.

5. **No universal latency claim.**
   Live wall times showed strong cold/warm/cache effects; prompt/context
   reduction and source-resolution microbenchmarks are the accepted evidence.

6. **L3 remains opt-in/default-OFF.**
   Freeze does not mean automatic promotion to all deployments or `main`.

7. **No vector/graph/agentic expansion is part of this closure.**
   Such work requires new measured need and a separately versioned scope.

## Closure decision

All accepted L3 milestones are complete:

| Milestone | Weight | Closure |
|---|---:|---|
| architecture + reconstructible store | 15% | PASS |
| deterministic tagging | 10% | PASS |
| planner/dedupe/budget | 15% | PASS |
| runtime integration/fallback | 15% | PASS |
| automatic indexing/corrections | 15% | PASS |
| first live proof | 10% | PASS |
| broader LIVE2 validation | 15% | PASS |
| hardening + source locator + closure | 5% | PASS |

**Engineering closure: 100/100.**

## Next milestone

Proceed to **L4 / Local Epistemic Balancer**.

Do not reopen frozen L2 or L3 tuning by default. Any material defect should be
handled as a new versioned follow-up rather than moving the frozen boundary.
