# Dev5 SQLite atomicity and failure injection. TEMP-only, deterministic, NO Ollama.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
foreach ($name in @('src\LfoStructuredMemory.ps1','src\LfoMemoryStore.ps1','src\QwenMemory.ps1')) {
    $tokens = $null; $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile((Join-Path $repo $name),[ref]$tokens,[ref]$errors)
    if (@($errors).Count -gt 0) { throw "PowerShell syntax error in $name : $($errors | Out-String)" }
}
. (Join-Path $repo 'src\LfoStructuredMemory.ps1')
. (Join-Path $repo 'src\LfoMemoryStore.ps1')
$root = Join-Path ([IO.Path]::GetTempPath()) ('LFO-dev5-atomic-'+[guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $root -Force)
$dbPath = Join-Path $root 'atomic.db'
$db = Open-LfoMemoryStore $dbPath
function Assert-LfoTest([bool]$Ok, [string]$Why) { if (-not $Ok) { throw $Why } }
function New-LfoTestInteger([string]$Value) {
    $raw = @([pscustomobject]@{op='SET_INTEGER';subject='ORION';subject_type='server';predicate='ram_gb';target=$Value;target_entity_type=''})
    return (ConvertFrom-LfoStructuredMemoryOps -RawOps $raw -MaxOps 6)
}
function Get-LfoTestRam($Connection, [string]$Scope = 'conversation:1') {
    return @(Invoke-LfoSqliteQuery $Connection @'
SELECT f.id, f.value_integer, f.valid_to_turn, f.source_turn
FROM facts f JOIN entity_names n ON n.entity_id=f.subject_entity_id
WHERE n.normalized_name='orion' AND f.predicate='ram_gb' AND f.scope_id=?1
ORDER BY f.id;
'@ @($Scope))
}
$other = $null
try {
    [void](Set-LfoMemoryAttribute $db 'ORION' 'os' 'Debian 13' 1 'server' 'conversation:1')
    [void](Set-LfoMemoryAttribute $db 'ORION' 'ram_gb' ([int64]64) 1 'server' 'conversation:1')
    [void](Set-LfoMemoryAttribute $db 'ORION' 'ram_gb' ([int64]128) 1 'server' 'conversation:2')
    $write = Apply-LfoStructuredMemoryOps -Connection $db -ParsedOps (New-LfoTestInteger '96') -SourceTurn 3 -ScopeId 'conversation:1' -RequireUniqueCurrentSubject
    $ram = @(Get-LfoTestRam $db)
    Assert-LfoTest ($write.Status -eq 'applied' -and $write.AppliedCount -eq 1 -and $ram.Count -eq 2 -and [int]$ram[0].valid_to_turn -eq 3 -and [int64]$ram[1].value_integer -eq 96 -and [int]$ram[1].source_turn -eq 3) 'Guarded current-user supersession failed.'
    $dup = Apply-LfoStructuredMemoryOps -Connection $db -ParsedOps (New-LfoTestInteger '96') -SourceTurn 4 -ScopeId 'conversation:1' -RequireUniqueCurrentSubject
    Assert-LfoTest ($dup.Status -eq 'applied' -and $dup.AppliedCount -eq 0 -and @($dup.Results).Count -eq 1 -and $dup.Results[0].Status -eq 'duplicate' -and @(Get-LfoTestRam $db).Count -eq 2) 'Repeated same-user write was not idempotent or counted a duplicate as a write.'
    $emptyScope = Apply-LfoStructuredMemoryOps -Connection $db -ParsedOps (New-LfoTestInteger '100') -SourceTurn 5 -ScopeId 'conversation:99' -RequireUniqueCurrentSubject
    Assert-LfoTest ($emptyScope.Status -eq 'guard-rejected' -and $emptyScope.AppliedCount -eq 0 -and @(Get-LfoTestRam $db 'conversation:99').Count -eq 0) 'Missing-scope guard wrote facts.'
    $twice = New-LfoTestInteger '256'
    $twice.Valid = @($twice.Valid[0],$twice.Valid[0])
    $batch = Apply-LfoStructuredMemoryOps -Connection $db -ParsedOps $twice -SourceTurn 6 -ScopeId 'conversation:9'
    Assert-LfoTest ($batch.Status -eq 'applied' -and $batch.AppliedCount -eq 1 -and @($batch.Results).Count -eq 2 -and $batch.Results[1].Status -eq 'duplicate' -and @(Get-LfoTestRam $db 'conversation:9').Count -eq 1) 'Within-batch duplicate accounting is incorrect.'
    $shape = Apply-LfoStructuredMemoryOps -Connection $db -ParsedOps $twice -SourceTurn 7 -ScopeId 'conversation:1' -RequireUniqueCurrentSubject
    Assert-LfoTest ($shape.Status -eq 'guard-rejected' -and $shape.AppliedCount -eq 0 -and @(Get-LfoTestRam $db).Count -eq 2) 'Guard allowed more than one user-sourced operation.'

    # INSERT fails after SET has invalidated the old row: the rollback MUST
    # restore 96 as current, with no historical split or partial new row.
    Invoke-LfoSqliteExec $db @'
CREATE TEMP TRIGGER lfo_injected_insert_failure BEFORE INSERT ON facts
WHEN NEW.scope_id='conversation:1' AND NEW.predicate='ram_gb'
BEGIN SELECT RAISE(ABORT,'injected-fact-insert-failure'); END;
'@
    $failed = $false
    try { [void](Apply-LfoStructuredMemoryOps -Connection $db -ParsedOps (New-LfoTestInteger '192') -SourceTurn 8 -ScopeId 'conversation:1' -RequireUniqueCurrentSubject) }
    catch { $failed = ($_.Exception.Message -like '*injected-fact-insert-failure*') }
    Assert-LfoTest $failed 'Injected SQLite failure did not propagate.'
    $afterFail = @(Get-LfoTestRam $db)
    Assert-LfoTest ($afterFail.Count -eq 2 -and $null -eq $afterFail[1].valid_to_turn -and [int64]$afterFail[1].value_integer -eq 96) 'Injected SQL failure left partial supersession.'
    Invoke-LfoSqliteExec $db 'DROP TRIGGER lfo_injected_insert_failure;'

    # Force a late operation error after a valid sibling UPDATE+INSERT.
    $bad = New-LfoTestInteger '192'
    $bad.Valid = @($bad.Valid[0],[pscustomobject]@{Op='INJECTED_UNSUPPORTED'})
    $lateFailed = $false
    try { [void](Apply-LfoStructuredMemoryOps -Connection $db -ParsedOps $bad -SourceTurn 9 -ScopeId 'conversation:1') }
    catch { $lateFailed = ($_.Exception.Message -like '*Unsupported validated L2 op*') }
    Assert-LfoTest $lateFailed 'Late batch error did not propagate.'
    $afterLate = @(Get-LfoTestRam $db)
    Assert-LfoTest ($afterLate.Count -eq 2 -and $null -eq $afterLate[1].valid_to_turn -and [int64]$afterLate[1].value_integer -eq 96) 'Late batch error did not roll back earlier operation.'

    # A separate connection may acquire BEGIN IMMEDIATE first; subsequent
    # guarded writes must fail rather than bypass the reserved writer lock.
    $other = Open-LfoMemoryStore $dbPath
    Start-LfoMemoryTransaction $other
    $lockedOut = $false
    try { [void](Apply-LfoStructuredMemoryOps -Connection $db -ParsedOps (New-LfoTestInteger '192') -SourceTurn 10 -ScopeId 'conversation:1' -RequireUniqueCurrentSubject) }
    catch { $lockedOut = $true }
    finally { Undo-LfoMemoryTransaction $other }
    Assert-LfoTest ($lockedOut -and @(Get-LfoTestRam $db).Count -eq 2) 'Second SQLite writer bypassed BEGIN IMMEDIATE.'

    # Reproduce the old check-then-write race deterministically: after a
    # read-side lookup says unique, a different writer adds a colliding alias.
    $outsideGuardRejected = $false
    try { [void](Test-LfoMemoryUniqueCurrentSubject $db 'ORION' 'conversation:1') }
    catch { $outsideGuardRejected = ($_.Exception.Message -like '*requires an open SQLite writer transaction*') }
    Assert-LfoTest $outsideGuardRejected 'Authorization helper must reject checks outside a transaction.'
    $preflightRows = @(Invoke-LfoSqliteQuery $db "SELECT DISTINCT entity_id FROM entity_names WHERE normalized_name='orion';")
    Assert-LfoTest ($preflightRows.Count -eq 1) 'Fixture unexpectedly ambiguous before race.'
    Start-LfoMemoryTransaction $other
    try {
        Invoke-LfoSqliteNonQuery $other 'INSERT INTO entities(entity_type,created_turn) VALUES (?1,?2);' @('server',11)
        $newId = @(Invoke-LfoSqliteQuery $other 'SELECT last_insert_rowid() AS id;')
        Invoke-LfoSqliteNonQuery $other 'INSERT INTO entity_names(entity_id,name,normalized_name,source_turn) VALUES (?1,?2,?3,?4);' @([int64]$newId[0].id,'ORION','orion',11)
        Complete-LfoMemoryTransaction $other
    } catch { try { Undo-LfoMemoryTransaction $other } catch {}; throw }
    $race = Apply-LfoStructuredMemoryOps -Connection $db -ParsedOps (New-LfoTestInteger '192') -SourceTurn 12 -ScopeId 'conversation:1' -RequireUniqueCurrentSubject
    $afterRace = @(Get-LfoTestRam $db)
    Assert-LfoTest ($race.Status -eq 'guard-rejected' -and $race.AppliedCount -eq 0 -and $afterRace.Count -eq 2 -and [int64]$afterRace[1].value_integer -eq 96 -and $null -eq $afterRace[1].valid_to_turn) 'Alias collision between read and write was not rejected.'
    $otherScope = @(Get-LfoTestRam $db 'conversation:2')
    Assert-LfoTest ($otherScope.Count -eq 1 -and [int64]$otherScope[0].value_integer -eq 128 -and $null -eq $otherScope[0].valid_to_turn) 'Cross-epoch scope mutated.'
    [pscustomobject]@{PASS=$true;AtomicGuard=$true;DuplicateReplay=$true;DuplicateBatch=$true;InvalidShapeRejected=$true;ScopeRejected=$true;SqlFailureRollback=$true;LateBatchRollback=$true;WriterLockEnforced=$true;OutsideTransactionGuardRejected=$true;AliasRaceRejected=$true;ProductionMemoryTouched=$false;OllamaCalled=$false;TempRoot=$root} | Format-List
} finally {
    if ($null -ne $other) { Close-LfoSqliteDatabase $other }
    Close-LfoSqliteDatabase $db
}
