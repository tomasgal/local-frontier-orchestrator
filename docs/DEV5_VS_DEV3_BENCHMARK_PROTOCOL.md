# Dev5 versus dev3: representative, correctness-gated benchmark

**Status (2026-10-09): PREPARED; no matched end-to-end workload results or net-gain acceptance.** This protocol is deliberately model-free until the Windows TEMP-only SQLite atomicity tests pass. Historical ORION/TITAN live timings are **not** a dev3/dev5 paired workload: different tasks, schemas, scopes and uncontrolled host states cannot establish a whole-project speedup.

## Refs and isolation

- **Dev3 baseline:** exact `a34658b81742596520da844618b5bb39f3329279` (branch `v9.4-l2-structured-memory`, the checkpoint immediately before the first dev4 phase-timing commit).
- **Dev5:** `v9.4-dev5-compact-read`, always record the resolved commit SHA for each run; do not benchmark against a moving head without pinning it.
- Benchmark **only on independent, fresh TEMP directories**, unique per run/variant. Never point `Memory.DataDirectory` to a production path. Do not modify `main`, `v9.4-dev4-observability` or existing user memory.
- Same host and OS, Qwen model *digest*, Ollama version, context length, thread/GPU runtime profile, `think=false`, local warm/cold policy, synthetic source text, answer rubric, fixture version, and logging mode. Record all of these.
- Dev5 A+B ON only for opt-in scoped reads (`CompactReadSchemaEnabled=true`, `LeanReadPolicyEnabled=true`, `StructuredReadEnabled=true`); candidate C and `MixedUserEvidenceWriteEnabled` remain OFF in the *comparable* benchmark. Normal writes preserve the full validated schema. Record dev3's actual functional support instead of pretending it implements dev5 read-side L2.

## Five common semantic workloads

1. `plain-local`: a short stable LOCAL instruction with no memory update; audit no extra inference or SQLite write.
2. `dense-write`: one synthetic four-fact declarative ORION update; all four must persist with correct source turn.
3. `correction`: a same-scope scalar correction after the dense turn; original value historical, other facts unchanged.
4. `preference-only`: user preference handled via normal L1 micro-memory, without fabricated L2 facts.
5. `scoped-read`: answer the four ORION facts, including a historical and a cross-epoch negative-control row. For a valid dev3 comparison, supply **the same factual evidence in a bounded recent dialogue** accessible to dev3; otherwise mark the task as a **dev5-only capability contrast**, not a performance comparison. Dev5 may additionally retrieve scoped L2 evidence. Both answers and memory side effects must pass independent checks.

A mixed read + current-user RAM update, ambiguous alias, hostile L2 content, or retrieval over a distant history are **separate functional/capability cohorts**. Dev3 cannot be scored as if it supported the opt-in dev5 mixed provenance feature. Do not include these in a time-weighted net speed claim.

## Order of execution and cost control

1. **Offline gate:** parse new PowerShell code and run `tests/Test-Dev5SqliteAtomicity.ps1`, `tests/Test-Dev5MixedRuntimePersistence.ps1`, `tests/Test-LfoMemoryStore.ps1`, `tests/Test-Dev5CompactRead.ps1`, `tests/Test-Dev5SemanticReadBoundary.ps1`, `tests/Test-Dev4L2Retrieval.ps1`, `tests/Test-Dev4Observability.ps1`, `tests/Test-PromptPolicyOptimization.ps1`, `tests/Test-Dev5MixedUserProvenance.ps1`. Stop on any failure, retaining TEMP artifacts and logs.
2. **Model-free baseline first:** measure PowerShell/SQLite processing time and default-off trace/snapshot overhead on identical synthetic workloads in dev3 versus dev5; compare correctness and cost distribution. This is not a model-wall benchmark.
3. **Minimal live pilot only when justified:** one matched pair on an eligible scoped-read case, randomized/counterbalanced order in subsequent repetitions. Freeze a private reference-host configuration and use independent TEMP stores. Do not replay the already validated mixed ORION Qwen turn merely to accumulate expensive CPU samples.
4. If the pilot remains valid, expand to all five workloads with at least three matched repetitions each (still exploratory). A statistically robust cross-host speedup claim requires more repeats, uncertainty estimates, both warm/cold strata and GPU/edge transfer tests as resources permit. Never claim significance from one sample or mixed environments.
5. Repeat the identical five scenarios with dev5 instrumentation **normally enabled** and, separately, with explicitly enabled diagnostic tracing. Report always-on dev4/dev5 overhead against dev3; optional diagnostic overhead must not be silently charged to default production mode.

Primary outcome: the **workload-weighted end-to-end answer time**, with independently grounded workload weights from observed task frequencies. Without grounded weights, report only illustrative equal-weight sensitivity. Accept a net architectural performance improvement only with matched correctness, no new model pass, no failed memory contracts, and dev5 weighted wall less than dev3 (including always-on dev4 instrumentation costs). Report model HTTP, prefill/decode, context assembly, SQL retrieval, persistence, trace overhead and unattributed residual separately; missing timing phases stay **missing**, never zero. Record confidence intervals or variation before making a repeatability claim.

## Offline comparator contract

`tests/Compare-Dev5VsDev3Workload.ps1` reads **measured** JSON inputs; it does not invent results or call Ollama. Each file is a JSON object with `schema="lfo-dev5-vs-dev3-v1"`, `variant="dev3"` or `"dev5"`, an `environment` object, and `samples` array.

Required environment keys, identical in both files: `fixture_version`, `host_class`, `model_id`, `model_digest`, `ollama_version`, `num_ctx`, `think`, `warm_state`, `logging_mode`. Preserve the additional actual commit SHA and experimental switch settings as provenance.

A measured sample: `{"case_id":"dense-write","repetition":1,"answer_correct":true,"memory_correct":true,"answer_wall_s":123.45,"input_tokens":1000,"output_tokens":50}`. **These numbers illustrate the input schema and are not observations.** Include all five common case IDs in each file and identical unique repetition numbers for each case. Export full model/context/persistence timing fields separately alongside the required summary fields for audit. The checker rejects missing, unmatched, nonpositive or incorrect samples. It prints per-case median wall and a weighted aggregate; fewer than three repetitions is explicitly exploratory.

Optional `-WeightsPath` accepts `{"schema":"lfo-observed-workload-weights-v1","provenance":"<documented workload sample and date>","weights":{"plain-local":0.2,"dense-write":0.2,"correction":0.2,"preference-only":0.2,"scoped-read":0.2}}`. The numerical weights shown are **illustrative placeholders**, not an observed workload distribution. The provenance must describe a real sample; avoid claiming observed weighting until measured. Without `-WeightsPath`, comparator labels the aggregate `ILLUSTRATIVE_ONLY`.

PowerShell commands are intentionally a **single physical line** each:

`& .\tests\Test-Dev5SqliteAtomicity.ps1`

`& .\tests\Compare-Dev5VsDev3Workload.ps1 -Dev3Path '<TEMP>\dev3-measured.json' -Dev5Path '<TEMP>\dev5-measured.json'`

Before any locally run command: verify the current branch, clean tree and that the isolation root is truly beneath TEMP. Failure is a hard stop; do not switch or modify `main`/dev4 and do not silently repeat expensive live inference.

## Current evidence vs acceptance

- **Confirmed earlier, one-sample:** A+B read reduced ORION prompt input from 1641 to 1042 tokens compared with A-only; candidate A reduced generated tokens 294 to 45 versus full-schema control. These are mechanism-level reductions, not a dev3-vs-dev5 full-loop benchmark.
- **Confirmed earlier:** mixed current-user RAM64→96 write passed one isolated live test, with source span and scope independently checked. This is a separate functional feature.
- **Committed, unvalidated on Windows:** dev5 guarded L2 scope/alias authorization under SQLite `BEGIN IMMEDIATE`, duplicate-count correction, and new SQL failure/lock/alias-collision offline test. Do not mark PASS until actually executed.
- **OPEN:** representative matched dev3-vs-dev5 wall/tokens by semantic case, default tracing overhead, workload weighting, variance, cross-host transfer, and a defensible whole-app net performance result.
