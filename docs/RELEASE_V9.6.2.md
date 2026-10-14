# LFO v9.6.2 release notes

Release date: 2026-10-14

## Scope

v9.6.2 is the packaging/runtime consolidation release for the accepted v9.6 line. It preserves the v9.6.1 conservative L4 recording and manual `/analyze` semantics while promoting the tested Windows bootstrap and service lifecycle into the immutable release boundary.

## Included changes

- accepted Windows bootstrap for PowerShell 5.1;
- Ollama 0.34.4 reuse/provisioning and CPU/GPU model aliases;
- one persisted shared Ollama model store for both CPU and GPU execution profiles;
- early runtime guard when the configured Ollama API does not expose both LFO aliases;
- SurrealDB 3.3.0 reuse/provisioning with isolated LFO datastore and current-user DPAPI credentials;
- automatic post-bootstrap Qwen launch while retaining Explorer access to the installed launcher directory;
- installed conversation-log viewer;
- deterministic 33-check L4 recording acceptance suite;
- installed-tree FRONTIER/Codex end-to-end smoke PASS;
- CPU-only execution-profile smoke PASS;
- consolidated current/frozen/historical documentation.

## Acceptance evidence

The functional installed-tree closure was exercised at source commit
`dbd14629d2318bc5f340271b225518c39d217f16` on 2026-10-14.

FRONTIER/Codex smoke:

```text
hard web/freshness gate
-> FRONTIER
-> one authenticated ask_codex call
-> frontier result returned
-> local Qwen post-FRONTIER synthesis
-> route=FRONTIER
```

CPU execution-profile smoke:

```text
Profile: CPU
Model: lfo-qwen3.5-4b-cpu5k:latest
num_gpu=0
context=5120
-> LOCAL inference
-> route=LOCAL
```

The shared model-store defect discovered by the first FRONTIER smoke was repaired before the final PASS. The accepted cold-start retry demonstrated successful post-FRONTIER Qwen synthesis after Codex returned.

## Unchanged boundaries

- L2 remains frozen at `v9.4-l2-frozen`.
- L3 remains frozen at `v9.5-l3-frozen`.
- L4 R1/R2/A1/D1/A2/P1/P2 frozen research baselines remain unchanged.
- P1/P2 response intervention remains OFF in the operational runtime.
- Detector coverage remains intentionally conservative; no general detector-accuracy or debiasing-efficacy claim is made.
- CPU acceptance validates the CPU execution profile on the accepted Windows/Ryzen installation; it is not separate-host replication.

## Publication note

The repository currently has no explicit software license file. v9.6.2 does not silently choose one. A license decision should be made explicitly before or together with Zenodo publication if broader reuse rights are intended.


## Zenodo archive

The published v9.6.2 software release is archived on Zenodo with the version-specific DOI:

`10.5281/zenodo.23373391`

The immutable Git tag remains `v9.6.2`; this DOI documentation was added to `main` after Zenodo completed the archive ingest and does not rewrite the released tag.
