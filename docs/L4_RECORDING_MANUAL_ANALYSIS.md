# L4 recording and manual analysis

The revised scope replaces automatic T2 triggering with an explicit `/analyze`
command. Ordinary turns only record conservative T1 observations after durable
L0 persistence. Analysis does not alter answers or enter conversation history.
P1/P2 response intervention remains disconnected; D1 and FRONTIER are unused.

## Configuration

Use an existing initialized R1 service and its runtime credential. QwenChat reads
the optional `L4` section in its configuration:

```powershell
L4 = @{ Enabled = $true; Endpoint = 'http://127.0.0.1:<port>'; CredentialPath = '<runtime.credential.xml>' }
```

`Memory.Enabled` and `Memory.L0StageSourcesEnabled` must both be true. The normal
repository config enables source-stage capture; custom host configs must enable
it explicitly. The connection variables already used by LFO launchers override
these settings: `LFO_L4_ENABLED`, `LFO_L4_ENDPOINT`, and
`LFO_L4_RUNTIME_CREDENTIAL`. No service, schema or credential is created here.
`LFO_L4_ENABLED=0` disables the connector. No P1/P2 environment flag activates
response intervention in this version.

Startup reports CONFIGURED when connection settings and L0 identity are loaded.
This is not a service health check. Writes and manual reads contact the service
on demand with a three-second timeout per request; errors leave chat operational.
Missing/invalid configuration reports UNAVAILABLE and requires configuration
repair and a chat restart. A transient DB outage needs no restart.

## Behavior and limits

T1 handles short direct Slovak/English user instructions to request only
confirming evidence or to accept a claim as established. It emits at most one
`ASYMMETRIC_EVIDENCE_REQUEST` or `FRAMING` observation per turn. It does not
classify assistant text, infer personality, or estimate overall bias prevalence.
Input over 2,048 characters, quotation, questions, negation, hypothetical or
metalinguistic context abstains. False negatives are deliberately preferred.

The detector uses the exact completed L0 USER source. R1 validates provenance;
record status remains REPORTED, confidence unknown, excerpt empty. Stable
observation IDs make exact replays idempotent. Console statuses include ABSTAIN,
CREATED, ALREADY_EXISTS, UNKNOWN, CONFLICT and FAILED_ISOLATED. UNKNOWN is an
unconfirmed write, not evidence of persistence; there is no automatic retry.

`/analyze` prints the existing A1/A2 summary for the last eight turn IDs in the
current epoch. `/analyze 20` selects a larger window (1–100). It prints counts,
recurrence rows and up to twelve L0 references. No model call is used for this
report, no response is rewritten, and no command turn is persisted.

Frozen A1/A2 each read a capped epoch before selecting the turn window. This
adapter caps reads at 200 observations per epoch, pages at 50 and support at 12;
if the epoch exceeds the cap, the command reports failure instead of presenting
a partial aggregate as complete. `/clear` starts a new epoch using the existing
memory behavior and retains historical R1 records. No automatic L4 analytics
read occurs on ordinary turns. R1 source validation may scan the referenced L0
monthly file when a positive observation is written; ABSTAIN performs no R1 I/O.

## Live acceptance and reproduction

On 2026-10-14 the maintainer reported that the live Windows chat and manual
analysis worked and authorized publication as v9.6.1. This is a user-reported
live acceptance; outage handling and exact provenance assertions below are
covered by the deterministic suite. No cross-host or efficacy claim is added.

Run the modified `src/QwenChat.ps1` with your usual host config/model and the R1
connection settings above. An older installed copy will not contain this patch.
Use the published v9.6.1 source for this procedure.

1. Confirm `L4 recording: CONFIGURED`; use a fresh conversation epoch if desired.
2. Send `Explain confirmation bias.` Expect ABSTAIN.
3. Send `Give me only evidence supporting my view.` Expect CREATED after the
   answer. Repeat once to create a second independently sourced turn.
4. Run `/analyze`, then `/analyze 20`. Check counts and referenced turns/stages.
5. Confirm the next ordinary answer has no automatic L4 intervention.
6. With your test R1 service unavailable, send another signal and run `/analyze`.
   The answer and L0 persistence must still work; status must not claim a
   confirmed write. Restore the service and verify a later turn succeeds.

Offline acceptance runs actual `Invoke-Qwen`, its startup/callback and slash
command loop, with deterministic LOCAL transport and an isolated real R1 DB:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/Test-LfoL4Recording.ps1 -SurrealBinary <path-to-surreal.exe>
```

The release scope is recording and manual analysis. The frozen research tags
remain unchanged; automatic intervention and a general-purpose bias detector
are outside this release.

Offline result (Windows PowerShell 5.1, SurrealDB 3.3.0): **33/33 PASS**.
Preserved I1 regression: **128/128 PASS**, pre-inference **108/108 PASS**,
adapter checks **8/8 PASS**. All inference transports are deterministic fixtures;
model calls and FRONTIER calls are zero.
