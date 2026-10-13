# Windows integrated-build bootstrap candidate

This branch contains the first Windows CLI bootstrap candidate for a complete
LFO L0-L4 installation. It is deliberately a candidate until it passes the
clean CORE bootstrap and live build acceptance.

## One-script bootstrap

`install/Install-LfoWindows.ps1` supports 64-bit Windows PowerShell 5.1+ and:

- verifies the Windows/PowerShell environment and free space;
- verifies or installs Git for Windows through winget when Git is absent;
- verifies the system `winsqlite3.dll` ABI and performs a real temporary
  LFO SQLite open/write/read test;
- downloads pinned portable Ollama 0.34.4 and verifies its SHA-256;
- downloads pinned SurrealDB 3.3.0 and verifies its SHA-256/version;
- performs a clean detached checkout of an explicit LFO Git ref;
- creates installation-local runtime/config/state directories;
- selects unused loopback ports without killing existing processes;
- opens visible foreground Ollama and SurrealDB PowerShell consoles;
- pulls the selected local model unless explicitly skipped;
- creates `Start-LFO-GPU.ps1` and `Start-LFO-CPU.ps1`;
- automatically executes a zero-model installed-build preflight and writes
  `build-preflight-report.json`.

The GPU launcher leaves accelerator placement to Ollama and uses an 8192
context default. The CPU-only launcher masks CUDA, ROCm and Vulkan devices for
the child Ollama server and uses a 5120 context default. Both use one loaded
model and one parallel request. Neither installs a Windows service.

## Integrated layer profile

The generated release configuration explicitly opts into:

- L0 conversation/stage provenance;
- L1 conversational memory;
- accepted L2 structured state and read path;
- accepted L3 read/index path with fail-open fallback;
- L4 SurrealDB observation infrastructure.

D1 is not loaded into the runtime. Automatic P1 policy and P2 intervention are
hard-refused by the v1 runtime bridge and remain OFF.

L4 runtime status is recorded in the research turn trace when configured.
Human/explicit R1 annotations remain separate from automatic runtime behavior;
the build does not manufacture epistemic annotations.

The user can explicitly request the bounded stored-evidence path in QwenChat:

- `/l4 status` — runtime/default-OFF state;
- `/l4 review` — read current stored R1/A2 evidence and evaluate frozen P1;
- `/l4 next` — if P1 yields an active decision, arm the frozen P2 instruction
  for the next local first-pass model request only;
- `/l4 cancel` — discard an armed one-shot.

`/clear` also cancels any armed one-shot.

## P1 packaging compatibility

The immutable P1 historical lock has a known byte-hash packaging defect.
The build does not rewrite the frozen tag or historical lock. Runtime use is
bound by `config/L4P1Integrity.compatibility-v1.json` to the accepted P1
frozen commit, Git blob and canonical rules SHA-256. The original historical
code path remains the default when no compatibility contract is requested.

## Acceptance sequence

1. Run this branch's bootstrap from a clean install root on CORE.
2. Require `WINDOWS_BUILD_PREFLIGHT_PASS`.
3. Review `build-preflight-report.json`; this gate makes zero model calls.
4. From that installed clean checkout, run the separately versioned live build
   acceptance covering ordinary L0-L3 behavior, L4 default-OFF behavior and an
   explicit L4 one-shot smoke.
5. Merge/freeze only after the live acceptance is critically reviewed.

No frozen milestone tag is modified by this candidate.
