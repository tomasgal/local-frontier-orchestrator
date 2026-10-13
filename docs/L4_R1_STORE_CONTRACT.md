# L4-R1 â€” Epistemic Observation Store

Status: implementation candidate, 2026-10-13. Store acceptance passed on Linux
and Windows PowerShell 5.1.19041.7725.
Linux x86_64 / PowerShell 7.4.6 / real SurrealDB 3.3.0: 39 checks passed,
including independent concurrent clients and forced-process restart.
Initial Windows PowerShell 5.1 gate failed on the combined Unicode/null
read assertion. The follow-up explicitly decodes HTTP response bytes as UTF-8,
splits that assertion and fixes stderr reporting. The user-run Windows gate
passed all 39 checks at `dae21d0bafa17a5a5c0291f28c5fe4f3a00116e0`: zero model
calls, production memory untouched, frozen tags unchanged.
Based on `2d80f1d64a4ed213e9c8163dbb227db4fb2f1ddd` (accepted L0 source
capture prerequisite). L0â€“L3 remain the fixed operational baseline. Their
runtime files/configuration and frozen tags are unchanged by this milestone.
LFO remains usable without L4.

## Scope and runtime

R1 supplies an explicit PowerShell 5.1-compatible observation API, SurrealDB
schema, foreground process launcher and isolated tests. Dot-sourcing the API
performs no I/O. It is not automatically called from QwenChat, does not detect
or classify turns, and adds no model call. A producer (initially a human or an
offline test/analysis) calls the API after L0 has persisted a turn. There is no
queue, prompt injection, automatic rewrite, or Balancer in R1.

Canonical layout: `lfo / epistemic / observations`. Pinned runtime: SurrealDB
3.3.0, official Linux amd64 archive and Windows amd64 executable with SHA256
in `config/L4Runtime.psd1`. Persistent backend: RocksDB. No Docker, GPU or
Ollama dependency. Bind only `127.0.0.1`, enable authentication, reject guests,
scripting and outbound network; server query timeout 3 seconds, client timeout
5 seconds. No implicit runtime download on ordinary LFO startup.

`tools/Start-LfoEpistemicServer.ps1` requires an explicit L4-only directory,
binary and port. It runs in the foreground, never installs a service. Initial
root credentials come from process environment `SURREAL_USER`/`SURREAL_PASS`.
Keep them outside source control. Bootstrap is a separate administrator action:
`Initialize-LfoEpistemicSchema` creates the namespace/database/schema and the
`lfo_r1` database EDITOR. It requires a generated hexadecimal runtime password
(32â€“128 characters); rerunning bootstrap does not rotate an existing password.
Ordinary APIs use this database credential in a PSCredential, never root. It
cannot access another database. The credential is trusted to access all source
stores within this L4 database: store/epoch filters are logical isolation,
not per-user authorization. Analytic callers are trusted explicit operators.

Append-only enforcement uses both CREATE semantics and a synchronous event
rejecting UPDATE/DELETE. A database administrator can change schema; this is
not a cryptographic tamper-proof audit store. `IF NOT EXISTS` bootstrap is for
this schema only, not a migration mechanism. Do not point R1 at an existing
unrelated database. No automatic production installation or enablement.

## Record and L0 provenance

`EpistemicObservation` schema/taxonomy version 1 has a stable random 32-hex
observation ID; source store ID, relative monthly filename, epoch, turn ID,
stage ID and SHA256 of exact decoded stage text; actor, stage, actual producer,
phase, source status and known model; observation type, nullable confidence,
detector/version, `REPORTED` status, observed/recorded timestamps, optional
exact excerpt (512 UTF-16 code units maximum), interaction and related ID.
The payload hash covers canonical client JSON excluding server recorded_at.
Confidence is detector-reported strength, not a calibrated probability.
`REPORTED` asserts that an annotation was recorded, not that it is correct.

`Register-LfoEpistemicL0Store` explicitly creates the only L0-side addition:
`l4-source-identity.json` in a supplied log directory, using create-new and a
durable flush. It never infers a production directory. Keep this UUID with L0
backups/restores. An independently writable copy of an L0 store must receive a
new identity before use; two independent histories must not share one UUID.
R1 performs no automatic copy detection or production migration.

`Resolve-LfoEpistemicSource` reads only the specified monthly JSONL file,
requires a unique matching epoch/turn/stage, and verifies its hash. USER and
FINAL resolve the authoritative `user`/`assistant` fields; LOCAL and FRONTIER
resolve the stored stage content. Actors/producer/model come from L0, not from
detector claims. Rejected cases include absent provenance, missing/duplicate
turns, invalid stage IDs, path traversal, symlink files, hash mismatch and
invented excerpts. Legacy L0 turns without stage capture are not silently
assigned fabricated stages. Source text is not copied into L4 beyond the
optional bounded excerpt. No hidden reasoning is requested or stored.

The existing L0 source capture must have been enabled for the source turn;
R1 does not turn it on globally. L0 is durable before registration/write.
There is no distributed transaction across L0 and SurrealDB, no crash journal
for incomplete turns, and no guarantee to retain unacknowledged observations.
Source resolution scans one monthly file and is intended for this explicit
R1 path; a bounded low-latency automatic turn hook requires later work.

## API and outcomes

1. Register the supplied L0 log root explicitly, retaining its identity file.
2. `New-LfoEpistemicObservation` resolves a persisted source and constructs the
   canonical payload. Retain this object (including ID and observed_at) for
   retries; constructing a new object is a new observation.
3. `Add-LfoEpistemicObservation` rechecks source integrity before one bounded
   RPC request; a race/error is never silently treated as success.

Outcomes: CREATED, ALREADY_EXISTS (same ID and exact payload), CONFLICT
(same ID with different payload), REJECTED (statement failure, including a
concurrent transaction conflict), UNKNOWN (unacknowledged transport/RPC
outcome). On a transient failure, retry the *same* payload/ID. UNKNOWN can mean
the server committed but the acknowledgement was lost. There is no automatic
retry or durable outbox. Invalid client/source input throws before sending.
A future online caller must preserve the answer on failure and expose the
write outcome; R1 does not add an online caller. Errors do not echo credentials
or full annotation content.

Related IDs are ordinary scalar links, never graph edges. A related annotation
must already exist in the same source store and epoch; self-links are rejected.
Interaction: INTRODUCED, REINFORCED, IGNORED, CHALLENGED, CORRECTED. Bias is one
annotation class among framing, presupposition and the other accepted design
types; no type is inferred from another.

`Get-LfoEpistemicObservation` requires ID/store/epoch.
`Find-LfoEpistemicObservations` requires store/epoch, optionally actor/type/
detector, with default 50 / maximum 200 records and ID keyset pagination.
`NextAfterId` is the last ID when a page is full (the final extra page may be
empty). UUID ordering is stable but not chronological. Concurrent inserts can
appear before the cursor; pagination is not a snapshot/export protocol.
Both are explicit analytic reads; nothing feeds L4 records into L2, L3 or
model prompts. All variable query values use RPC parameters. Raw SQL transport
is internal, never an input from a model or untrusted user.

## Verification and Windows console

`tests/Test-LfoEpistemicStore.ps1 -SurrealBinary <explicit executable>` creates
new TEMP L0 and RocksDB stores, a random loopback port, random credentials,
synthetic USER/LOCAL/FRONTIER/FINAL sources and independent concurrent clients.
It verifies persistence after forced process termination, Unicode/hash
linkage, schema rejection, idempotency/conflicts, concurrent create/retry,
pagination, authentication and logical store/epoch isolation. It kills only
the process it started, including on failure, and retains evidence in TEMP.
No production paths/configuration, model API, L1/L2/L3 databases or tags are
opened or changed. Process restart tests are not proof of power-loss durability.

`tools/Test-LfoL4R1Windows.ps1` downloads the pinned binary into a new explicit
work directory, checks its hash and runs the gate. Tests use temporary storage;
that directory is evidence, not a production deployment.
`tools/Initialize-LfoWindowsConsole.ps1` sets UTF-8, TLS 1.2 support and progress
handling for the current shell only. No persistent execution policy/profile
change is made. The accepted Windows host was sufficient for these no-model tests; R1 has no model or GPU requirement.

Optional `tools/Start-LfoOllamaConsole.ps1` is Windows-only and
opens a separate visible foreground server window, preserving the shell.
It refuses an occupied port, never kills an existing server, and selects CPU
visibility for this child process. No model or permanent Ollama configuration
is changed. It is not needed or invoked for R1, and its actual host launch
remains a separate manual check.

## Deferred

Automatic detectors/turn hook, persistent user profiling, automatic answer
rewrite, continuous history injection, implicit rare-trigger policy capsules,
Balancer policy, graph/vector/WASM/plugins/MCP, online retry queues and
longitudinal analytic claims are outside R1.

Runtime references: [HTTP API](https://surrealdb.com/docs/reference/rest-api/http-protocol),
[DEFINE USER](https://surrealdb.com/docs/reference/query-language/statements/define/user),
[release 3.3.0](https://github.com/surrealdb/surrealdb/releases/tag/v3.3.0).

Ollama launcher references: [GPU selection](https://docs.ollama.com/gpu),
[foreground logs](https://docs.ollama.com/troubleshooting).

## Visible Windows service consoles

`tools/Open-LfoSurrealConsole.ps1` opens a separate, persistent PowerShell
window with foreground SurrealDB and diagnostic logging (`debug`, configurable
to `info`). It requires an explicit dedicated workspace directory. It
verifies the runtime hash, rejects an occupied port, protects bootstrap/runtime
credentials using Windows current-user DPAPI via Export-Clixml, and initializes
the isolated development schema. It never loads or registers production L0.
Do not copy these credential files to a different account/host expecting them
to decrypt. Server diagnostics are not a complete SQL audit trail.

The server stays running when the launching script returns; Ctrl+C in its own
window stops it. The original shell remains available. The optional Ollama
launcher likewise opens a dedicated foreground console and does not start
a model. When both services are needed, this means three windows: shell,
SurrealDB, Ollama. Neither service is installed as a Windows service.

The visible-window workflow is syntax-checked here; its native Windows window
behavior was manually verified on Windows. The accepted 39-check store gate does not
need repeating solely for this launcher addition.

