# Windows bootstrap candidate

This candidate is the first installer/build substrate for an integrated Windows
LFO distribution.

The installer at install/Install-LfoWindows.ps1 supports 64-bit Windows
PowerShell 5.1+, verifies or installs Git for Windows through winget when
necessary, verifies the Windows winsqlite3.dll ABI with an actual temporary LFO
SQLite open/write/read test, downloads pinned portable Ollama 0.34.4 and
SurrealDB 3.3.0 with SHA-256 verification, checks out an explicit LFO Git ref,
writes an installation-local release configuration and state record, selects
free loopback ports without killing existing processes, opens visible
foreground Ollama and SurrealDB consoles, optionally pulls
qwen3.5:4b-q4_K_M, and creates Start-LFO-GPU.ps1 and Start-LFO-CPU.ps1
wrappers.

The GPU profile leaves accelerator selection to Ollama. The CPU profile masks
CUDA, ROCm and Vulkan devices for the child Ollama server. Neither profile
installs a Windows service.

The generated release profile opts into accepted L0 stage provenance, L2
structured read/write and L3 read/index behavior. Unknown L3 queries retain the
accepted fail-open baseline.

L4 infrastructure is configured, but automatic detector-derived annotations are
not enabled. D1 remains offline. P1/P2 intervention remains default-OFF. The
next build increment must wire the accepted explicit L4 runtime invocation into
QwenChat before this candidate is called the final L0-L4 release.

Do not merge this candidate solely because installation completes. Run it from a
clean directory on Windows, test both CPU and GPU launchers, and then perform a
clean-checkout acceptance of the integrated runtime.
