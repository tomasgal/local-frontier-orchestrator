# Windows bootstrap build v2 — v9.6.3 runtime

Status: **v9.6.3 PRODUCTION RUNTIME — v9.6.2 BOOTSTRAP BASELINE RETAINED; RUNTIME-PRIORITY PROMOTION ACCEPTED 2026-10-20**

This document describes the Windows bootstrap packaging used by the **LFO v9.6.3 runtime contract**. v9.6.3 retains the accepted v9.6.2 installer/service packaging, shared model-store lifecycle and v9.6.1 L4 recording/manual-analysis semantics, while adding the production `LFO.ps1` runtime/experiment entrypoint and a default High inference-priority policy.

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

The bootstrap also publishes `LFO.ps1` directly into the installed `launch` directory. The CPU/GPU launchers are compatibility wrappers around that primary v9.6.3 entrypoint. The automatic chat launch occurs only after the bootstrap has reached its
successful completion boundary. Failure to open the chat window does not undo a
completed installation; the installed launcher path is printed for manual use.

## Runtime contract

The installed runtime provides Qwen 3.5 4B via Ollama, OpenAI Codex CLI as the current reference frontier adapter, SQLite through `winsqlite3.dll`, SurrealDB 3.3.0, v9.6.1-compatible conservative post-L0 L4 recording, explicit `/analyze` bounded A1/A2 reads, and P1/P2 response intervention **OFF**. v9.6.3 records `DefaultPriority = High`; the production launcher applies High to the inference runtime while leaving SurrealDB at Normal. L4 remains fail-open with respect to ordinary chat.

## Reuse before provisioning

### SurrealDB

The installer does **not** hardcode any host path. It builds candidates from `LFO_SURREAL_EXE`, prior install state, PATH, the installer-managed runtime, bounded discovery below `%LOCALAPPDATA%\`, and the executable path of a running `surreal` process. Every candidate is accepted only when the version probe reports **3.3.0**. Otherwise the official pinned binary is downloaded and SHA-256 verified.

Binary reuse never implies datastore reuse. Each installation owns its datastore under the selected `InstallRoot`, with separate current-user DPAPI bootstrap/runtime credentials and the `lfo / epistemic` namespace/database.

### Ollama

The installer reuses a compatible running/installed Ollama runtime and existing model store when possible. Otherwise it provisions pinned Ollama 0.34.4 and verifies SHA-256. CPU and GPU aliases share the same base weights **and the same persisted model store**; profile selection is an execution policy, not a storage boundary.

If a compatible Ollama listener is already running but does not expose a uniquely discovered existing LFO CPU/GPU alias store, the bootstrap leaves that listener untouched and starts an LFO listener on a free local port against the shared LFO store. **Any service started by LFO is headless and has stdout/stderr redirected under `runtime\logs\services`; an interactive console is never the service's I/O sink.** This prevents Windows console selection/QuickEdit from suspending service output and indirectly stalling the API. After alias creation the exact store is written to `install-state.json`. Runtime startup verifies that both aliases are visible before chat begins, so model-store drift fails early with a diagnostic instead of failing during LOCAL or post-FRONTIER synthesis.

## L4 wiring in v9.6.3 (semantics inherited from v9.6.1)

The installer verifies `src/LfoL4Runtime.ps1` and the recording test, generates a local config with L4 enabled, the actual isolated SurrealDB endpoint and runtime credential, L0 stage-source provenance enabled, and an installation-local memory directory. The launcher also exports `LFO_L4_ENABLED=1`, `LFO_L4_ENDPOINT` and `LFO_L4_RUNTIME_CREDENTIAL`.

A normal QwenChat startup must therefore report L4 recording as `CONFIGURED`. Positive T1 signals are written after durable L0 persistence; ABSTAIN performs no R1 I/O. Analytics run only on explicit `/analyze`. P2 remains OFF.

## Deterministic installation gate

Unless `-SkipL4Acceptance` is explicitly supplied, installation runs:

~~~powershell
tests/Test-LfoL4Recording.ps1 -SurrealBinary <detected-or-provisioned-surreal.exe>
~~~

The v9.6.3 bootstrap retains the published v9.6.1 suite and expects **33/33 PASS** and uses deterministic LOCAL fixtures with **zero model inference and zero FRONTIER calls**. It exercises real isolated R1 writes, exact L0 drill-back, idempotent replay, manual read-only analysis and fail-open behavior.

## Clean acceptance

Run the installer from Windows PowerShell 5.1 into a clean isolated root. Acceptance requires source acquisition, SQLite PASS, Ollama readiness/model aliases, SurrealDB 3.3.0 discovery or verified provisioning, isolated datastore/schema and credentials, generated v9.6.3 L4 config, deterministic recording-suite PASS, installed launchers, live L4 `CONFIGURED`, and a LOCAL recording plus explicit `/analyze` from the installed tree.

Clean installed-tree acceptance was reviewed and passed on 2026-10-14, including bootstrap completion, deterministic 33-check L4 recording acceptance, installed-tree GPU launcher startup, live LOCAL routing, two live L4 `CREATED` writes, and `/analyze` readback with exact L0 references.

### Release-closure live smokes — 2026-10-14

The final packaging smokes were run from the installed tree at source commit `dbd14629d2318bc5f340271b225518c39d217f16` after repairing shared Ollama model-store binding.

**FRONTIER/Codex E2E: PASS**

A current-web request produced the expected visible chain:

~~~text
[policy -> FRONTIER; reason=explicit-frontier-or-web]
[ask_codex; ... characters]
[ask_codex -> Qwen; ... characters]
...
route=FRONTIER
~~~

The authenticated Codex call returned successfully and Qwen completed the post-FRONTIER synthesis. This closes the distinction between merely detecting `codex --version` and demonstrating the installed authenticated frontier path.

**CPU execution profile: PASS**

The CPU launcher selected:

~~~text
Profile: CPU
Model:   lfo-qwen3.5-4b-cpu5k:latest
~~~

A LOCAL arithmetic prompt completed correctly with `route=LOCAL`. The CPU alias is defined with `num_gpu=0` and a 5120-token context. This test was performed on the accepted Windows installation in CPU-only execution mode; it does not claim separate-host replication.

**Shared model-store lifecycle: PASS**

The bootstrap resolved one persisted Ollama model store containing both CPU and GPU aliases. A cold runtime restart then found the selected GPU alias, completed FRONTIER handoff, and successfully re-entered local Qwen synthesis. The earlier failure mode — Codex returning successfully followed by `model ... not found` during synthesis — is therefore closed for the accepted installed-tree path.

### v9.6.3 final runtime/service closure — 2026-10-20

Final installed-tree smoke source: `e625e2f44187c23f9379fd9ef3e3c8cb74109972`.

The final validation targeted the v9.6.3 changes added after the earlier packaging gates:

- bootstrap update against an existing installation completed while **reusing running Ollama 0.34.4** and **SurrealDB 3.3.0**;
- persisted Ollama executable/model-store state was resolved through the fast path;
- service lifecycle no longer requires an interactive console for LFO-owned servers; stdout/stderr are redirected to `runtime\logs\services`;
- installed `LFO.ps1 -Device CPU` selected the CPU alias and verified the running Ollama process at **High** priority;
- startup reported L4 recording `CONFIGURED`;
- explicit `/exit` returned cleanly to the calling PowerShell process, closing the Windows PowerShell 5.1 blank-`ExitCode` regression.

The closure bootstrap deliberately used `-SkipModelPull -SkipL4Acceptance -SkipLaunch`. Those switches make this a focused runtime/service smoke, not a replacement for the earlier model-alias and deterministic L4 acceptance evidence. The inherited L4 suite had already passed **33/33** earlier in the v9.6.3 cycle, and model aliases/shared-store behavior had already been validated.
