# Memory, provenance and logging

This document describes the **current v9.6.2 operational storage and logging
contract**. Design rationale and historical evolution are in
[MEMORY_STRATEGY.md](MEMORY_STRATEGY.md).

## 1. Operational layers

LFO separates storage by epistemic role:

```text
L0  append-only conversation evidence / provenance
L1  bounded conversational orientation
L2  typed factual state with scope and provenance
L3  reconstructible selective retrieval metadata
L4  epistemic observations and bounded analytics
```

These layers are complementary. L0 remains the authority for what was actually
captured. L1 is lossy orientation. L2 is structured state. L3 narrows retrieval.
L4 records derived epistemic observations and must not silently become factual
memory.

## 2. Data roots

The repository default config uses:

```text
%LOCALAPPDATA%\LocalFrontierOrchestrator
```

The Windows bootstrap instead generates an **installation-local** memory root:

```text
<InstallRoot>\data\memory
```

For the normal install this is:

```text
%LOCALAPPDATA%\LFO\data\memory
```

Relevant layout:

```text
data\memory\
  state\
    working_memory.txt
    pending_notes.jsonl
    runtime_state.json
    l2-memory.db
    l3-index.db              # when L3 is enabled/used
  logs\
    conversation-YYYY-MM.jsonl
    trace-YYYY-MM.jsonl
    l4-source-identity.json  # created when the L0 store is registered for L4
```

L4 observations themselves live in the separate SurrealDB
`lfo / epistemic / observations` store prepared by the bootstrap.

## 3. L0 conversation JSONL

Each completed persisted turn is appended as one UTF-8 JSON object to:

```text
logs\conversation-YYYY-MM.jsonl
```

Core fields include:

```text
event
timestamp
turn_id
epoch
route
user
assistant
```

With `Memory.L0StageSourcesEnabled = true`, the row also carries
`stage_sources_schema = 1` and ordered `stage_sources[]` for USER, LOCAL,
FRONTIER and FINAL stages that actually occurred. USER and FINAL stages can
reference the authoritative top-level `user` / `assistant` fields instead of
duplicating text. L4 provenance binds observations to these exact persisted
turn/stage sources and verifies the content hash.

The JSONL file is plain text and is intentionally inspectable.

The installed helper:

```powershell
.\View-LFOConversationLog.ps1
```

renders the current month's turn ID, epoch, route, user text and assistant text.

## 4. L1 working memory

L1 provides conversational orientation with bounded cost:

- recent raw turns;
- one small same-pass `memory_note` when the normal LOCAL/synthesis response
  produces a useful durable user delta;
- `pending_notes.jsonl`;
- bounded `working_memory.txt`;
- pressure-triggered compaction.

Current common defaults are:

- recent turns: 4;
- note limit: 40 characters;
- state limit: 160 characters;
- compact at 4 pending notes or 108 pending-note characters.

The same answer pass normally produces the note; there is no mandatory extra
per-turn memory-model call. Exact historical text is never replaced by this
lossy state.

## 5. Exact L0 retrieval

The baseline lexical retriever scans only the current conversation epoch,
scores older turns against terms from the current query (with bounded memory
cues when necessary), excludes the recent-turn tail and injects only a bounded
number of snippets.

Common defaults:

- scan cap: 500 turns;
- at most 3 retrieved items;
- at most 2500 characters.

This is a retrieval mechanism, not a truth estimator. Repetition increases
retrieval relevance, not factual certainty.

## 6. L2 structured factual state

When `Memory.StructuredEnabled = true`, L2 uses:

```text
state\l2-memory.db
```

L2 stores typed facts/relations with source-turn provenance and current versus
historical state. Writes are guarded by current-user evidence/authorization
rules and SQLite transactions.

Current structured **read injection remains opt-in** in the common config
(`StructuredReadEnabled = false`). When a LOCAL turn actually receives L2
facts as read evidence, model-echoed L2 writes and companion L1 notes are
suppressed by the read-side persistence guard.

L2 scopes use the conversation epoch, e.g. `conversation:2`.

## 7. L3 retrieval/index layer

L3 uses a separate reconstructible SQLite index:

```text
state\l3-index.db
```

It can narrow L0/L2 evidence using deterministic facets and then fall open to
the ordinary baseline path when classification/retrieval is unavailable. L3 is
non-authoritative: deleting/rebuilding the index must not destroy L0 history or
L2 factual state.

The frozen L3 implementation is documented in
[L3_FROZEN_BASELINE.md](L3_FROZEN_BASELINE.md). Deployment remains explicitly
controlled; absent/false L3 switches mean the ordinary baseline retrieval path
is used.

## 8. /clear semantics

`/clear` is intentionally an **epoch boundary**, not a history deletion.

It:

- clears active in-process messages;
- increments `runtime_state.epoch`;
- clears `working_memory.txt` and pending L1 notes;
- retains historical conversation/trace JSONL;
- retains L2/L3 databases and L4 observations as historical records.

Because normal L2/L3 retrieval is scope/epoch bounded, facts from the previous
epoch are not automatically reintroduced into the new conversation epoch.

The trace log records the clear event when research logging is enabled.

## 9. L4 recording

v9.6.2 preserves the v9.6.1 conservative L4 recording behavior **after durable L0 persistence**.

Current online T1 can emit:

- `ASYMMETRIC_EVIDENCE_REQUEST`;
- `FRAMING`;
- or `ABSTAIN`.

Positive observations are stored in SurrealDB with exact L0 provenance.
`ABSTAIN` does not prove absence of bias; it means the current conservative
detector did not emit one of its supported signals.

`/analyze [1..100]` performs bounded explicit A1/A2 reads in the current epoch.
No ordinary-turn L4 analytics history is injected into prompts. P1/P2 response
intervention remains OFF.

See [L4_RECORDING_MANUAL_ANALYSIS.md](L4_RECORDING_MANUAL_ANALYSIS.md).

## 10. Trace logging

When `ResearchLogging.Enabled = true`, LFO writes monthly trace JSONL under
`logs\trace-YYYY-MM.jsonl`. Depending on configuration and path, traces may
include raw/intermediate text, routing/policy decisions, memory snapshots,
retrieval/context statistics, token/timing metadata, write/suppression outcomes
and clear events.

Trace records are research/diagnostic evidence. They are not a replacement for
the canonical L0 conversation row or L2 structured state.

## 11. Authority rules

Keep these distinctions explicit:

- **L0:** what was captured.
- **L1:** what should remain actively in mind.
- **L2:** structured current/historical state.
- **L3:** what evidence/context should be considered.
- **L4:** what epistemic observation/analysis is being reported.

No L4 annotation should silently become an L2 fact or persistent L1 user trait.
No retrieved context becomes true merely because it was retrieved.
