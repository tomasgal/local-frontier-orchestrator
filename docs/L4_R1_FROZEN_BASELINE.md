# L4-R1 Frozen Baseline — Epistemic Observation Store

**Closure date:** 2026-10-13  
**Accepted public runtime commit:** `d2e0c005b9f4907a4f3d9c47ae4610ca39386446`  
**Development branch:** `v9.6-l4-r1-store`  
**Immutable tag:** `v9.6-l4-r1-frozen`  
**Status:** CLOSED for the L4-R1 observation-store scope.

## Decision

L4-R1 is accepted and frozen as a separate SurrealDB-backed epistemic
observation store above the fixed L0-L3 baseline.

This closes only the R1 storage/API milestone. It does not claim completion of
L4-A longitudinal analytics, automatic detection, L4-P Balancer policy, or
online intervention. LFO remains fully usable without L4.

## Frozen scope

R1 includes:

- SurrealDB 3.3.0 runtime contract with persistent RocksDB storage;
- namespace `lfo`, database `epistemic`, table `observations`;
- explicit PowerShell create/read API;
- append/create semantics with schema and UPDATE/DELETE rejection;
- stable observation IDs and payload hashes;
- actor/stage/producer/phase/type/confidence/detector metadata;
- verified binding to persisted L0 sources by store identity, file, epoch,
  turn, stage and SHA256;
- bounded exact evidence excerpts;
- explicit analytic reads with store/epoch isolation and keyset pagination;
- visible Windows development-console helpers;
- isolated Linux and Windows acceptance.

R1 intentionally excludes automatic observation detection, automatic QwenChat
turn hooks, mandatory additional LLM calls, response rewriting, automatic
intervention, persistent psychological/user profiling, continuous L4 history
injection into prompts, graph/vector/plugin/WASM/MCP machinery, generalized
longitudinal claims, and a distributed L0/SurrealDB transaction or durable
retry outbox.

Observations are annotations. They are never factual evidence about the external
world merely because they are present in L4.

## Accepted evidence

The accepted store implementation was tested against real SurrealDB 3.3.0 on
Linux / PowerShell 7.4.6 and Windows PowerShell 5.1.19041.7725.

Final store gate:

- 39/39 checks PASS on Linux;
- 39/39 checks PASS on Windows after explicit strict UTF-8 HTTP decoding;
- independent concurrent clients covered;
- Unicode including a supplementary character covered;
- nullable confidence covered;
- idempotency and payload conflict behavior covered;
- pagination covered;
- schema UPDATE/DELETE rejection covered;
- source integrity and L0 linkage covered;
- authentication and logical store/epoch isolation covered;
- outage outcome covered;
- persistence after forced server-process termination/restart covered;
- `ModelCalls=0`;
- `ProductionMemoryTouched=False`.

The accepted store-test commit was
`dae21d0bafa17a5a5c0291f28c5fe4f3a00116e0`.

The public runtime was privacy-sanitized and squashed onto the published L0
prerequisite. Public runtime commit
`d2e0c005b9f4907a4f3d9c47ae4610ca39386446` preserves the accepted store
implementation bytes. Host-specific names and deployment paths were removed
from public launcher/documentation surfaces. The public PowerShell surface
passed parser checks and the public privacy boundary check. The 39-check store
gate was not repeated solely for launcher/documentation sanitization.

The visible Windows server workflow was manually exercised before publication.
Its public sanitization removes deployment-specific guards/paths without
changing the R1 store protocol.

## Frozen invariants

- L0 remains authoritative conversation/evidence provenance.
- L2 remains authoritative current structured factual state.
- L3 remains reconstructible selective retrieval metadata.
- L4 observations remain non-factual annotations.
- R1 adds no mandatory model call.
- R1 does not inject observation history into ordinary prompts.
- R1 does not automatically alter a user-visible answer.
- Store creation/reads are explicit operations.
- Source integrity must resolve back to persisted L0.
- Automatic detection and intervention remain outside the frozen R1 contract.

## Known limitations

- Process-restart persistence is not proof of sudden power-loss durability.
- L0 and SurrealDB do not share a distributed transaction.
- There is no durable automatic retry/outbox; an unacknowledged RPC may remain
  `UNKNOWN`.
- Database-level credentials are trusted for the L4 database; store/epoch
  filters are logical isolation, not per-user authorization.
- Confidence is detector-reported metadata, not a calibrated probability.
- Explicit analytic pagination is stable by ID but is not a chronological or
  snapshot export protocol.
- R1 has no evidence about detector quality because it deliberately implements
  no automatic detector.
- R1 has no evidence that epistemic interventions improve answers because it
  deliberately implements no intervention path.

## Reopen policy

Do not reopen the frozen R1 store/API contract for routine tuning.

Reopen only for a demonstrated material defect in the frozen contract or
implementation, or for a new explicitly versioned storage/API requirement.
L4-A analytics and L4-P policy work are higher-layer follow-ups, not reasons to
mutate R1 by default.

## Smallest next step

Create a bounded explicit annotation pilot:

1. select a small set of persisted L0 turns;
2. have a human/offline producer create observations through the frozen R1 API;
3. verify each observation resolves back to its exact L0 source;
4. inspect a small set of explicit queries and interaction links;
5. record what analytics are actually useful.

This produces real design evidence for L4-A while preserving all R1 boundaries:
no automatic detector, no online intervention, no prompt injection and no
mandatory model call.