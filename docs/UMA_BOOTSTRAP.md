# Windows UMA bootstrap — AMD Ryzen AI Max+ / Radeon 8060S

Status: **experimental implementation (2026-11-23), not yet validated on the MS-S1 MAX host**. This extends the v9.6.4 source without altering the frozen v9.6.3 or v9.6.4 release tags.

## Intent and boundaries

`-Profile UMA` is a third **LFO execution profile** for a Windows host with large unified CPU/GPU memory. It retains the existing orchestration, L0–L4 logging/memory, optional Codex frontier and experiment runner.

Reference host: Ryzen AI Max+ 395, Radeon 8060S, 128 GB LPDDR5X, Windows 11 Pro. The existing Ollama instance at `127.0.0.1:11434` already hosts `qwen3.5:35b-a3b-q8_0`. Its reported 100% GPU placement and 16,384-token context were measured in the host's separate text runtime; **that does not yet validate LFO's UMA profile**.

UMA explicitly:
- requires a *running* compatible native Windows Ollama and the locally installed 35B Q8 model; it does not download a model or install/restart a second Ollama;
- creates `lfo-qwen3.5-35b-uma16k:latest` from `qwen3.5:35b-a3b-q8_0` with `num_ctx 16384`, `num_gpu 99`, `temperature 0.1`;
- creates an Ollama *manifest/alias* pointing at the existing model blobs, not a second copy of the 35B weights;
- verifies the alias and the backing filesystem store before persisting the installation state, instead of assuming a particular `OLLAMA_MODELS` directory;
- installs the same LFO Windows runtime, local SQLite memory, independent SurrealDB L4 store, DPAPI credentials, logs and three launchers;
- keeps CPU/GPU profiles and the original installer behavior intact on their normal hosts.

**UMA memory semantics:** CPU and GPU share physical RAM, but this does not make all 128 GB available to the model. BIOS allocation, current OS load, GPU driver and KV cache matter. `num_gpu 99` is an offload request, not proof of actual placement. There is no ROCm/PyTorch/ComfyUI or Docker/WSL installation in this bootstrap.

On a *new* UMA host the 4B CPU/GPU model aliases are not downloaded merely to populate their launchers; if those optional aliases are absent, launching CPU/GPU explicitly will report the missing alias. On a CPU/GPU bootstrap the legacy 4B aliases are still provisioned exactly as before.

## Preparation on MS-S1 MAX

In the same Windows user account that owns the existing model store, first verify:

```powershell
ollama --version
Invoke-RestMethod 'http://127.0.0.1:11434/api/version'
(Invoke-RestMethod 'http://127.0.0.1:11434/api/tags').models.name
Get-Process ollama* -ErrorAction SilentlyContinue | Select-Object ProcessName,Id,Path
```

Ensure `qwen3.5:35b-a3b-q8_0` is listed. If Ollama is stopped, start the *existing* `ollama serve` using the existing configuration; do not start a second instance. If Ollama uses a custom model store, set `$env:LFO_OLLAMA_MODELS` to **that same filesystem path** before installation. The installer fails closed when it cannot resolve the store.

Do not run a heavy T4AI/ComfyUI inference at the same time as the initial LFO validation; sharing physical UMA can cause memory pressure or device contention. Existing services and installed models must not be deleted or overwritten for this experiment.

## Installation

After this branch is merged into `main`, the normal third bootstrap command is:

```powershell
Invoke-WebRequest -UseBasicParsing 'https://raw.githubusercontent.com/tomasgal/local-frontier-orchestrator/main/install/Install-LFO.ps1' -OutFile "$env:TEMP\Install-LFO.ps1"; powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$env:TEMP\Install-LFO.ps1" -Profile UMA -SkipLaunch
```

To test the development branch *before merge*, download its installer and set matching `-SourceRef`:

```powershell
$ref='feat/uma-bootstrap-20261123'
Invoke-WebRequest -UseBasicParsing "https://raw.githubusercontent.com/tomasgal/local-frontier-orchestrator/$ref/install/Install-LFO.ps1" -OutFile "$env:TEMP\Install-LFO-UMA.ps1"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$env:TEMP\Install-LFO-UMA.ps1" -Profile UMA -SourceRef $ref -SkipLaunch
```

The initial `-SkipLaunch` prevents an automatic heavy model start; remove it for normal installations after smoke testing. The default root is `%LOCALAPPDATA%\LFO`. To keep an already installed LFO tree untouched during acceptance, specify a separate `-InstallRoot`; it will have separate L0–L4 state while referencing the same existing Ollama store.

The bootstrap can install/reuse the pinned SurrealDB 3.3.0 and runs its deterministic L4 suite by default. The optional frontier path requires Codex CLI; if not installed, the existing installer offers the reviewed, SHA-256-verified Codex installer or exits. **No credentials or personal data belong in source control.**

`-SkipModelPull` skips **UMA alias creation as well**, so only use it when `lfo-qwen3.5-35b-uma16k:latest` already exists and is resolvable in the active model store.

## Launch and validation

```powershell
$launch = Join-Path $env:LOCALAPPDATA 'LFO\launch'
& (Join-Path $launch 'Start-LFO-UMA.ps1')
# or:
& (Join-Path $launch 'LFO.ps1') -Device UMA
# automatic on a fresh UMA installation:
& (Join-Path $launch 'LFO.ps1')
```

Once LFO has completed at least one **LOCAL** reply, inspect actual placement:

```powershell
ollama ps
Invoke-RestMethod 'http://127.0.0.1:11434/api/ps' |
    Select-Object -ExpandProperty models |
    Select-Object name,size,size_vram,expires_at
```

Expected evidence (to be measured): `lfo-qwen3.5-35b-uma16k:latest` is loaded; `size_vram` is positive and ideally close to the loaded model size; the runtime reports a 16,384-token context. If the model is CPU-placed, the UMA acceleration requirement is **not** met even if a prompt succeeds.

Run the offline source-contract checks first, on the checkout:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-LfoUmaBootstrapContract.ps1
```

Then verify interactive LOCAL answer, `/analyze`/L4 configured, `/exit`, and optionally a short LOCAL-only experiment. Measure actual prefill/decode separately rather than projecting from T4AI's earlier ~41 tokens/s observation. The experiment runner records the requested/resolved device and Ollama placement and rejects zero GPU residency for UMA after warmup.

## Compatibility and failure conditions

- **CPU/GPU legacy installations:** unchanged defaults and their 4B model parameters. The new launcher is published alongside the old two.
- **UMA with a missing running Ollama, missing 35B model, or unresolvable backing model store:** explicit error, not silent download or fallback to CPU/a second daemon.
- **UMA vs NVIDIA detection:** when the recorded default is UMA, `Auto` selects UMA. A legacy installation without UMA default still uses the previous NVIDIA/CPU auto-resolution.
- **Shared services:** LFO may set Ollama process priority to High as in v9.6.4; this also affects other clients using that existing process. LFO does not guarantee exclusive model ownership or zero impact on concurrent T4AI/ComfyUI work.
- **Privacy:** the v9.6.4 research default records full local conversation/trace text and memory snapshots. Treat the installation's `data` directory as sensitive; `/clear` does not erase archives.

**Acceptance gate:** do not merge or designate UMA as production-supported until the Windows PowerShell parser/static tests, install/reinstall idempotency, real AMD GPU model placement, L4 recording and one interactive/experiment smoke test pass on MS-S1 MAX.
