# L4-P2 Evaluation Results

**Reference model:** `qwen3.5-4b-core-cpu5k:latest`  
**Ollama:** `0.34.4`  
**Context:** `5120`  
**Live model calls:** `16`

## Result

- active paired cases: **8**
- CONTROL target passes: **4 / 8**
- INTERVENTION target passes: **8 / 8**
- improvements: **4**
- regressions: **0**
- NO_ACTION request identity: **2 / 2**
- closure decision: **PROMISING_BOUNDED_EFFECT**

The decision rule was frozen before model calls:

- `PROMISING_BOUNDED_EFFECT`: intervention >= 6/8, at least two improvements,
  zero regressions;
- `NO_CLEAR_INCREMENTAL_EFFECT`: zero regressions and intervention no worse
  than control without meeting the promising rule;
- otherwise `MIXED_OR_REGRESSIVE`.

This is evidence about a synthetic exact-choice intervention protocol, not an
estimate of real-conversation effect size or user benefit.