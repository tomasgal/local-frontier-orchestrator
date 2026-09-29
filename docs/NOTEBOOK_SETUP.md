# Clean Windows notebook setup

This checklist prepares a new Windows machine for Local Frontier Orchestrator without using Codex to modify the project.

The goal is to install prerequisites, clone the repository, pull a neutral base model, and collect hardware facts. **Do not copy a tuned model/context profile from another PC.**

## 1. Install base tools

Open PowerShell as a normal user. Use elevation only when an installer requests it.

```powershell
winget install --id Git.Git -e --source winget
winget install --id OpenJS.NodeJS.LTS -e --source winget
irm https://ollama.com/install.ps1 | iex
```

Close and reopen PowerShell after installation, then verify:

```powershell
git --version
node --version
npm --version
ollama --version
```

## 2. Install Codex CLI, but do not use it to change the project yet

```powershell
npm install -g @openai/codex
codex --version
```

Authentication can be completed interactively later. The Qwen-first architecture expects the native Codex CLI to be authenticated before FRONTIER routing is tested.

## 3. Clone the project

Choose a normal working directory. Do not put Ollama model storage inside a synchronized project folder.

```powershell
New-Item -ItemType Directory -Force "$HOME\Documents\Codex" | Out-Null
Set-Location "$HOME\Documents\Codex"
git clone https://github.com/tomasgal/local-frontier-orchestrator.git
Set-Location .\local-frontier-orchestrator
git status
```

Expected state: clean `main` branch.

## 4. Pull the neutral reference model

The public baseline uses the standard Ollama Qwen 3.5 4B Q4_K_M model. Pulling it does **not** select the final context/GPU profile for this machine.

```powershell
ollama pull qwen3.5:4b-q4_K_M
ollama list
```

Do not create a copied 16k/22k/24k/32k profile yet. The new host must be measured first.

## 5. Collect hardware facts

Run:

```powershell
Get-CimInstance Win32_Processor | Select-Object Name,NumberOfCores,NumberOfLogicalProcessors
Get-CimInstance Win32_ComputerSystem | Select-Object Manufacturer,Model,TotalPhysicalMemory
Get-CimInstance Win32_VideoController | Select-Object Name,AdapterRAM,DriverVersion
```

If the notebook has NVIDIA graphics:

```powershell
nvidia-smi
```

Save the output for the next implementation session.

## 6. What not to do yet

- Do not copy the tuned context/GPU profile from another host.
- Do not set `num_gpu`, `num_ctx`, or `num_thread` in QwenChat request payloads.
- Do not tune temperature or presence penalty from one or two prompts.
- Do not remove the local post-frontier synthesis layer; it is part of the research design.
- Do not install or run Codex Router for the normal Qwen-first path.
- Do not put credentials, Codex auth state, Ollama weights, logs, or machine-specific secrets into this repository.
- Do not save Windows `.bat` files with a UTF-8 BOM; `cmd.exe` can interpret the BOM as characters before `@echo off`.

## 7. Stop point

At this point the notebook is ready for host-specific work:

1. inspect CPU/GPU/RAM and driver state;
2. choose the notebook model/context profile;
3. benchmark local inference;
4. start Ollama and QwenChat;
5. run LOCAL, FRONTIER, and named-product regression smoke tests.

Do not optimize before those measurements exist.

## 8. Clean-host validation result — 2026-09-28

A clean second-host bootstrap was completed on a constrained legacy notebook class to test portability rather than peak performance.

Observed host class:

- Intel Core i7-6600U, 2 cores / 4 threads;
- 8 GB RAM;
- Intel HD Graphics 520;
- normal desktop workload intentionally left running during the proof-of-concept test, with about 1.1 GiB physical RAM available before model load;
- Ollama 0.34.4;
- `qwen3.5:4b-q4_K_M` (about 3.3 GiB model size).

Ollama detected the Intel integrated GPU through Vulkan but dropped it by default, so the validated baseline remained **CPU-only**. No iGPU override was forced.

The initial 8k bootstrap ceiling was reduced to **4096** for the constrained-host proof of concept. The actual runner initialized with `n_ctx_slot = 4096`; the LOCAL smoke test used a 396-token prompt, generated 463 tokens, reported about **14.29 prompt tok/s** and **4.23 generation tok/s**, and completed without truncation. The first/cold wrapper turn took about 163 seconds including model load and warm-up.

Regression results:

- LOCAL routing: **PASS**;
- explicit web/freshness FRONTIER routing: **PASS**;
- named-product specification hard gate: **PASS**;
- post-frontier local synthesis: **PASS**;
- clean shutdown of the controlled Ollama process tree: **PASS**.

Warm frontier synthesis on the same host was around **5.1 tok/s**. These results validate orchestration and capacity only; they do not imply that every local 4B answer is factually correct.

The clean-host test also found a Windows Codex CLI shim issue. An npm installation exposed `codex.ps1`, `codex.cmd`, and `codex`; resolving the PowerShell shim caused `codex exec` to fail under the wrapper. The shared resolver was fixed to prefer **`codex.cmd`** on Windows and fall back to `codex`.

### Ollama desktop-app interference

A Windows Ollama desktop app may already own `127.0.0.1:11434`. In the validated host, `ollama app.exe` spawned `ollama.exe serve`; killing only the child caused it to be respawned. For controlled benchmarking, stop the parent app/process first and verify that the listener is gone before launching the project-managed server.

The constrained host was subsequently re-tested successfully at **5120** context, which is now the frozen notebook proof-of-concept default; 4096 remains a conservative fallback. The host launcher uses a small memory envelope (3 recent turns, about 500 characters of micro-memory, and bounded exact-data retrieval) while preserving the shared memory semantics.

### Persistent-memory validation — 2026-09-29

QwenChat **v9.1.3** passed the constrained-host micro-memory regression at the 5120 context baseline. A clean five-turn test produced correct user-delta notes, preserved a correction through compaction, normalized the final rolling state, and survived process restart with the corrected value and active goal/constraint intact. Post-turn micro-memory extraction was about **18–21 s**; the fifth turn including compaction was about **40 s**. Exact-data retrieval from older raw JSONL remains the next isolated regression test.

