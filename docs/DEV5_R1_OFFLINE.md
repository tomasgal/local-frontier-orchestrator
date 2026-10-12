# R1 offline regression preparation (2026-10-12)

> **Superseding closure — 2026-10-12:** L2 is complete and frozen at `v9.4-l2-frozen`. Read [L2_FROZEN_BASELINE.md](L2_FROZEN_BASELINE.md) for the accepted profile, R1/R3/R4/R5 evidence and limitations. Earlier candidate, PENDING, PAUSED and next-test instructions below are historical. Do not restart L2 tuning automatically; next work is L3 design, then L4. The full 2414-character write policy is restored; A+B is accepted selectively, grouped extraction and C are not adopted.


Base source: `67173eaa18c648605dc92759b57c4e38c1a41ab5`, branch
`v9.4-dev5-compact-read`. The initial patch extended tests only. The follow-up
candidate also repairs three demonstrated LOCAL authorization defects. Policies,
configuration, historical fixtures, main and frozen DEV3 are unchanged.

**Initial regression execution: FAIL.** User-provided Windows PowerShell 5.1
output for test commit `1c69a1ee46d211608458ac05036ace890de3fbed` and patch
SHA-256 `a1e43ac459c88e961862c246c39f5394bb3fc26889d36e02459012b6fa7ccc21`
reports UNSAFE ACCEPT for all three new negative cases below. The suite evaluates
all 26 cases before its aggregate failure; the other 11 suites did not run.
This proves authorization defects, not a physical production-memory write.

**Authorization repair: targeted Windows PASS; full R1 incomplete.** User output
for commit `549f01e942d882798c1d41ca2ba324952f71c9be`, patch SHA-256
`5d2f3cf46344bf274ee8f4bbe1a201f3ce4163780e73616e63776949d19977e0`, shows PASS
for adversarial authorization, authority/persistence integration and mixed
runtime persistence. The fourth suite failed at empty-epoch; eight suites did
not run. The reported guard=False is the expected value for zero retrieved items.
Static inspection identifies a stale full-policy assertion: semantic-boundary
and compact-read tests searched the opening sentence of the old policy, absent
from the checked-in 2040-character candidate.

**Policy-assertion repair: INCONCLUSIVE pending Windows execution.** Those two
tests now require the full checked-in template with independently specified
LOCAL evidence scope, allowing LF/CRLF line endings. This strengthens assembly
verification rather than replacing the old heading with another heading.
Boundary failures now print all actual/expected checks. Authorization runtime,
policy text and config are unchanged from the targeted passing repair.
No model call was performed; a complete current R1 PASS remains pending.

The repair binds OS values to a local runs/OS assertion, CPU counts to their
adjacent CPU attribute, and Boolean state to a contiguous property assertion.
It contains no entity names, target values or whole-prompt exceptions. It is
still a bounded lexical gate: arbitrary predicates and general entailment
are not solved. Some valid alternative phrasings can be conservatively rejected.
Existing adversarial pairs remain unchanged. The existing authority integration
suite now also sends the three unsafe proposals through Persist-TurnAndMemory
and checks zero new L2 facts, suppressed L1 notes and authorization trace fields
in three independent synthetic TEMP stores; its original positive remains.

## Minimal additions

`Test-Dev5LocalWriteAdversarial.ps1` keeps all 14 negative and 6 positive cases,
and adds three pairs with identical evidence and independent semantic oracles:

| Exact evidence | Reject proposal | Accept proposal |
|---|---|---|
| ORION runs Ubuntu 24.04, uses PostgreSQL 16. | SET_TEXT ORION / os / PostgreSQL 16 | SET_TEXT ORION / os / Ubuntu 24.04 |
| ORION has 64 GB RAM and 32 CPU cores. | SET_INTEGER ORION / cpu_count / 64 | SET_INTEGER ORION / cpu_count / 32 |
| ORION runs Ubuntu 24.04, nightly backups are enabled and audit logging is disabled. | SET_BOOLEAN ORION / nightly_backups_enabled / false | SET_BOOLEAN ORION / nightly_backups_enabled / true |

The suite now requires 17 denials and 9 acceptances. It evaluates all cases
before throwing, and prints JSON containing each prompt, typed proposal,
expected/actual authorization, reason and verdict. The existing runner captures
this in its TEMP log. There is no expected-failure exemption and no SQLite
write in this suite. All three unsafe acceptances were reproduced before the
repair; the new candidate must reject them while retaining all positives.

`Test-PromptPolicyOptimization.ps1` additionally checks that all five experimental
switches are present, Boolean and false in the unmodified repository config.
The compact-read suite sets several flags explicitly in its fixture, so its
default-schema assertions alone did not establish this repository-default contract.

## Existing runner coverage

`tests/Invoke-Dev5OfflineRegressions.ps1` remains the single entry point, with
the same 12 suites, in this order. Do not run the policy test again merely
because it has a separate filename.

| Suite (Test- prefix and .ps1 suffix omitted) | Covered contract |
|---|---|
| Dev5LocalWriteAdversarial | Negative evidence, current correction side, subject/value boundaries; three new attribute-binding pairs |
| Dev5LocalModelWriteAuthority | Independent LOCAL authorization, positive declarations, misrouted read and three misbindings; actual TEMP persistence and L1/trace audit; separate FRONTIER route policy |
| Dev5MixedRuntimePersistence | Opt-in/off mixed persistence, source turn/scope/history, duplicate accounting, ambiguity and store-failure containment |
| Dev5SemanticReadBoundary | Retrieval/guard/A+B eligibility, scope/history exclusions, lower-trust message placement, unchanged stored facts |
| Dev5SqliteAtomicity | Transactions, duplicates, injected rollback failures, writer lock, alias race and scope isolation |
| LfoMemoryStore | Storage/schema, typed operations, relations, correction history/provenance, invalid-batch rejection and scope |
| Dev5MixedUserProvenance | Exact current-user spans, unsupported-input rejection, stored-data decoy, simulated scoped supersession |
| Dev5CompactRead | Full/compact schemas, A/B policy assembly and eligibility, C fallback; source parsing without CLI launch |
| Dev4L2Retrieval | Current scoped facts, relations, retrieval budgets, missing entity and read-side write suppression |
| Dev4Observability | Synthetic telemetry units, L0 retrieval and immutable pre-turn context cache |
| PromptPolicyOptimization | Source parsing, temperature, 2040-character policy/anchors, declarative acknowledgement; five default-OFF flags |
| Dev5VsDev3Comparator | Synthetic comparator contract and rejection tests; no performance measurements |

Module loading and PowerShell parsing are distributed across these suites.
Their stores/logs use synthetic TEMP locations, not the production memory path.
The runner requires the DEV5 branch and a clean worktree, records its exact HEAD,
creates a fresh TEMP report directory and stops on the first failing suite.
If the first suite fails, the remaining 11 are **NOT RUN / INCONCLUSIVE**,
not failed and not passed. Its Boolean `passed=false` also covers incomplete
execution; inspect the error/log before assigning a product FAIL.

## Windows execution and evidence

First prepare a clean checkout containing this patch, record the resulting full
commit SHA and identify the actual Windows host/PowerShell version. Use a fresh
Windows PowerShell 5.1 process to avoid stale native interop classes. No Ollama,
host model profile or production-memory settings are required: each suite imports
its repository configuration and establishes its own test state.

After replacing `<PIN>` with that full committed revision, run this single line
from the prepared checkout:

```powershell
$ErrorActionPreference='Stop'; if ((git rev-parse HEAD).Trim() -cne '<PIN>') { throw 'Wrong R1 source pin' }; powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Invoke-Dev5OfflineRegressions.ps1; if ($LASTEXITCODE -ne 0) { throw 'R1 stopped; preserve the reported TEMP logs and inspect the failure' }
```

Retain `acceptance-report.json`, the failing suite log (if any), the commit SHA
and host/runtime identification. The report binds results to source; the new
case JSON binds a failure to reproducible input and proposal. A missing runtime,
setup error or unexecuted check is INCONCLUSIVE. An executed violated contract is
FAIL. PASS requires the positive and negative postconditions to be met.

## Remaining boundaries and next decision

The adversarial pairs exercise authorization only. New authority integration
cases check fact counts, current-turn additions, L1 suppression and trace for
these three inputs and passed on the repair commit above. They do not audit every
SQLite table or byte-level file identity. General
language entailment, every malformed scalar/operation combination and L0/L2
crash consistency are not exhaustively tested by this suite. The runner's
no-model/no-production fields are declarations of the curated harness, not OS
network or filesystem instrumentation.

If an unsafe acceptance is reproduced, retain the red test and repair only the
demonstrated boundary; preserve the paired positives. Re-run a targeted suite
only for the repair, then the full runner for acceptance of the new exact pin.
Do not weaken the oracle or add phrase-specific exceptions to force a pass.

R2 readiness is pending R1 evidence and any demonstrated defect repair. The
smallest planned model validation remains the unchanged five-case
`Test-L2Extraction.ps1` probe, with semantic expectations, model digest and
runtime/config fixed before its five calls. It does not validate runtime write
authorization or SQLite integration. R2 and all other model runs require
separate explicit authorization. The old performance experiment remains
CLOSED / DEFER; this R1 work does not restart it.
