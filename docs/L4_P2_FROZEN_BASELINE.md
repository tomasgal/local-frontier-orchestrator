# L4-P2 Frozen Baseline - Bounded Intervention Experiment

**Closure date:** 2026-10-13  
**Development branch:** `v9.6-l4-p2-intervention`  
**Immutable tag:** `v9.6-l4-p2-frozen`  
**Dependency:** `v9.6-l4-p1-frozen`  
**Status:** CLOSED for the bounded synthetic intervention experiment.

P2 preserved the exact frozen P1 Git dependency, including documenting rather
than mutating the discovered P1 byte-lock portability defect.

Live summary:

- model calls: **16**
- CONTROL: **4 / 8**
- INTERVENTION: **8 / 8**
- improvements: **4**
- regressions: **0**
- NO_ACTION request identity: **2 / 2**
- decision: **PROMISING_BOUNDED_EFFECT**
- detector calls: **0**
- automatic R1 writes: **0**
- production memory touched: **False**

The P1 declared rules SHA-256 `d837c9b6d62e387c6482b83449495d5dc5c4d2092976ef459892bceabe2ee7c3` is inconsistent with
the committed canonical rules SHA-256 `a5da19563afcb4ac9698acce7aff423daf9b3e400cfe5af40f3a46aea4fe0106`. Exact P1
dependency identity was established by immutable tag, commit and Git blob; the
experiment-local compatibility lock was never committed.

## Decision boundary

P2 does not establish ecological intervention efficacy, longitudinal benefit,
detector accuracy, a user trait, or authorization for automatic runtime
deployment.

## Next step

Proceed only to a separately versioned broader replication step, preferably
cross-host and with less synthetic natural-language tasks, before any runtime
integration.