# L3 Historical Candidate Checkpoint — selective tagged SQL retrieval

**Date:** 2026-10-12  
**Branch:** `v9.5-l3-selective-index`  
**Checkpoint base:** `2e93bd0daa11023a03ba44fa2c387360b72c0d45`  
**Status:** historical checkpoint. L3 is now closed; see `L3_FROZEN_BASELINE.md`.

## Candidate solution

L3 is a separate, reconstructible SQLite metadata/index layer over L0/L2 references. It does not replace L0 or L2.

Online path:

```text
user query
  -> deterministic normalization
  -> bounded topic/entity/kind classification
  -> L3 SQL candidate narrowing
  -> current L2 / referenced L0 evidence resolution
  -> safe dedupe + hard context budget
  -> evidence-only model context
  -> local Qwen
```

Post-turn maintenance is opt-in and runs after the user-visible answer. It adds no mandatory LLM call.

Key invariants:

- L2 remains authoritative for current structured facts;
- L3 is reconstructible derived metadata;
- internal tags are not model-visible;
- unknown/unclassified queries fail open to the baseline retrieval path;
- historical L2 facts are marked `historical + retrieval:exclude`;
- equally relevant current L2 evidence outranks more verbose L0 narration;
- L3 is default-OFF unless explicitly enabled.

## Accepted evidence so far

### Offline gates

- R1 store: **3/3 PASS**
- R2 deterministic tagging: **4/4 PASS**
- R3 planner/context compiler: **5/5 PASS**
- runtime context gate: **6/6 PASS**
- automatic post-turn indexer: **7/7 PASS**

All offline acceptance runs used TEMP-only fixtures with `ModelCalls=0` and `ProductionMemoryTouched=False`.

### First valid live gate

Commit under test: `458ea93e20280ea87dd410ecd6199bcf2893980c`  
Ollama: `0.34.4`  
Model: `qwen3.5:4b-q4_K_M`  
Paired repetitions: 2 per variant.

Matched-correctness result:

| Metric | Baseline | L3 | Delta |
|---|---:|---:|---:|
| L2 items injected | 4 | 1 | selective |
| model-visible chars | 5519 | 4618 | **-16.33%** |
| prompt tokens | 1165 | 973 | **-16.48%** |
| correct answers | 2/2 | 2/2 | unchanged |

Raw wall-time mean was lower for L3, but that result is **not accepted as a general speedup claim** because prompt-eval timings show strong cold/warm/cache effects.

Accepted finding:

> On an eligible current-state query, L3 reduced measured model input by 16.48% at matched correctness while preserving baseline fallback behavior elsewhere.

## L3-LIVE2 broader live validation — substantive PASS

Commit under test: `e71bd7dc4645563df77b9691e3f364ce8eef0aaa`  
Model: `qwen3.5:4b-q4_K_M`  
Paired repetitions: 2 per variant, AB/BA order.  
Total model calls: 20.

Mandatory offline/pre-inference retrieval-shape gate: **5/5 PASS** with
`ModelCalls=0` and `ProductionMemoryTouched=False`.

| Case | Baseline -> L3 evidence | Prompt tokens | Model-visible chars | Correctness |
|---|---|---:|---:|---|
| single current | L2 4 + L0 2 -> L2 1 + L0 0 | 1113 -> 972 (**-12.67%**) | 5032 -> 4617 (**-8.25%**) | 4/4 paired samples correct |
| two current | L2 4 + L0 2 -> L2 2 + L0 0 | 1119 -> 999 (**-10.72%**) | 5055 -> 4697 (**-7.08%**) | 4/4 paired samples correct |
| corrected current | L2 4 + L0 2 -> L2 1 + L0 0 | 1115 -> 974 (**-12.65%**) | 5048 -> 4633 (**-8.22%**) | 4/4 paired samples correct; historical value absent |
| topic-only L0 | L0 1 -> L0 1 | 1522 -> 1522 | 6927 -> 6927 | 4/4 paired samples correct |
| no-match | exact baseline fallback | 1492 -> 1492 | 6805 -> 6805 | 4/4 answers semantically correct |

The automated run exited FAIL only because the `no_match` assertion accepted
`no information` but not the model's equivalent wording
`No specific information is available ...`. Baseline and L3 produced the
same semantically correct LOCAL answer and used the same 1492-token / 6805-char
prompt. This is classified as a **test-harness false negative**, not a runtime
correctness failure. The intended no-match contract had already passed the
pre-inference exact-context fallback gate with `l3_status=no_query_facets`.

Wall-time observations are not accepted as a general speedup claim. The AB/BA
samples show strong cold/warm/cache effects (for example the first baseline
single-current call was 91.94 s while warm calls were much shorter).

Accepted finding:

> LIVE2 preserved correctness across all five retrieval shapes while reducing
> prompt tokens by about 10.7-12.7% on the three cases where predicate-aware L3
> narrowed evidence. Topic-only and no-match cases remained non-increasing and
> preserved their baseline context.

## Engineering progress

**Final engineering progress: 100%.**

This is a milestone-based engineering estimate, not a statistical measurement.

| Milestone | Weight | State |
|---|---:|---|
| architecture + separate reconstructible store | 15% | done |
| deterministic tagging | 10% | done |
| candidate planner + dedupe + budget | 15% | done |
| opt-in runtime integration + fail-open fallback | 15% | done |
| automatic post-turn indexing/correction maintenance | 15% | done |
| first valid end-to-end live proof | 10% | done |
| broader multi-case live validation | 15% | **done — LIVE2 substantive PASS** |
| closure hardening + freeze/publish decision | 5% | **done** |

Completed weighted milestones: **100/100**.

The optional L0 source-locator/I/O optimization is **not required for L3 functional closure**. It should be attempted only after the broader live corpus confirms that prompt/context selection is robust enough to justify further optimization.

## Historical test plan (completed)

The plan below is retained as development history. LIVE2, hardening, source-locator measurement, and closure are complete. The normative state is `docs/L3_FROZEN_BASELINE.md`.

### Previously required LIVE2 plan

#### Gate L3-LIVE2 — broader live corpus

Run the same baseline-vs-L3 comparison on at least these five retrieval shapes:

1. **single current fact** from an entity with several L2 facts;
2. **two-fact answer** from the same entity;
3. **correction/current-state** query where a historical predecessor exists and must remain excluded;
4. **topic-only L0 retrieval** where no current L2 fact is sufficient;
5. **unclassified/no-match** query that must use exact baseline fallback.

For each case:

- pre-inference probe must confirm the intended retrieval shape;
- baseline and L3 must receive the same user question and local model;
- answer correctness must be gated before efficiency claims;
- record model-visible chars, `prompt_eval_count`, output tokens, context assembly time and wall time;
- use alternating AB/BA order;
- use at least 2 paired repetitions for mechanism validation; increase to >=3 only if variance analysis is needed;
- abort expensive inference when offline/preflight shape is wrong.

### Acceptance for LIVE2

PASS requires:

- no correctness regression across all five cases;
- exact baseline fallback in the no-match case;
- no historical L2 leakage in the correction case;
- no internal L3 metadata in model-visible context;
- eligible cases show non-increasing prompt tokens, with a clear reduction where L3 narrows evidence;
- L3 adds no mandatory model call;
- production memory remains untouched.

Do **not** require a universal latency speedup. Latency remains secondary until cache/warm-state effects are explicitly controlled.

### Gate L3-HARDEN

After LIVE2:

- review false-positive/false-negative tagging cases;
- verify multi-topic and multi-entity bounds;
- verify idempotent post-turn indexing under repeated process restarts;
- confirm current/historical transitions remain reconstructible from L0/L2;
- add any demonstrated regressions only; avoid speculative complexity.

### Gate L3-FREEZE

Freeze/publish only when:

- LIVE2 passes;
- no correctness regression is observed;
- fallback contract is preserved;
- automatic indexing is deterministic/reconstructible;
- default-OFF migration/config behavior is documented;
- known limitations are explicit;
- candidate tag/manifest/closure document are created.

## Decision after LIVE2

If LIVE2 passes, choose one of two paths:

- **Freeze first:** publish L3 candidate and defer L0 source-locator optimization as a post-freeze performance enhancement.
- **One more optimization gate:** add an L0 source locator/offset index only if JSONL scan cost is demonstrated to matter materially in measured context assembly.

The default recommendation is **freeze first unless measured I/O cost justifies another optimization cycle**.
