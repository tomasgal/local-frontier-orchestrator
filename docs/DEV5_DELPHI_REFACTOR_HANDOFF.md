# Selective refactoring goal and chat handoff

Tracking goal: [GitHub issue #3](https://github.com/tomasgal/local-frontier-orchestrator/issues/3).

Updated: 2026-10-11. Working branch: `v9.4-dev5-compact-read`.
Source reviewed before this change: `6f02466b47c4d08153503bc0707263f2ad58be0b`.
Historical DEV3 reference: `a34658b81742596520da844618b5bb39f3329279`.

## Goal and current authorization

Minimize the total cost of useful, correct local-first answers while preserving memory integrity and reducing configuration/maintenance complexity. Use a frozen DEV3 reference and selectively retain or transfer justified improvements. The running experimental branch already contains newer authorization fixes; do not revert those fixes to recreate DEV3 behavior. The historical reference remains immutable, and main remains v9.3.

The user requested a GitHub handoff, a staged refactoring roadmap and immediate shortening of the L2 extraction policy to **2040 characters**. Only that policy change, its structural regression and documentation are implemented in this checkpoint. The broader refactoring below is planned work. No model benchmark, production-memory change, main merge or automatic feature promotion is authorized by this checkpoint.

This plan comes from a three-round **simulated Delphi review by one assistant**, considering inference, semantic memory, reliability, experimental methodology and human–AI interaction. It is a prioritization judgment, not independent expert consensus or empirical validation.

## Implemented now: L2 policy candidate

- `policy/l2-structured-memory.txt`: **2414 -> 2040 characters**, a 374-character / 15.49% reduction.
- Counting contract: decoded file text, CRLF normalized to LF, final LF included, before `{{L2_EVIDENCE_SCOPE}}` substitution. The final LF is removed by runtime `TrimEnd()`, giving 2039 template characters before substitution. Actual expanded prompt/token counts are separate measurements.
- There is no numeric `L2PolicyChars` runtime setting. It is a measured property of the policy file.
- The current source file confirms the user's 2414 baseline. The earlier approximate 2458 figure in experiment notes describes a different reported count/checkpoint and is not used as this change's baseline.
- Shorten phrasing while retaining evidence scope, current-pass acceptance, rejection of copied/old/uncertain facts, L1/L2 responsibilities, all five operation types, integer/real/boolean formatting, correction and deduplication rules, surface identity, predicate naming, type hints and empty-result behavior.
- All five complete examples are preserved byte-for-byte.
- `tests/Test-PromptPolicyOptimization.ps1` now checks the exact LF-normalized budget, one scope placeholder and the retained contract/example anchors. Existing temperature, declarative-fallback and duplicate-rule checks remain.
- This changes the shared extraction template used by normal LOCAL writes and post-FRONTIER synthesis. B-eligible lean reads replace that template; rerun the existing A/B structural regressions rather than reusing old prompt-reduction figures.

**Acceptance:** IMPLEMENTED; static text checks completed; Windows offline acceptance PENDING; model extraction and end-to-end performance PENDING. The tool host could not start Windows shell processes (`CryptUnprotectData` process-creation error), so no PowerShell test PASS is claimed. Static checks are not PowerShell parsing or model tests. No Ollama calls were made.

The user's explicit 2040 request supersedes the review's recommendation to keep D01 unchanged. It authorizes this candidate's implementation, not a claim of semantic equivalence or speedup. Prior failures of shorter policies remain relevant negative evidence. Preserve the previous policy at commit `6f02466b47c4d08153503bc0707263f2ad58be0b`, blob `bcf78e1661010cf19555460db5d9b8a6efbacaf4`, for comparison or isolated rollback. Do not weaken extraction expectations to make the new policy pass.

## Evidence to carry into the next chat

| Mechanism | Evidence and limits |
|---|---|
| DEV3 typed L2 writes | Targeted functional validation across two Windows host classes: multi-fact writes, corrections, scope/provenance, persistence and atomicity. The full-policy baseline was restored after two shorter candidates failed. |
| DEV3 small optimizations | Temperature 0.10, removal of 871 duplicate instruction characters and narrow deterministic acknowledgement passed their recorded fixtures. Their individual causal and portable speed gains are unproven. |
| DEV4 read path | Bounded current-fact retrieval and deterministic suppression of model echo writes/L1 notes passed offline and isolated live checks. Mixed new claims can be omitted. |
| DEV5 A+B | Implemented; isolated live functional checks passed. A observed output 294 -> 45 tokens; B observed input 1641 -> 1042. Historical observations do not establish representative full-loop gains or validate the new 2040 policy. |
| C | Matched C-off/C-on both ignored one adversarial marker. Added protection and general robustness are unproven. Keep OFF. |
| Mixed current-user write | Narrow exact-grammar live case passed; G2 atomic alias/scope checks, duplicates and failures passed offline. General natural-language coverage remains absent. |
| LOCAL write authorization | Already implemented independently of read eligibility. Core 12/12 offline acceptance at `370827f6793b59062aae841c9cf1cc439dadf6de`; no post-hardening live acceptance. Those results predate this policy change. |
| DEV3/DEV5 performance | Component measurements are small and noisy; they do not prove whole-turn regression or gain. One live pair was faster on DEV5 but A+B never activated and a read request caused one model-origin write. The historical SQLite row is still unaudited. |

The old 110.953-second timing anomaly remains unexplained. Do not attribute it to orchestration. The five-case benchmark and synthetic comparator are prepared, not completed end-to-end evidence. No Raspberry Pi, energy or multi-node scaling claim is established.

## Roadmap by implementation and validation horizon

### 1. Implement directly — this checkpoint

- [x] Publish this goal/handoff and link it from the roadmap and G2 entry point.
- [x] Implement the explicitly requested 2040-character candidate and exact structural checks.
- [x] Preserve all five examples, existing authorization/transaction protections, temperature 0.10, removed duplicate instructions and default-OFF read/A/B/C/mixed switches.
- [x] Separate historical evidence from current candidate status.

### 2. Short validation — next bounded work

- [ ] On the exact committed source, run `Test-PromptPolicyOptimization.ps1` and the existing `Invoke-Dev5OfflineRegressions.ps1` wrapper. This is model-free, TEMP-only work; a previous 12/12 result is not current acceptance.
- [ ] Once a bounded model check is deliberately scheduled, run the **unchanged five-case** `Test-L2Extraction.ps1` probe. It calls Ollama five times and does not write memory. Inspect full semantic subject/predicate/type/value/relation output; valid/rejected counts alone are insufficient. Historical counts are 4/0, 3/0, 1/0, 0/0, 3/0, with an existing post-FRONTIER CPU/model predicate ambiguity.
- [ ] The extraction probe prints observations; it does not enforce all semantic expectations automatically. Record explicit human/independent semantic acceptance for each case.
- [ ] Stop on a semantic regression, preserve the failure and restore the prior policy alone if needed. Do not repeat indefinitely or adjust fixtures after seeing failures.

### 3. Consider before further implementation

- [ ] Evaluate one coherent read profile for A+B, deriving schema and policy together. Keep separate experimental controls where needed for attribution; do not add a classifier merely to increase activation.
- [ ] Assess an explicit typed update interface reusing MemoryStore instead of extending the special English question-plus-RAM grammar. Compare user effort and lost automatic memory capture before replacing behavior.
- [ ] Inspect predicate drift from existing evidence; consider a small unambiguous mapping only if real failures justify it.
- [ ] Keep C, L3, epistemic mediation, temperature sweeps, retrieval-limit sweeps and background-compaction architecture out of the immediate implementation scope.
- [ ] Preserve cheap diagnostic trace coverage. Do not remove observability based on unproven overhead attribution.

### 4. More comprehensive acceptance — before promotion

- [ ] Independently audit SQLite/L1 on post-hardening real Qwen reads, writes, corrections and mixed/unsupported inputs, including the new policy and FRONTIER parity.
- [ ] Separate two experiments: eligible DEV5 FULL versus A+B mechanism attribution, and the frozen five-case representative DEV3 versus DEV5 workload.
- [ ] Pin source, policy, model digest, context, runtime profile, configuration, evidence access and host state. Keep cold/warm strata separate; alternate AB/BA where feasible.
- [ ] Start with a correctness-gated pair; expand only if justified. The planned 3 pairs x 5 cases = 30 answers describes the basic one-host system comparison, including its pilot; extraction probes and separate mechanism trials have their own explicit budgets.
- [ ] Include permanent observability, authorization, retrieval, retries, non-eligible turns, persistence integrity and real A+B hit/miss frequency. Assess complete useful-turn cost, not only answer display time or component medians.
- [ ] Derive workload weights from actual usage where possible. Equal weights remain illustrative; three pairs do not guarantee statistical power.
- [ ] Require useful repeatable gains before performance promotion; postpone additional host/model performance cohorts until the first cohort warrants them. Correctness checks on supported target profiles remain necessary.
- [ ] Publish an inconclusive/negative result and keep experiments OFF when evidence does not support promotion. Do not trigger outreach from this handoff.

## Parameter dispositions carried forward

FIX retains the stated current baseline; OPTIMIZE names an active candidate; SIMPLIFY reduces mechanism/configuration scope; INVESTIGATE requests evidence; DEFER excludes immediate work. D01 is the explicit user override after the review.

| IDs | Disposition | Decision |
|---|---|---|
| D01 | OPTIMIZE | Implemented 2040 candidate; semantic acceptance pending. |
| D02 | FIX | Preserve full examples. |
| D03 | INVESTIGATE | Predicate drift and narrowly justified mapping. |
| D04 | OPTIMIZE | Reuse existing independent LOCAL authorization when selectively transferring improvements; do not reimplement it. |
| D05 | SIMPLIFY | Limit heuristic responsibility; write authority stays separate. |
| D06, D07, D08 | FIX | 0.10, removed duplication, narrow deterministic acknowledgement; successful-storage wording follows commit outcome. |
| D09 | INVESTIGATE | DEV3 net-gain attribution remains limited. |
| V01 | FIX | StructuredReadEnabled=false by default. |
| V02, V03 | OPTIMIZE | A+B remains the primary bounded performance candidate. |
| V04 | DEFER | C stays OFF; no further tuning now. |
| V05, V06, V07 | SIMPLIFY | Explicit updates; derived schema/policy rather than independent product knobs. |
| V08 | INVESTIGATE | Lower-trust evidence handling remains unresolved; C's negative finding proves neither placement safe. |
| V09, V10 | FIX | Retain current independent authorization and read-side guard. |
| V11 | SIMPLIFY | Accept safe optimization misses; avoid an expanding lexical exception list. |
| V12, V13 | FIX | Keep 6 items / 800 characters; optimality is unproven. |
| V14 | INVESTIGATE | Representative DEV5 net gain remains unknown. |
| E01, E02 | FIX | Frozen five scenarios and planned three pairs, subject to early stopping. |
| E03 | SIMPLIFY | Conditional experiment budget rather than a call-count target. |
| E04, E05, E07 | FIX | AB/BA, controlled cold/warm state, pinned runtime profile. |
| E06, E09 | INVESTIGATE | Actual workload weights and correctness-gated weighted net result. |
| E08 | DEFER | Additional performance cohorts after a promising first result. |

## Simpler architecture alternative and decision boundary

A substantially simpler alternative preserves local-first routing, L0 raw history, v9.3 L1 micro-memory and the existing transactional L2 store, but permits L2 mutation through explicit typed updates. Exact supported L2 queries can be answered deterministically. Ordinary model output carries answer/routing/L1 rather than arbitrary L2 operations.

That alternative removes automatic conversational L2 extraction, read/write/mixed classification for write authority, the RAM-specific mixed grammar and the A/B/C combinations needed to reconcile those paths. It sacrifices automatic dense-fact capture and some natural-language L2 recall; user effort must be evaluated. It is a proposal, not an implemented or validated winner.

Preferred stop/go decision remains **freeze the DEV3 reference and selectively transfer justified improvements**. Three future implementation units: (1) consolidate the protected baseline and validate this policy candidate; (2) introduce explicit typed updates only if their utility justifies the behavior change; (3) consolidate and accept or retire A+B using bounded evidence. No broader rewrite is authorized merely by listing these units.

## Resume instruction for the next chat

Read this file, then the latest section of [G2 handoff](DEV5_G2_HANDOFF.md), [ROADMAP](ROADMAP.md), [MEMORY_STRATEGY](MEMORY_STRATEGY.md), [performance experiments](DEV5_PERFORMANCE_EXPERIMENTS.md) and the existing [benchmark protocol](DEV5_VS_DEV3_BENCHMARK_PROTOCOL.md) as needed. Check the actual branch HEAD and candidate policy first. Begin with the pending cheap offline gate. Preserve historical source pins and results. Do not infer a Windows/model PASS, portable gain, or production acceptance from a successful GitHub commit.
