# Offline adversarial authorization matrix: model L2 proposals are NOT trusted user facts.
# No network/Ollama, no SQLite, no production memory. Covers false-positive writes
# and representative positive declarations. This is not a language entailment proof.
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
if((& git -C $repo branch --show-current).Trim() -cne 'v9.4-dev5-compact-read'){throw 'Wrong experimental branch'}
if(@(& git -C $repo status --porcelain).Count -ne 0){throw 'Dirty worktree'}
foreach($f in @('src\LfoStructuredMemory.ps1','src\QwenMemory.ps1')){
    $tok=$null;$err=$null
    [void][Management.Automation.Language.Parser]::ParseFile((Join-Path $repo $f),[ref]$tok,[ref]$err)
    if(@($err).Count -ne 0){throw "Source syntax failed: $f"}
}
. (Join-Path $repo 'src\LfoStructuredMemory.ps1')
. (Join-Path $repo 'src\QwenMemory.ps1')
function New-Proposal([string]$Subject,[string]$Op,[string]$Predicate,[string]$Target) {
    $raw=[pscustomobject]@{
        op=$Op;subject=$Subject;subject_type='server'
        predicate=$Predicate;target=$Target
        target_entity_type=''
    }
    $result=ConvertFrom-LfoStructuredMemoryOps -RawOps @($raw) -MaxOps 6
    if(@($result.Valid).Count -ne 1 -or @($result.Rejected).Count -ne 0){throw 'Invalid synthetic proposal'}
    return $result
}
$debian=New-Proposal ORION SET_TEXT os 'Debian 13'
$ubuntu=New-Proposal ORION SET_TEXT os 'Ubuntu 24.04'
$ram64=New-Proposal ORION SET_INTEGER ram_gb '64'
$ram32=New-Proposal ORION SET_INTEGER ram_gb '32'
$lyraDebian=New-Proposal LYRA SET_TEXT os 'Debian 13'
$core32=New-Proposal Core SET_INTEGER ram_gb '32'
$backupOn=New-Proposal ORION SET_BOOLEAN nightly_backups_enabled 'true'
$backupOff=New-Proposal ORION SET_BOOLEAN nightly_backups_enabled 'false'
# These cases must not authorize a durable LOCAL L2 write. Each contains a
# plausible model proposal but insufficient or contradictory current-user evidence.
$negative=@(
    [pscustomobject]@{Name='negation-in-main-claim';Prompt='ORION runs not Debian 13.';Ops=$debian},
    [pscustomobject]@{Name='negated-integer-claim';Prompt='ORION has no 64 GB RAM.';Ops=$ram64},
    [pscustomobject]@{Name='old-value-in-correction';Prompt='Correction: ORION now runs Debian 13 instead of Ubuntu 24.04.';Ops=$ubuntu},
    [pscustomobject]@{Name='previous-value-mentioned';Prompt='ORION runs Ubuntu 24.04, previously Debian 13.';Ops=$debian},
    [pscustomobject]@{Name='quoted-value';Prompt='ORION runs "Debian 13".';Ops=$debian},
    [pscustomobject]@{Name='external-attribution';Prompt='ORION runs Debian 13 according to old logs.';Ops=$debian},
    [pscustomobject]@{Name='uncertain-claim';Prompt='ORION runs maybe Debian 13.';Ops=$debian},
    [pscustomobject]@{Name='two-subjects-two-sentences';Prompt='ORION runs Ubuntu 24.04. LYRA runs Debian 13.';Ops=$debian},
    [pscustomobject]@{Name='two-subjects-one-sentence';Prompt='ORION runs Ubuntu 24.04, LYRA runs Debian 13.';Ops=$debian},
    [pscustomobject]@{Name='other-subject-from-later-sentence';Prompt='ORION runs Ubuntu 24.04. LYRA runs Debian 13.';Ops=$lyraDebian},
    [pscustomobject]@{Name='cpu-count-misread-as-ram';Prompt='ORION has 64 GB RAM and 32 CPU cores.';Ops=$ram32},
    [pscustomobject]@{Name='other-property-misread-as-ram';Prompt='ORION has 64 GB RAM and 32 GB disk.';Ops=$ram32},
    [pscustomobject]@{Name='read-command-no-question-mark';Prompt='State ORION runs Debian 13, then summarize the OS.';Ops=$debian},
    [pscustomobject]@{Name='historic-claim-past-tense';Prompt='ORION was running Ubuntu 24.04.';Ops=$ubuntu}
)
$positive=@(
    [pscustomobject]@{Name='fresh-os-declaration';Prompt='ORION runs Ubuntu 24.04.';Ops=$ubuntu},
    [pscustomobject]@{Name='explicit-correction-current';Prompt='Correction: ORION now runs Debian 13 instead of Ubuntu 24.04.';Ops=$debian},
    [pscustomobject]@{Name='ram-unit-bound';Prompt='ORION has 64 GB RAM and 32 CPU cores.';Ops=$ram64},
    [pscustomobject]@{Name='second-sentence-same-subject';Prompt='Core has a GTX1050 graphics card. Core has 32 GB RAM.';Ops=$core32},
    [pscustomobject]@{Name='boolean-positive';Prompt='ORION runs Ubuntu 24.04, and nightly backups are enabled.';Ops=$backupOn},
    [pscustomobject]@{Name='boolean-negative-value';Prompt='ORION runs Ubuntu 24.04, and nightly backups are disabled.';Ops=$backupOff}
)
$fails=@()
foreach($c in $negative) {
    $r=Get-LfoLocalModelWriteAuthorization -Prompt $c.Prompt -Route 'LOCAL' -ParsedOps $c.Ops
    if($r.Allowed){$fails+= "UNSAFE ACCEPT $($c.Name): $($r.Reason)"}
}
foreach($c in $positive) {
    $r=Get-LfoLocalModelWriteAuthorization -Prompt $c.Prompt -Route 'LOCAL' -ParsedOps $c.Ops
    if(-not $r.Allowed){$fails+= "FALSE REJECT $($c.Name): $($r.Reason)"}
}
if($fails.Count -gt 0){throw ('Adversarial authorization FAILED: '+($fails -join ' | '))}
[pscustomobject]@{
    PASS=$true
    UnsafeCasesRejected=$negative.Count
    ValidDeclarationsPreserved=$positive.Count
    RuntimeWrites=0
    ModelCalls=0
    ProductionMemoryTouched=$false
    Assurance='CONSERVATIVE_LEXICAL_BOUNDARY_NOT_SEMANTIC_PROOF'
}|Format-List
