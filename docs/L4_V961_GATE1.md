# v9.6.1 Gate 1: reusable I1 integration

Base: public main `50c7189` (accepted I1 dependencies at `51a7b2a`).
Scope at the Gate 1 checkpoint: extraction and deterministic regression only.
Subsequent recording/manual-command work is documented in
`L4_RECORDING_MANUAL_ANALYSIS.md`.

## Source of the extraction

Recovered the actual runner identified by `L4_I1_INTEGRATION_EVIDENCE.md`:

- runner SHA-256: `a747a322415a7b1db28f76245d8768dd71be979ba7a462eacb11e203b8ef71cd`;
- embedded harness SHA-256: `224fa0aee18a8b54fa640f28d179d1d411ef8eeaaa0628847913608abdf22b1b`.

The runner is a private host launcher; its embedded synthetic harness is the
source for `tests/Invoke-LfoL4I1Walkthrough.ps1`. The public harness takes the
model identity as an argument and defaults to an offline transport identity.
Host setup, embedded Git bundle, credentials and service discovery stay outside
the reusable implementation.

`src/LfoL4Runtime.ps1` extracts these existing operations:

1. I1's external P1 compatibility lock and frozen P2 integrity binding. It
   accepts LF/CRLF and an optional UTF-8 BOM only after verifying the exact
   canonical I1 rules hash, and retains the frozen historical lock.
2. The R1-backed A1 window and A2 interaction-summary calls.
3. `ConvertTo-LfoP1Evidence` followed by the frozen P1 capsule and P2 mapping.

The fixture generator, R2 explicit annotation-plan ingestion into R1, isolated
server lifecycle, model transport, reverse drill-back and original assertions
remain in the harness. No synthetic annotation logic enters the runtime module.
The existing R1 write API is unchanged; the ordinary connector belongs to Gate 2.

## Runtime boundary

`New-LfoL4RuntimePolicyBinding` creates a caller-owned compatibility lock in an
explicit work directory. Importing the module opens no database and writes no
files. `Invoke-LfoL4RuntimeCycle` composes the accepted chain with a fail-open
result (`FAILED_ISOLATED`, no policy/intervention) on component errors.

`Get-LfoL4RuntimeWindow` is the explicit read phase;
`Get-LfoL4RuntimeResponse` consumes an existing A2 summary without store I/O.
This split allows later pre-response use of prior-turn state and post-turn
refresh after L0 provenance completes. Both policy and intervention default OFF.
Callers must isolate initialization errors as part of later ordinary wiring.

Frozen A1/A2 currently scan a capped epoch and then select the requested turn
window; the turn bounds are not pushed into the R1 query. This extraction
preserves that behavior, passes explicit page/record/support bounds (default
record cap 200), and performs no scheduled or per-turn reads. Gate 3 must honor
this limitation when implementing rare reads; no bounded-window query claim is
made here.

QwenChat, frozen components, D1 and FRONTIER are unchanged. The separate existing
`fix/v9.6.1-l4-runtime` development branch was inspected and left intact. This
Gate 1 patch is based on accepted main and introduces no T1/T2 or ordinary hook.

## Validation

Windows PowerShell 5.1, pinned SurrealDB 3.3.0, isolated RocksDB with owned-process
restart/reconnect. Use a local nonsynchronized test directory for RocksDB.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/Test-LfoL4I1Runtime.ps1 -SurrealBinary <path-to-surreal.exe>
```

Optional `-BaselineRoot` compares against an original I1 offline run. The original
harness was exercised with a fixed local transport and only its server window
changed to hidden; no research model experiment was repeated.

- Original and refactored I1: **128/128 PASS** each.
- Original deterministic pre-inference gate: **108/108 PASS** each.
- Adapter and baseline comparisons: **54 PASS**, including **45 artifact pairs**
  over all five decisions, instructions, full requests and reverse provenance.
- **18** explicit synthetic R1 annotations; no unplanned writes.
- **0** model inference calls, **5** deterministic transport responses, **0** D1 calls.
- Failure injection at R1, A1, A2, P1 and P2 returns no active policy/intervention.
- Response-only path uses prior A2 state without R1 reads; both readers receive
  the explicit bounds unchanged.
- Windows PowerShell 5.1 parsing: all three new scripts PASS. Standard Windows
  CRLF checkout regression also passes 128 I1, 108 pre-inference and 8 adapter
  checks, with a generic offline transport identity and zero inference calls.

Cross-run artifact comparison normalizes generated store IDs and excludes
capture/recording timestamps and store-dependent payload hashes. Source content
hashes, exact L0 text/stage fields, support IDs, aggregates and requests are
compared; the frozen R1 API validates payloads during ingestion.

This is deterministic Gate 1 regression evidence, not a new live-model or
ordinary-runtime acceptance. No publish/freeze or v9.6.1 candidate designation.
