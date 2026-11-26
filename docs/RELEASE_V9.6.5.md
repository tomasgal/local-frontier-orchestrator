# LFO v9.6.5 — research experiment tooling

**Release date:** 2026-11-26  
**Type:** backwards-compatible research-tooling release  
**Runtime:** accepted v9.6.4 security behavior, v9.6.3 Windows runtime behavior and L0–L4 semantics are retained.

v9.6.5 adds three narrow capabilities outside the normal chat path: a mediator parameter-sweep schema/expander, a frozen-response/replay-bank schema/validator, and a paired neutral-vs-leading model-audit manifest/analyzer.

The research layer explicitly separates spontaneous model error from framing-induced behavior and allows controlled misleading stimuli without presenting them as evidence of sycophancy. Mediator tuning remains a pilot-time activity; the chosen configuration must be frozen before confirmatory data collection.

## Runtime and bootstrap boundary

- L0–L4 semantics are unchanged.
- P1/P2 remain OFF in the normal response path.
- Local/frontier routing behavior is unchanged.
- Bootstrap logic is unchanged; only the declared runtime/source contract advances to v9.6.5.
- Existing installations do not require migration to continue working.
- The new research helper performs zero model calls and does not touch production memory.

## Validation

Release acceptance requires Windows PowerShell 5.1 parser acceptance, deterministic `Test-ResearchToolingV965.ps1` PASS, and the inherited Codex installer-integrity regression PASS. No debiasing-efficacy claim follows from these tooling tests.
