# Windows bootstrap build v1

Status: **DEVELOPMENT CANDIDATE — WINDOWS ACCEPTANCE PENDING**

This branch constructs the first reusable Windows installation/bootstrap path for
the complete LFO runtime. It is intentionally separate from `main` until a clean
Windows acceptance run proves the bootstrap itself.

## Design contract

The bootstrap is one build with two convenience launchers:

- `Start-LFO-GPU.ps1` — GPU offload profile;
- `Start-LFO-CPU.ps1` — CPU-only profile.

Both launch the same source tree, data layout and LFO code. The profile
difference is represented through Ollama model parameters, not separate builds.

Default installation root:

`%LOCALAPPDATA%\LFO`

The installed tree separates application source, runtimes, models, mutable data,
local/private configuration and launchers.

## Frontier runtime requirement

The current Windows build uses **OpenAI Codex CLI** as the supported frontier
runtime. The bootstrap detects an existing Codex CLI before continuing. If
Codex is not present, the installer offers only two choices:

1. install OpenAI Codex CLI using the official Windows installer;
2. exit the LFO installation.

A LOCAL-only installation is not treated as a complete LFO installation in
this bootstrap path.

Codex is the current default frontier runtime because OpenAI makes Codex
available across ChatGPT plans, including **Free** and **Go**, with usage limits
that vary by plan. This allows the reference LFO frontier path to rely on one
official client and its user authentication instead of implementing a separate
OpenAI account, credential, or TUI layer inside LFO.

The current bootstrap stage detects/provisions the Codex executable and records
its availability. Authentication/readiness validation is a separate bootstrap
gate still to be completed before this candidate can be called a finished
installer.

The current LFO runtime invokes Codex as an isolated frontier pipe and keeps the
user's Codex configuration out of the request path via the existing
`--ignore-user-config` contract. This keeps the accepted reference path
predictable while using Codex-managed user credentials.


## Reuse before provisioning

The installer does not blindly install duplicate dependencies.

### Ollama

It checks explicit overrides, PATH, normal Windows installation locations,
the installer-managed runtime and the process bound to the conventional local
Ollama port. A compatible existing Ollama executable/server is reused when its
identity can be established.

If no compatible runtime is available, the bootstrap provisions pinned Ollama
0.34.4 from the official release artifact and verifies its SHA-256 before use.

If LFO starts an Ollama server, it runs in a separate visible foreground
PowerShell window with live output. If an already-running compatible server is
reused, LFO does not own its stdout/stderr and therefore opens a separate
visible activity/status monitor instead of pretending to own the original log
stream.

Model weights are shared. The bootstrap creates lightweight Ollama aliases for
GPU and CPU execution:

- GPU: context 8192, `num_gpu=99`;
- CPU: context 5120, `num_gpu=0`.

The aliases reference the same base model and do not imply two independent LFO
builds.

### SQLite

The Windows runtime uses the in-box `winsqlite3.dll` ABI already used by LFO.
The bootstrap performs an actual create/write/read/transaction self-test through
the same LFO PowerShell interop layer.

A missing `winsqlite3.dll` is currently a platform-preflight failure rather
than a trigger to install an unrelated SQLite CLI or silently replace the ABI.
This preserves the runtime contract that was validated for L0-L3. A private
SQLite-library fallback would require an explicit separately tested ABI change.

### SurrealDB

The bootstrap checks explicit overrides, PATH, an existing compatible process
and the installer-managed runtime. An exact SurrealDB 3.3.0 binary is reused
when available.

Otherwise it downloads the pinned official Windows amd64 binary and verifies the
published SHA-256.

Reusing a SurrealDB **binary** does not mean reusing an unrelated database.
LFO maintains its own RocksDB datastore, namespace/database and credentials.
Current-user DPAPI-protected bootstrap/runtime credentials are stored under the
private local install configuration.

A SurrealDB process started by LFO runs in a separate visible foreground
PowerShell window with live logs. A compatible already-running LFO datastore is
attached without stopping or restarting the process.

## Service ownership

The launcher never stops a service process it did not start.

Visible consoles are first-class UX:

1. Ollama foreground log window, or an activity monitor when attaching to an
   already-running server;
2. SurrealDB foreground log window, or an activity monitor when attaching to an
   already-running LFO datastore;
3. the primary LFO chat/runtime console.

## L4 boundary in this candidate

The installer provisions the pinned SurrealDB store/schema and enables L0
stage-source provenance in the installed local configuration. It also exports
the local L4 endpoint/runtime-credential location to the launch environment.

The current `QwenChat.ps1` still requires the final runtime adapter that
invokes the frozen L4 analytics/policy/intervention chain during an ordinary
chat turn. Therefore this branch is a **bootstrap/build candidate**, not yet a
claim that the normal chat entrypoint exercises the full L0-L4 path.

That adapter and its OFF/ON acceptance gate must be completed before the branch
can be promoted as a complete L0-L4 release.

## First acceptance

Run the published installer from a normal Windows PowerShell 5.1 console on a
reference host into a clean install root. The installer should:

1. obtain this branch from GitHub;
2. prove the SQLite ABI;
3. reuse or provision Ollama;
4. reuse existing model weights when available and create CPU/GPU aliases;
5. reuse or provision SurrealDB 3.3.0;
6. create an isolated LFO SurrealDB datastore and schema;
7. write local install state/configuration;
8. expose the two installed launchers.

Acceptance evidence must come from the installed tree, not a development
checkout.

Do not merge this branch into `main`, freeze a milestone, or call the
implementation cycle complete until the clean Windows acceptance result has
been reviewed.
