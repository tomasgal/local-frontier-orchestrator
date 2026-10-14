# Windows bootstrap and post-bootstrap host validation

This document is the **post-bootstrap validation and tuning guide** for a new
Windows LFO host. Manual Git/Ollama/Codex setup is no longer the normal install
path. The supported entry point is the bootstrap command in the repository
[README](../README.md).

## 1. Install from README

Open Windows PowerShell 5.1 as a normal user and choose one default profile.

**CPU default**

```powershell
Invoke-WebRequest -UseBasicParsing "https://raw.githubusercontent.com/tomasgal/local-frontier-orchestrator/main/install/Install-LFO.ps1" -OutFile "$env:TEMP\Install-LFO.ps1"; powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$env:TEMP\Install-LFO.ps1" -Profile CPU
```

**GPU default**

```powershell
Invoke-WebRequest -UseBasicParsing "https://raw.githubusercontent.com/tomasgal/local-frontier-orchestrator/main/install/Install-LFO.ps1" -OutFile "$env:TEMP\Install-LFO.ps1"; powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$env:TEMP\Install-LFO.ps1" -Profile GPU
```

The bootstrap verifies Windows/PowerShell/SQLite, obtains the exact LFO source,
detects or offers to install Codex CLI, reuses or provisions compatible Ollama
and SurrealDB runtimes, prepares the reference Qwen model and both CPU/GPU model
aliases, creates an installation-local data/configuration tree, initializes the
L4 datastore and runs the deterministic L4 recording acceptance suite.

The selected `-Profile` chooses both the **default** profile and the profile automatically launched after a successful bootstrap. Both `Start-LFO-CPU.ps1` and `Start-LFO-GPU.ps1` are installed. They share the same Ollama model store and all LFO state; CPU/GPU is an execution profile only. The bootstrap also opens the installed `launch` directory in Explorer so shortcuts can be created easily. Use `-SkipLaunch` only when the final automatic Qwen launch is not wanted.

The normal install root is:

```text
%LOCALAPPDATA%\LFO
```

Use `-InstallRoot` only when a deliberately separate installation is required,
for example an acceptance tree.

## 2. Capacity planning

The reference local model is `qwen3.5:4b-q4_K_M`.

Practical guidance:

- **CPU-only operation is supported.**
- **8 GB RAM** was validated as a constrained proof-of-concept host, not as a
  performance target.
- **16 GB+ RAM** is a more comfortable general-purpose baseline.
- A discrete GPU is optional but can materially improve latency and usable
  context headroom.
- Plan for at least **8 GB free disk**, preferably **10 GB+**, for the model,
  runtimes, caches and growing logs.
- Do not copy a large context/thread/GPU profile from another host without
  measuring the target machine.

The bootstrap currently prepares:

- CPU alias: `lfo-qwen3.5-4b-cpu5k:latest`, `num_gpu 0`, 5120-token context;
- GPU alias: `lfo-qwen3.5-4b-gpu8k:latest`, `num_gpu 99`, 8192-token context.

`num_gpu 99` requests maximal supported offload; Ollama decides what the
runtime can actually place on an available accelerator. The bootstrap does not
use GPU model detection to choose CPU versus GPU automatically.

## 3. Verify the installed state

After bootstrap completion, inspect:

```text
%LOCALAPPDATA%\LFO\config\install-state.json
%LOCALAPPDATA%\LFO\config\QwenChat.install.local.psd1
%LOCALAPPDATA%\LFO\launch\
```

The bootstrap summary should report:

- exact source commit;
- runtime contract `v9.6.1`;
- SQLite PASS;
- Ollama API/version;
- SurrealDB 3.3.0 endpoint;
- L4 recording enabled and deterministic acceptance PASS;
- Codex CLI found;
- selected default CPU/GPU profile.

The installer may reuse compatible runtimes from elsewhere on the host, but its
LFO datastore, credentials, configuration and memory root remain installation
specific.

## 4. Start or restart the installed runtime

A normal bootstrap already starts Qwen with the selected profile. To start it again later, or to override the recorded default explicitly, use the launcher in the installed tree:

```powershell
& "$env:LOCALAPPDATA\LFO\launch\Start-LFO-GPU.ps1"
```

or:

```powershell
& "$env:LOCALAPPDATA\LFO\launch\Start-LFO-CPU.ps1"
```

A healthy startup reports the selected profile/model, Ollama endpoint,
SurrealDB endpoint, installed config path and:

```text
[L4 recording: CONFIGURED; analysis: /analyze; P2 OFF]
```

The interactive prompt then appears as `Qwen>:`.

## 5. Host validation

Collect the host facts only **after** the common bootstrap has succeeded:

```powershell
Get-CimInstance Win32_Processor | Select-Object Name,NumberOfCores,NumberOfLogicalProcessors
Get-CimInstance Win32_ComputerSystem | Select-Object Manufacturer,Model,TotalPhysicalMemory
Get-CimInstance Win32_VideoController | Select-Object Name,AdapterRAM,DriverVersion
```

If NVIDIA tooling is available:

```powershell
nvidia-smi
```

For an actual LOCAL turn, record:

- model/profile;
- prompt and generated token counts;
- prompt evaluation and generation latency;
- whether GPU offload actually occurred;
- host load/paging state when comparing configurations.

Do not infer a host-wide optimum from one prompt.

## 6. Minimal runtime smoke tests

### LOCAL

Use a stable ordinary question. Expect:

```text
[Qwen route -> LOCAL]
```

and a normal answer.

### FRONTIER / Codex

Use an explicit current/web/frontier request. This verifies the complete:

```text
Qwen -> ask_codex -> native Codex CLI -> local synthesis
```

path. Codex must already be authenticated for frontier execution.

### L4 recording and analysis

A deterministic live signal is:

```text
Daj mi iba dôkazy potvrdzujúce môj názor.
```

Expected post-turn status:

```text
[L4 turn=<n>: CREATED]
```

A second signal such as:

```text
Ber ako fakt, že tento návrh škodí.
```

should create a second observation. Then:

```text
/analyze
```

should report the corresponding observation types and exact L0 references.
P1/P2 response intervention remains OFF.

## 7. Inspect conversation logs

The installed launcher directory contains:

```powershell
.\View-LFOConversationLog.ps1
```

It displays the current monthly JSONL log as turn rows containing
`turn_id`, `epoch`, `route`, `user` and `assistant`.

For another month:

```powershell
.\View-LFOConversationLog.ps1 -Month 2026-09
```

See [MEMORY_AND_LOGGING.md](MEMORY_AND_LOGGING.md) for the storage contract.

## 8. Tuning rule

Keep orchestration semantics common across hosts. Tune only host-owned runtime
properties such as context, thread count or accelerator placement, and measure
the full turn rather than only an isolated model microbenchmark.

Do not:

- edit shared routing/memory semantics merely because a host is slower;
- copy another machine's large-context profile blindly;
- put credentials, Codex auth state, Ollama weights or private logs in Git;
- treat one stochastic answer as evidence for sampler or routing retuning.

The historical constrained-notebook experiments remain in Git history and the
frozen L2 evidence. They are no longer the installation procedure.
