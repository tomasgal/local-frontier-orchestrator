# L2 complete — frozen baseline v9.4-l2-frozen

Decision date: 2026-10-12. **L2 development is closed for the accepted scope.**
This is the fixed dependency for subsequent L3 and L4 work. It combines the
validated DEV3 typed-memory substrate and accepted post-DEV3 optimizations with
selectively accepted DEV5 read-path and integrity improvements. This closure is
an engineering decision supported by bounded tests, not a claim of universal
semantic reliability or globally optimal CPU inference.

## Freeze and use

The immutable reference is tag `v9.4-l2-frozen`. Do not move or overwrite this tag,
retune its prompts, replace fixtures, or restart R1–R5 merely because a new session
begins. Read `L2_FROZEN_MANIFEST.json` for the hashes of the fixed implementation,
policies and configurations. A necessary future correction must use a new branch
and version, with its own explicit scope and evidence; it must not rewrite this
baseline. Historical DEV3 `a34658b81742596520da844618b5bb39f3329279` is also unchanged.

`main` retains the v9.3 runtime; its documentation points to this separate frozen
L2 milestone. Publishing the freeze does not deploy it to existing user memory.
The delivery branch is `v9.4-dev5-compact-read`; use the immutable tag for replay.

`config/QwenChat.config.psd1` preserves its conservative default-OFF switches.
Selecting **`config/QwenChat-L2Frozen.config.psd1`** explicitly enables the accepted
reference profile: structured reads, A (compact schema), B (lean read policy),
and the narrow mixed-current-user RAM update path. C stays OFF. The latter write
path remains an opt-in feature of this selected profile, not general free-form
mixed-turn authorization. Other settings are identical to the common config;
hardware/context placement belongs to host profiles. Use a fresh isolated data
path when replaying tests; the profile alone is not a sandbox.

The frozen write contract is `memory_ops[]` with the restored **2414-character**
policy (LF-normalized, including final LF), SHA256
`e569f902206f03a2318aed4de97ba4d62766ce89824ccac6fee3a5ea877a45ec`.
Existing SQLite schema, scope, source-turn provenance, history and authorization
remain intact. L0 raw evidence and L1 working memory remain separate layers.

## Decisions

| Class | Decision | Basis / boundary |
|---|---|---|
| Accept for demonstrated utility | A+B together on eligible protected LOCAL L2 reads | Fewer input/output tokens and markedly lower latency in the four-observation CPU pilot; correct answers, zero L1/L2 mutation. |
| Accept for demonstrated utility | LOCAL write authorization, read/write suppression, transactional alias/scope checks and atomic application | R1 Windows 12/12; R3 six targeted suites; R4 four LOCAL turns. The FULL comparison still proposed two unnecessary operations per turn; guards suppressed them. |
| Preserve accepted post-DEV3 work | LOCAL temperature 0.1, removal of 871 duplicate prompt characters, narrow deterministic declarative acknowledgement | Earlier functional evidence retained; acknowledgement also avoided an extra model call on R4 turn 1. Earlier paired timing observations are not general speed estimates. |
| Accept as bounded architecture | Separate read/write contracts, necessary observability, exact-source mixed write path | Mixed case passed; broad language coverage and standalone telemetry performance benefit are not established. |
| Do not adopt as default | 2040-character extraction policy | Failed semantic acceptance. Restoring the full policy does not imply the full policy is error-free. |
| Defer | 1721-character grouped extraction format | Windows converter/SQLite 58 checks PASS, but both model probes omitted the required GPU relation. No production wiring or schema migration. |
| Defer / keep OFF | C, lower-trust L2 placement | Earlier matched adversarial pair showed no demonstrated advantage and added input; broader security effects remain unknown. |
| Reject expansion without evidence | Treating retrieved facts as new user authority, enabling optimization outside eligibility, growing lexical exceptions to chase fixture PASS | Risks integrity or loses needed updates. Safe misses and visible failure remain acceptable. |

Deferral is distinct from proven general harm. A missing relation is observed
information loss; it is not proof that every grouped-format workload performs
worse. No candidate is described as the globally most effective CPU technique.

## Evidence and provenance

Windows executions below were reported by the operator in console output;
the cloud assistant prepared the pinned scripts and inspected the supplied
results, but did not directly execute those Windows/model runs. Private paths,
host identities and raw traces are deliberately excluded from the public report.

- **R1 PASS:** all 12 offline suites, zero model calls, test commit
  `a264b61df70c66b3d09239c116a2606373484ca7`. It fixes demonstrated OS/database,
  RAM/CPU-count and boolean-attribute misbinding defects, with positive controls.
- **R2 original candidate:** first four extraction cases PASS; frontier synthesis
  FAIL. The full-policy contrast and both explicit-CPU controls also failed their
  complete semantic expectations. These outcomes remain recorded and are not
  relabeled PASS by milestone closure. Grouped-format probes subsequently fixed
  observed operation typing but omitted the GPU relation in both outputs.
- **R3 PASS:** six targeted Windows offline suites on conservative source
  `8ace0ca81e830095230efa1313e675dcd9143085`: policy optimization, adversarial
  authorization, write authority, compact read, semantic read boundary and mixed
  runtime persistence. Full policy restored; C OFF; A+B and narrow mixed path
  enabled only in the isolated reference config.
- **R4 PASS, bounded LOCAL pilot:** declaration (four writes), correction (one
  write with history), protected A+B read (zero writes), exact current-user mixed
  RAM update (one write, preserved history and other-scope decoy). Four model
  calls in total; no extra model recovery. First turn initially failed a checker
  that accepted only `db_version`/`database_version`; stored `db=PostgreSQL 16`
  preserved the intended fact. The checker was corrected, the saved turn was
  rechecked without inference, and the remaining three turns ran after restart
  against a copy of that state. This is not an uninterrupted four-turn timing run.
- Resume checker SHA256:
  `4fb49d8b73fcc9b6e39f67952b06798649e08f97b6c4e3fd655857b762f7696f`.
- **R5 PASS, eligible-case mechanism pilot:** same conservative source; same
  question `What OS does ORION run?`; byte-matched copies of the accepted state
  before each trial; FULL, A+B, A+B, FULL. Each response correct; SQLite facts,
  entities and aliases unchanged; L1 unchanged; four calls total, no retries.
- R5 harness SHA256:
  `b315993be2b16c4f731845249e8bbe7d614aed2058f6c780391caa20015bca54`;
  derived driver SHA256:
  `75266b4733d9654a4f7bf03ae57656e7e0bf00b46d86defeadfc7b7f67178a7f`.

Pinned R4/R5 runtime: Windows PowerShell 5.1.19041.7725, Ollama 0.34.4,
`qwen3.5:4b-q4_K_M`, digest
`2a654d98e6fba55d452b7043684e9b57a947e393bbffa62485a7aac05ee4eefd`,
CPU-only, two inference threads, context 5120, LOCAL temperature 0.1,
`think=false`. R5 normal generation cap 1024. Model defaults observed:
presence_penalty 1.5, top_k 20, top_p 0.95; request temperature overrides model
metadata temperature 1. No frontier service calls or production memory writes.

## R5 measured observations

| Trial | Mode | Complete turn s | Input tokens | Output tokens | Prefill s | Decode s | Load s | Proposed / suppressed ops |
|---|---|---:|---:|---:|---:|---:|---:|---|
| 1 | FULL | 192.195 | 1756 | 171 | 127.605 | 46.909 | 16.294 | 2 / 2 |
| 2 | A+B | 41.616 | 1210 | 24 | 34.380 | 6.027 | 0.009 | 0 / 0 |
| 3 | A+B | 7.966 | 1210 | 24 | 0.634 | 6.277 | 0.009 | 0 / 0 |
| 4 | FULL | 127.063 | 1756 | 175 | 78.248 | 47.793 | 0.007 | 2 / 2 |

Same retrieved evidence in every trial: four L2 facts / 328 characters. Complete
turn timing includes application processing and persistence, excludes fixture
setup and independent post-run audit. Every trial made one model call.

Mean complete turn: FULL 159.629 s; A+B 24.791 s (84.47% lower in this pilot).
Input decreased 31.09%; mean output decreased 86.13%. Both A+B trials showed
much lower output/decode cost. A+B answered the requested OS directly; FULL also
mentioned RAM and produced unnecessary memory proposals.

These are four observations of one eligible LOCAL question, **not** a general
DEV3-versus-DEV5 workload comparison. Initial cache/load state was observed,
not reset: the first FULL loaded the model, and the second A+B prefill is
consistent with substantial cache reuse. ABBA order does not remove that
asymmetry or background-load variance. The exact 84.47% must not be advertised
as a universal or statistically established speedup. The token/decode savings
and successful guard behavior are sufficient for the selective engineering
acceptance; no further repeated benchmark is required to close L2.

## Portability and known limits

The techniques inspired by memory/context-traffic work were implemented and
validated in a different setting: a PowerShell/SQLite local-first application
on a constrained CPU-only Windows notebook. This supports practical applicability
in LFO beyond the motivating environment; it does not reproduce another study,
establish hardware independence of the gain, or rank all known CPU optimizations.
Earlier L2 write-side validation covered two Windows host classes; the final
A+B latency pilot covers one CPU profile. Do not conflate those evidence scopes.

Remaining limitations are accepted scope boundaries, not unfinished L2 tasks:
model extraction can omit/misbind facts; predicate aliases (`db`, `db_version`,
`database_version`) are not globally canonicalized; mixed writes support narrow
explicit grammar; a complete live FRONTIER integration was not revalidated in
this closure; L0 JSONL and L2 SQLite are not one distributed transaction. The
90% semantic engineering target is not a measured reliability estimate. Source
reconstruction and static/hash verification do not constitute a fresh Windows
execution of this packaging commit.

## Next session

Start L3 requirements and interface design against this frozen L2 contract:
semantic retrieval, entity resolution and selective reranking only where needed.
Preserve authoritative evidence and provenance. Then scope L4 / Local Epistemic
Balancer separately: hypotheses, interventions, calibration/reliance metrics,
controls and research safeguards. Neither L3 nor L4 is implemented by this closure.
Do not automatically reopen the old CLOSED / DEFER performance experiment, run
model sweeps, change production defaults, or reinterpret this freeze as a main
runtime deployment.
