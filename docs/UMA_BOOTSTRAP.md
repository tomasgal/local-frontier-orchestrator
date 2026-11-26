# Windows UMA bootstrap — AMD Ryzen AI Max+ / Radeon 8060S

Status: **reference-host integration accepted on 2026-11-26; stable v9.6.6 source**. Historical release tags remain unchanged.

## Intent and boundaries

`-Profile UMA` is a third **LFO execution profile** for a Windows host with large unified CPU/GPU memory. It retains the existing orchestration, L0–L4 logging/memory, optional Codex frontier and experiment runner.

Reference host: Ryzen AI Max+ 395, Radeon 8060S, 128 GB LPDDR5X, Windows 11 Pro. The existing Ollama instance at `127.0.0.1:11434` already hosts `qwen3.5:35b-a3b-q8_0`. The subsequent LFO integration tests independently confirmed full reported GPU residency and a 16,384-token context.

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

For the stable v9.6.6 release, use the matching installer and explicit tag:

```powershell
Invoke-WebRequest -UseBasicParsing 'https://raw.githubusercontent.com/tomasgal/local-frontier-orchestrator/v9.6.6/install/Install-LFO.ps1' -OutFile "$env:TEMP\Install-LFO.ps1"; powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$env:TEMP\Install-LFO.ps1" -Profile UMA -SourceRef refs/tags/v9.6.6 -SkipLaunch
```

For historical reproduction of the feature branch only (not the stable release), download its installer and set matching `-SourceRef`:

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

Placement acceptance criteria: `lfo-qwen3.5-35b-uma16k:latest` is loaded; `size_vram` is positive and ideally close to the loaded model size; the runtime reports a 16,384-token context. If the model is CPU-placed, the UMA acceleration requirement is **not** met even if a prompt succeeds.

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


## v9.6.6 compatibility and file exchange

The stable source incorporates v9.6.5 research tooling. The installer recognizes both legacy Ollama manifests and the newer manifests-v2/ollama.com layout, preferring v2 when both are present. It can reuse a previously created UMA alias with -SkipModelPull. The console renders common Markdown constructs using native PowerShell console colors (headings, emphasis, links, lists, task lists, blockquotes, rules, tables and code fences); this is a terminal-oriented subset, not a browser/CommonMark engine. Set LFO_MARKDOWN_PLAIN=1 or NO_COLOR to preserve plain output. Raw Markdown remains the persisted and exported response.

Optional bootstrap parameters -ImportDirectory and -ExportDirectory select existing or newly created exchange directories; defaults are import and export under the install root. These paths persist on reinstall. /files lists import files and both paths. /import NAME reads a UTF-8 text file (up to 64 MiB). A line containing only ||| (optional surrounding spaces) submits the current entry and starts another. Ordinary newlines remain inside prompts; EOF submits the last entry; blank entries are skipped. Each entry is limited to 32 KiB, and normal routing, slash commands, persistent memory and logging apply. Nested imports are rejected; /exit ends the session and remaining entries are not executed. There is no separate batch mode or automatic resume. Do not import confidential data if frontier routing is enabled. /export [NAME] writes the last response from this session as raw Markdown without overwriting existing files. /export-log explicitly copies the current monthly conversation JSONL, including potentially sensitive historical prompts. No automatic transfer of memory databases or credentials. Configure access to the exchange directories separately.

Host smoke testing has demonstrated 100% GPU residency, 16k context, LOCAL and FRONTIER transport, and L4 recording/analysis on an AMD unified-memory host. A local installer workaround was required for the v2 manifest layout; this branch includes the correction. Some schema-constrained responses ended prematurely despite valid JSON; short quote-copy tests did not reproduce the issue consistently. This remains an open quality issue, not a confirmed quote parser defect. Host reinstall and isolated LOCAL-only UMA smoke tests with L4 OFF and ON have passed. The reference host subsequently passed a complete long LOCAL response and a multi-example quotation/code response after the UMA-only writing mitigation; this is bounded acceptance, not proof of general model reliability.

Markdown tables with a header separator are laid out using visible column widths and word wrapping within the terminal window, with Unicode borders and a colored header. Extremely narrow terminals or irregular tables fall back to ordinary text. Display widths are approximate for complex emoji and Unicode sequences.

The renderer also accepts Markdown tables with optional leading or trailing pipe characters, including mixed forms in the same table. A valid header separator is required.

UMA generation ceilings are 4096 normal and 8192 thinking tokens for local answers and synthesis, reduced by a heuristic context-headroom estimate (not exact tokenization). CPU/GPU defaults are unchanged. At a local generation limit, the wrapper presents only a recoverable top-level answer prefix with an explicit incomplete marker, suppressing model-generated memory and frontier routing for that envelope; raw source stays in provenance. Other malformed envelopes receive a diagnostic instead of raw internal JSON. Existing frontier synthesis fallback remains unchanged. SSH or -SkipLaunch bootstrap skips Explorer. L4 experiment datastore copying refuses a detected live production endpoint or process holding the source path; do not start production SurrealDB during a copy.

Host testing also reproduced a syntactically valid but prematurely closed LOCAL answer with done_reason=stop near an optional quotation mark. A similar request explicitly avoiding quotations completed at 1509 tokens. UMA-only prompt guidance now discourages decorative quotation marks and requires proper JSON escaping while preserving necessary verbatim quotations and code. This is a mitigation experiment, not evidence that the underlying constrained decoder defect is resolved. No additional inference pass is introduced.
