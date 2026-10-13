$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
. (Join-Path $repo 'src\LfoStructuredMemory.ps1')
. (Join-Path $repo 'src\LfoTurnTelemetry.ps1')
. (Join-Path $repo 'src\QwenMemory.ps1')
. (Join-Path $repo 'src\LfoL3Runtime.ps1')
$script:checks=0
function Assert([bool]$c,[string]$m){$script:checks++;if(-not $c){throw $m}}
function Configure([string]$root){
    $script:Config=Import-PowerShellDataFile (Join-Path $repo 'config\QwenChat.config.psd1')
    $script:Config.Memory.DataDirectory=$root
    $script:Config.Memory.L0StageSourcesEnabled=$true
    $script:Config.Memory.StructuredEnabled=$false
    $script:Config.ResearchLogging.Enabled=$false
    Initialize-QwenMemoryConfiguration
    $script:RuntimeState=New-DefaultRuntimeState
    $script:LfoTurnContext=$null
}
$root=Join-Path ([IO.Path]::GetTempPath()) ('lfo-l4-connector-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $root
try{
    Configure (Join-Path $root 'ok')
    $script:l4Calls=0;$script:sawAuthoritativeL0=$false
    function Invoke-LfoL4PostTurn {
        param([string]$Prompt,[string]$FinalContent,[int]$TurnId,[int]$Epoch,[string]$SourceFile,[string]$Timestamp,[object[]]$StageSources)
        $script:l4Calls++
        $path=Join-Path $script:LogDir $SourceFile
        Assert (Test-Path -LiteralPath $path -PathType Leaf) 'L4 hook ran before L0 file existed'
        $row=Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json
        Assert ($row.turn_id -eq $TurnId -and $row.epoch -eq $Epoch) 'L4 hook identity differs from authoritative L0'
        Assert ($row.user -ceq $Prompt -and $row.assistant -ceq $FinalContent) 'L4 hook content differs from authoritative L0'
        Assert (@($row.stage_sources).Count -eq @($StageSources).Count -and @($StageSources).Count -eq 2) 'L4 hook stage provenance differs from L0'
        $script:sawAuthoritativeL0=$true
    }
    $stages=@(
        [pscustomobject]@{stage_id='s1';actor='USER';stage='INPUT';phase='input';producer='USER';captured_at=[DateTime]::UtcNow.ToString('o');status='received';model=$null;source_field='user'},
        [pscustomobject]@{stage_id='s2';actor='FINAL';stage='FINAL_RESPONSE';phase='initial';producer='LOCAL';captured_at=[DateTime]::UtcNow.ToString('o');status='delivered';model='fixture';source_field='assistant'}
    )
    $emptyOps=[pscustomobject]@{Valid=@();Rejected=@()}
    Persist-TurnAndMemory -Prompt 'fixture prompt' -FinalContent 'fixture answer' -Route 'LOCAL' -AnswerSeconds 0 -InlineMemoryOps $emptyOps -StageSources $stages
    Assert ($script:l4Calls -eq 1 -and $script:sawAuthoritativeL0) 'ordinary persistence did not invoke L4 exactly once after L0'
    Assert ($script:RuntimeState.next_turn_id -eq 2) 'ordinary turn state did not advance'

    Configure (Join-Path $root 'fail-open')
    function Invoke-LfoL4PostTurn { throw 'synthetic L4 connector failure' }
    Persist-TurnAndMemory -Prompt 'second prompt' -FinalContent 'second answer' -Route 'LOCAL' -AnswerSeconds 0 -InlineMemoryOps $emptyOps -StageSources $stages
    $row2=Get-Content -LiteralPath (Get-MonthlyLogPath 'conversation') -Raw -Encoding UTF8|ConvertFrom-Json
    Assert ($row2.user -ceq 'second prompt' -and $row2.assistant -ceq 'second answer') 'L4 failure blocked authoritative L0 persistence'
    Assert ($script:RuntimeState.next_turn_id -eq 2) 'L4 failure blocked ordinary turn progression'
    Write-Host ("L4_QWEN_CONNECTOR_PASS: checks={0}; hook_after_L0=True; failure_isolated=True; ModelCalls=0" -f $script:checks)
}finally{Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue}
