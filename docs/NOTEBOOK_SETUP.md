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
