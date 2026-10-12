# L0 stage source capture (L4 prerequisite)

`Memory.L0StageSourcesEnabled` is an optional, default-false switch. Missing
settings in older configurations mean false. Capture also requires Memory.Enabled.
It is independent of ResearchLogging and does not require SurrealDB or an extra
model call. Frozen L2/L3 tags and retrieval semantics are unchanged.

When enabled, a completed conversation JSONL `event=turn` gains
`stage_sources_schema=1` and an ordered `stage_sources` array. Existing `user`,
`assistant`, `route`, `epoch`, and `turn_id` fields retain their meanings.

Each stage has a turn-local `stage_id`, actor, stage, phase, producer, UTC capture
time and status. Local producers include the configured model name. The frontier
model identity is unknown here and is not guessed. USER and FINAL entries use
`source_field=user|assistant`; intermediate entries carry `content`.

Captured phases are user input, initial LOCAL response (including a routing
response), FRONTIER handoff result, LOCAL synthesis, LOCAL answer recovery, and
the delivered FINAL answer. Skipped stages are absent. A frontier transport error
is recorded with `producer=WRAPPER,status=failed`, not as frontier model text.
FINAL distinguishes LOCAL, FRONTIER fallback, and WRAPPER-produced text.

Local content is exactly the cleaned content passed to the existing parser,
before parsing or fallback replacement; it is not the complete HTTP response or
hidden reasoning. `status=returned` describes capture, not semantic validity or
successful completion. Rejected or truncated synthesis content is still retained.
Memory-only extraction/compaction calls are outside this conversation-stage scope.

No stage sources enter L1/L2, the L3 index, or model-visible context. Current
readers continue selecting the existing user/assistant fields. No old logs are
rewritten. The existing L0 byte-length measurement includes the extended row.

Boundary: this patch retains the current completed-turn persistence model. If a
turn aborts before persistence (or no final content exists), in-flight stages are
not durable. It does not implement a crash journal. Stable cross-store identity,
source hashes/resolution, epistemic detectors, and the SurrealDB observation store
remain L4-R1 work; stage IDs are unique only within their parent turn.

Run `tests/Test-LfoL0StageSources.ps1` for isolated synthetic OFF/ON cases using
the actual orchestrator, parser and JSONL persistence with model transports
stubbed. Tests cover source capture, final producer attribution, fresh-process
reads, no research trace dependency, no added calls and no production data.
The same tests compare L3 locator and scan evidence with capture OFF/ON: source
stage payloads stay outside retrieved evidence.

Validation: PowerShell 7.4.6 on Linux, 10 scenarios / 20 OFF-ON variants PASS,
zero real model calls. Windows PowerShell 5.1 execution is pending; the publisher
runs the same suite on the target host before publishing. This is a source-stage
capture checkpoint, not completion of L4-R1 or a live model-quality evaluation.
