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

### Candidate detector tuning (not implemented in v9.6.1)

The current v9.6.1 T1 detector has no user-facing sensitivity parameter. Its
matching rules are intentionally conservative and are hard-coded in
`Get-LfoL4TurnObservationType`. A future implementation could expose either a
named profile:

```powershell
L4 = @{
    Enabled = $true
    DetectorProfile = 'conservative'   # conservative | expanded
}
```

or a small ordinal sensitivity setting:

```powershell
DetectorSensitivity = 1   # 1=conservative, 2=expanded
```

These are **candidate interfaces, not active configuration keys**. They should
not both become independent controls; implementation should choose one canonical
interface and map it to an explicit, testable ruleset. The intended meaning is
limited to breadth of detection: `conservative` preserves the current
false-negative-preferring rules, while `expanded` may recognize a broader set
of semantically equivalent formulations. It must not silently turn a deterministic
signal detector into a personality classifier or a generic bias score.

Current implementation points on `main` (2026-10-14; function names are
authoritative if line numbers later move):

- `config/QwenChat.config.psd1:10` — current `L4` configuration block. Add
  `DetectorProfile` or `DetectorSensitivity` here when the interface is
  implemented.
- `src/QwenChat.ps1:1036-1039` — QwenChat reads `Config.L4` and passes the
  complete hashtable to `Initialize-LfoL4Recording`; no separate transport path
  is required for a new L4 key.
- `src/LfoL4Runtime.ps1:48-71` — `Initialize-LfoL4Recording`. Validate the
  profile/sensitivity here and preserve the resolved setting in
  `$script:LfoL4Recording`.
- `src/LfoL4Runtime.ps1:74-90` — `Get-LfoL4TurnObservationType`. This is the
  actual deterministic T1 ruleset. Profile-dependent rule expansion belongs
  here (or in helper functions called from here).
- `src/LfoL4Runtime.ps1:93-108` — `Invoke-LfoL4RecordTurn` calls the detector
  and creates the R1 observation. Pass the resolved profile/sensitivity into the
  detector here and bump `DetectorVersion` if detector semantics change.
- `tests/Test-LfoL4Recording.ps1:12-28` — current positive/negative T1 fixtures.
  Add explicit conservative and expanded-profile cases here before promotion.
  Conservative negatives must remain negatives unless the profile explicitly
  changes their contract.

### Bias magnitude is a separate measurement problem

Detector sensitivity only changes **which candidate events are annotated**. It
does not measure how strong a bias-related effect is. A future research output
might look like:

```text
FRAMING magnitude = 0.32
ASYMMETRY magnitude = 0.71
SYCOPHANCY shift = 0.18
```

Such values require an explicit reference/control condition and a
phenomenon-specific metric. They must not be produced by simply assigning a
numeric weight to the current regex match. The existing R1 `confidence` field
is detector confidence and must not be overloaded as bias magnitude.

Relevant implementation points for a future magnitude design are:

- `src/LfoEpistemicStore.ps1:69-106` — canonical R1 observation construction;
  currently includes optional `confidence`, but no magnitude field.
- `schema/L4Observations.surql:1-30` — SurrealDB R1 schema. A persisted
  per-observation magnitude would require an explicit schema/version decision
  here and matching canonical serialization in `Add-LfoEpistemicObservation`
  (`src/LfoEpistemicStore.ps1:163-190`).
- `src/LfoEpistemicObservatory.ps1:98-160` — A1 window aggregation; currently
  counts annotations and provenance but computes no magnitude.
- `src/LfoEpistemicInteractionAnalytics.ps1:105-215` — A2 interaction analytics;
  this is a natural place for a **derived** magnitude from paired/control
  observations if the metric is defined at interaction/window level rather than
  stored in each R1 record.
- `docs/GENERIC_EPISTEMIC_MEDIATOR.md`, section 4 — research definition of bias
  magnitude as deviation from an explicit reference/control condition.

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
