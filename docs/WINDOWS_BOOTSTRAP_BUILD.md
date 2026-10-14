# Windows bootstrap build v1 — v9.6.1 runtime

Status: **ACCEPTED WINDOWS BOOTSTRAP — CLEAN INSTALLED-TREE ACCEPTANCE PASSED 2026-10-14**

This document describes the Windows bootstrap packaging for the published **LFO v9.6.1 runtime contract**. The immutable `v9.6.1` tag remains the runtime release evidence boundary; `main` carries the accepted installer/service packaging.

## Source selection

The normal installer defaults to `SourceRef = 'main'`, which is the canonical accepted packaging/source line. `-SourceRef <commit-or-ref>` remains available for pinned acceptance or reconstruction work.

## Post-bootstrap launch behavior

After all installation and deterministic acceptance steps succeed, the installer
still opens the installed `launch` directory in Windows Explorer for convenient
shortcut creation. Unless `-SkipLaunch` is supplied, it then starts a new
PowerShell window using the selected profile's installed-tree launcher:

```text
-Profile CPU -> Start-LFO-CPU.ps1
-Profile GPU -> Start-LFO-GPU.ps1
```

The automatic chat launch occurs only after the bootstrap has reached its
successful completion boundary. Failure to open the chat window does not undo a
completed installation; the installed launcher path is printed for manual use.

## Runtime contract

The installed runtime provides Qwen 3.5 4B via Ollama, OpenAI Codex CLI as the current reference frontier adapter, SQLite through `winsqlite3.dll`, SurrealDB 3.3.0, v9.6.1 conservative post-L0 L4 recording, explicit `/analyze` bounded A1/A2 reads, and P1/P2 response intervention **OFF**. L4 remains fail-open with respect to ordinary chat.

## Reuse before provisioning

### SurrealDB

The installer does **not** hardcode any host path. It builds candidates from `LFO_SURREAL_EXE`, prior install state, PATH, the installer-managed runtime, bounded discovery below `%LOCALAPPDATA%\`, and the executable path of a running `surreal` process. Every candidate is accepted only when the version probe reports **3.3.0**. Otherwise the official pinned binary is downloaded and SHA-256 verified.

Binary reuse never implies datastore reuse. Each installation owns its datastore under the selected `InstallRoot`, with separate current-user DPAPI bootstrap/runtime credentials and the `lfo / epistemic` namespace/database.

### Ollama

The installer reuses a compatible running/installed Ollama runtime and existing model store when possible. Otherwise it provisions pinned Ollama 0.34.4 and verifies SHA-256. CPU and GPU aliases share the same base weights **and the same persisted model store**; profile selection is an execution policy, not a storage boundary.

If a compatible Ollama listener is already running but does not expose a uniquely discovered existing LFO CPU/GPU alias store, the bootstrap leaves that listener untouched and starts an LFO listener on a free local port against the shared LFO store. After alias creation the exact store is written to `install-state.json`. Runtime startup verifies that both aliases are visible before chat begins, so model-store drift fails early with a diagnostic instead of failing during LOCAL or post-FRONTIER synthesis.

## v9.6.1 L4 wiring

The installer verifies `src/LfoL4Runtime.ps1` and the recording test, generates a local config with L4 enabled, the actual isolated SurrealDB endpoint and runtime credential, L0 stage-source provenance enabled, and an installation-local memory directory. The launcher also exports `LFO_L4_ENABLED=1`, `LFO_L4_ENDPOINT` and `LFO_L4_RUNTIME_CREDENTIAL`.

A normal QwenChat startup must therefore report L4 recording as `CONFIGURED`. Positive T1 signals are written after durable L0 persistence; ABSTAIN performs no R1 I/O. Analytics run only on explicit `/analyze`. P2 remains OFF.

## Deterministic installation gate

Unless `-SkipL4Acceptance` is explicitly supplied, installation runs:

~~~powershell
tests/Test-LfoL4Recording.ps1 -SurrealBinary <detected-or-provisioned-surreal.exe>
~~~

The published v9.6.1 suite expects **33/33 PASS** and uses deterministic LOCAL fixtures with **zero model inference and zero FRONTIER calls**. It exercises real isolated R1 writes, exact L0 drill-back, idempotent replay, manual read-only analysis and fail-open behavior.

## Clean acceptance

Run the installer from Windows PowerShell 5.1 into a clean isolated root. Acceptance requires source acquisition, SQLite PASS, Ollama readiness/model aliases, SurrealDB 3.3.0 discovery or verified provisioning, isolated datastore/schema and credentials, generated v9.6.1 L4 config, deterministic recording-suite PASS, installed launchers, live L4 `CONFIGURED`, and a LOCAL recording plus explicit `/analyze` from the installed tree.

Clean installed-tree acceptance was reviewed and passed on 2026-10-14, including bootstrap completion, deterministic 33-check L4 recording acceptance, installed-tree GPU launcher startup, live LOCAL routing, two live L4 `CREATED` writes, and `/analyze` readback with exact L0 references.
