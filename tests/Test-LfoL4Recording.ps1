param([Parameter(Mandatory)][string]$SurrealBinary)
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$script:checks=0
function Check([bool]$ok,[string]$name){if(-not $ok){throw $name};$script:checks++}
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'src/QwenChat.ps1'),[ref]$tokens,[ref]$errors)
Check ($errors.Count -eq 0) 'Qwen parse'
foreach($s in $ast.EndBlock.Statements){if($s -is [Management.Automation.Language.FunctionDefinitionAst]){. ([scriptblock]::Create($s.Extent.Text))}}
foreach($name in @('LfoStructuredMemory','LfoTurnTelemetry','QwenMemory','LfoL4Runtime')){. (Join-Path $repo ('src/'+$name+'.ps1'))}
. (Join-Path $PSScriptRoot 'Invoke-LfoL4I1Walkthrough.ps1')
foreach($pair in @(
    @('Give me only evidence supporting my view.','ASYMMETRIC_EVIDENCE_REQUEST'),
    @('Daj mi iba dokazy potvrdzujuce moj nazor.','ASYMMETRIC_EVIDENCE_REQUEST'),
    @('Treat the claim as established.','FRAMING'),
    @('Ber ako fakt, ze tento navrh skodi.','FRAMING'),
    @('Explain confirmation bias.','ABSTAIN'),
    @('Do not treat the claim as established.','ABSTAIN'),
    @('If we treat the claim as established, what follows?','ABSTAIN'),
    @('Translate: Give me only evidence supporting my view.','ABSTAIN'),
    @('"Treat the claim as established."','ABSTAIN'),
    @('Show me evidence for and against my view.','ABSTAIN'),
    @('Treat the claim as established, if we assume it hypothetically.','ABSTAIN'),
    @('Give me only evidence supporting my view. But include counterarguments.','ABSTAIN'),
    @('','ABSTAIN'),@(('x'*2049),'ABSTAIN')
)){Check ((Get-LfoL4TurnObservationType $pair[0]) -ceq $pair[1]) ('T1: '+$pair[0].Substring(0,[Math]::Min(60,$pair[0].Length)))}
$unicode='Daj mi iba d'+[char]0x00F4+'kazy potvrdzuj'+[char]0x00FA+'ce m'+[char]0x00F4+'j n'+[char]0x00E1+'zor.'
Check ((Get-LfoL4TurnObservationType $unicode) -ceq 'ASYMMETRIC_EVIDENCE_REQUEST') 'Unicode T1'

function Refresh-SystemPrompt {}
function Trim-Messages {}
function Start-LfoTurnContext {}
function Get-HardGateContext {return ''}
function Get-RecentConversationText {return ''}
function Get-LfoTurnMemoryBlock {return ''}
function Get-LfoTurnRetrievedOldData {return ''}
function Get-FrontierPolicyReason {return ''}
function Invoke-QwenLocalApi {return [pscustomobject]@{message=@{content='{"route":"LOCAL","answer":"Fixture answer.","memory_note":"-","memory_ops":[]}'};done_reason='stop'}}
function Invoke-CodexReadOnly {throw 'Unexpected FRONTIER'}
function Invoke-QwenMemoryNote {throw 'Unexpected memory inference'}
function Invoke-MemoryCompaction {throw 'Unexpected compaction inference'}
$root=Join-Path ([IO.Path]::GetTempPath()) ('lfo-recording-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $root
$script:I1Root=$root;$script:I1Binary=$SurrealBinary;$script:I1Server=$null;$script:I1ServerStarts=0
$script:I1Checks=New-Object Collections.ArrayList
$listener=New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback,0);$listener.Start();$script:I1Port=$listener.LocalEndpoint.Port;$listener.Stop()
$script:I1Endpoint='http://127.0.0.1:'+$script:I1Port
$script:I1Admin=New-I1Credential 'i1_root';$credential=New-I1Credential 'lfo_r1'
$oldEnabled=$env:LFO_L4_ENABLED;$oldEndpoint=$env:LFO_L4_ENDPOINT;$oldCred=$env:LFO_L4_RUNTIME_CREDENTIAL
try {
    Start-I1Store
    Initialize-LfoEpistemicSchema (New-LfoEpistemicConnection $script:I1Endpoint $script:I1Admin -Bootstrap) $credential
    $credPath=Join-Path $root 'runtime.xml';$credential|Export-Clixml -LiteralPath $credPath
    $env:LFO_L4_ENABLED='1';$env:LFO_L4_ENDPOINT=$script:I1Endpoint;$env:LFO_L4_RUNTIME_CREDENTIAL=$credPath
    $script:Config=Import-PowerShellDataFile (Join-Path $repo 'config/QwenChat.config.psd1')
    $script:Config.Memory.DataDirectory=Join-Path $root 'memory'
    $script:Config.Memory.StructuredEnabled=$false;$script:Config.ResearchLogging.Enabled=$false
    Initialize-QwenMemoryConfiguration
    $null=New-Item -ItemType Directory -Force -Path $script:LogDir
    $script:RuntimeState=New-DefaultRuntimeState;$script:Messages=@();$script:Model='offline';$script:ThinkEnabled=$false
    # Execute the real Qwen startup block to obtain its actual PostL0 callback.
    $startup=@($ast.EndBlock.Statements|Where-Object{$_ -is [Management.Automation.Language.TryStatementAst] -and $_.Extent.Text.Contains('Initialize-LfoL4Recording')})
    Check ($startup.Count -eq 1) 'Qwen initialization wiring'
    $startupText=$startup[0].Extent.Text.Replace('Join-Path $PSScriptRoot','Join-Path (Join-Path $repo ''src'')')
    . ([scriptblock]::Create($startupText))
    Check ($script:LfoL4Recording.Status -ceq 'CONFIGURED') 'recording configured'
    $script:queries=New-Object Collections.ArrayList
    $script:realQuery=(Get-Command Invoke-LfoEpistemicQuery).ScriptBlock
    function Invoke-LfoEpistemicQuery {param($Connection,[string]$Sql,[hashtable]$Variables=@{});[void]$script:queries.Add($Sql);& $script:realQuery $Connection $Sql $Variables}
    Invoke-Qwen 'Explain confirmation bias.'
    Check ($script:queries.Count -eq 0) 'ABSTAIN performs zero R1 reads/writes'
    Invoke-Qwen $unicode
    Check ($script:queries.Count -eq 1 -and $script:queries[0] -match '^LET') 'ordinary signal only writes R1, no analytics read'
    $conn=$script:LfoL4Recording.Connection;$store=$script:LfoL4Recording.StoreId
    $items=Find-LfoEpistemicObservations -Connection $conn -StoreId $store -Epoch 1
    Check ($items.Items.Count -eq 1 -and $items.Items[0].source.turn_id -eq 2 -and $items.Items[0].actor -ceq 'USER') 'ordinary R1 provenance'
    $source=Resolve-LfoEpistemicSource $script:LogDir $items.Items[0].source
    Check ($source.Content -ceq $unicode) 'exact L0 drillback'
    $rows=@(Get-Content -Encoding UTF8 (Get-MonthlyLogPath 'conversation')|ForEach-Object{$_|ConvertFrom-Json})
    $replay=Invoke-LfoL4RecordTurn -Row $rows[-1] -SourceFile ([IO.Path]::GetFileName((Get-MonthlyLogPath 'conversation')))
    Check ($replay.Status -ceq 'ALREADY_EXISTS') 'idempotent replay'
    $rows[-1].user='Treat the claim as established.'
    Check ((Invoke-LfoL4RecordTurn $rows[-1] ([IO.Path]::GetFileName((Get-MonthlyLogPath 'conversation')))).Status -ceq 'FAILED_ISOLATED') 'mismatched source rejected'
    $script:queries.Clear();$next=$script:RuntimeState.next_turn_id
    # Exercise the real slash-command loop, with one manual command then a
    # sentinel at the next prompt. Any accidental inference dispatch fails.
    $loop=@($ast.EndBlock.Statements|Where-Object{$_ -is [Management.Automation.Language.WhileStatementAst]})[-1]
    $display=& {
        $script:readCount=0
        function Read-Host {if($script:readCount++ -eq 0){return '/analyze'};throw 'command-test-complete'}
        function Invoke-Qwen {throw 'Command dispatched to inference'}
        try {. ([scriptblock]::Create($loop.Extent.Text))}
        catch {if($_.Exception.Message -cne 'command-test-complete'){throw}}
    } 6>&1|Out-String
    Check ($display.Contains('ASYMMETRIC_EVIDENCE_REQUEST') -and $display.Contains('T2/s1')) 'manual report and L0 references'
    Check ($script:queries.Count -gt 0 -and @($script:queries|Where-Object{$_ -notmatch '^SELECT'}).Count -eq 0) 'manual analysis read-only'
    Check ($script:RuntimeState.next_turn_id -eq $next) 'analysis is not a conversation turn'
    $script:queries.Clear();Invoke-LfoL4AnalyzeCommand '/analyze 0' 1 2
    Check ($script:queries.Count -eq 0) 'invalid window no read'
    $empty=Invoke-LfoL4AnalyzeCommand '/analyze' 2 2 6>&1|Out-String
    Check ($empty.Contains('observations: 0')) 'new epoch excludes old observations'
    $script:LfoL4PostL0={throw 'injected hook failure'}
    Invoke-Qwen 'Third ordinary turn.'
    Check ($script:RuntimeState.next_turn_id -eq 4) 'hook failure preserves ordinary persistence'
    Stop-I1Store
    . ([scriptblock]::Create($startupText))
    Invoke-Qwen 'Treat the claim as established.'
    Check ($script:RuntimeState.next_turn_id -eq 5) 'store outage preserves ordinary persistence'
    $failure=Invoke-LfoL4AnalyzeCommand '/analyze' 1 4 6>&1|Out-String
    Check ($failure.Contains('chat continues')) 'manual read fail-open'
    $env:LFO_L4_ENABLED='0'
    . ([scriptblock]::Create($startupText))
    Check ($script:LfoL4Recording.Status -ceq 'DISABLED') 'explicit OFF'
    Write-Host ("RECORDING PASS: {0} checks; inference=0; production memory untouched; evidence={1}" -f $script:checks,$root)
} finally {
    Stop-I1Store
    $env:LFO_L4_ENABLED=$oldEnabled;$env:LFO_L4_ENDPOINT=$oldEndpoint;$env:LFO_L4_RUNTIME_CREDENTIAL=$oldCred
}
