# Offline UMA contract and PowerShell AST checks; no model inference or service lifecycle.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$paths = @('install/Install-LFO.ps1','LFO.ps1','launch/Start-LFO.ps1','launch/Start-LFO-UMA.ps1','src/QwenChat.ps1')
$asts = @{}
foreach ($path in $paths) {
    $full = Join-Path $root ($path -replace '/','\')
    $tokens = $null
    $parseErrors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile($full,[ref]$tokens,[ref]$parseErrors)
    if (@($parseErrors).Count -gt 0) {
        throw ("PowerShell parse failed in {0}: {1}" -f $path,(@($parseErrors | ForEach-Object { $_.Message }) -join '; '))
    }
    $asts[$path] = $ast
}
$installer = Get-Content -LiteralPath (Join-Path $root 'install/Install-LFO.ps1') -Raw -Encoding UTF8
foreach ($required in @(
    "[ValidateSet('CPU','GPU','UMA')]",
    "qwen3.5:35b-a3b-q8_0",
    "lfo-qwen3.5-35b-uma16k:latest",
    'PARAMETER num_ctx $UmaContext',
    'PARAMETER num_gpu 99',
    'UMA refuses to start a second Ollama listener',
    'no automatic 35B download',
    'Start-LFO-UMA.ps1',
    'UMAModel=$UmaModel;UMAContext=$UmaContext'
)) {
    if (-not $installer.Contains($required)) { throw "Missing UMA installer contract: $required" }
}
$fnNames = @('Resolve-LfoDevice','Get-LfoModelSpec','Get-LfoPromptArray','New-LfoBatchInputFile')
foreach ($name in $fnNames) {
    $found = @($asts['LFO.ps1'].FindAll({
        param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
    },$true))
    if ($found.Count -ne 1) { throw "Expected one function $name, found $($found.Count)" }
    . ([scriptblock]::Create($found[0].Extent.Text))
}
$state = [pscustomobject]@{
    LFO = [pscustomobject]@{ DefaultProfile = 'UMA' }
    Ollama = [pscustomobject]@{
        CPUModel='lfo-qwen3.5-4b-cpu5k:latest'
        GPUModel='lfo-qwen3.5-4b-gpu8k:latest'
        UMAModel='lfo-qwen3.5-35b-uma16k:latest'
        UMAContext=16384
    }
}
if ((Resolve-LfoDevice 'Auto' $state) -ne 'UMA') { throw 'UMA auto device resolution failed.' }
if ((Resolve-LfoDevice 'UMA' $state) -ne 'UMA') { throw 'Explicit UMA selection failed.' }
$uma = Get-LfoModelSpec $state 'UMA'
if ($uma.Model -ne $state.Ollama.UMAModel -or $uma.Context -ne 16384) { throw 'UMA model spec mismatch.' }
if ((Get-LfoModelSpec $state 'CPU').Context -ne 5120) { throw 'Legacy CPU context changed.' }
if ((Get-LfoModelSpec $state 'GPU').Context -ne 8192) { throw 'Legacy GPU context changed.' }
$state.LFO.DefaultProfile='CPU'
if ((Resolve-LfoDevice 'UMA' $state) -ne 'UMA') { throw 'Explicit UMA override failed on legacy host.' }
Write-Host 'PASS: UMA source syntax, installer guards, model specs and legacy context invariants.' -ForegroundColor Green

foreach($name in @('Get-OllamaLibraryManifestPath','Test-OllamaStoreHasModel','Get-LfoSourceArchiveUrl')){
    $fn=@($asts['install/Install-LFO.ps1'].FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true))
    if($fn.Count -ne 1){throw "Missing helper $name"}
    . ([scriptblock]::Create($fn[0].Extent.Text))
}
$archiveBase='https://codeload.github.com/tomasgal/local-frontier-orchestrator/zip/'
foreach($ref in @('v9.6.7','refs/tags/v9.6.7')){
    if((Get-LfoSourceArchiveUrl $ref) -cne ($archiveBase+'refs/tags/v9.6.7')){throw 'Release tag archive URL incorrect'}
}
if((Get-LfoSourceArchiveUrl 'main') -cne ($archiveBase+'refs/heads/main')){throw 'Branch archive URL incorrect'}
if((Get-LfoSourceArchiveUrl 'refs/heads/feat/example') -cne ($archiveBase+'refs/heads/feat/example')){throw 'Explicit branch archive URL incorrect'}
$sha='0123456789abcdef0123456789abcdef01234567'
if((Get-LfoSourceArchiveUrl $sha) -cne ($archiveBase+$sha)){throw 'Pinned SHA archive URL incorrect'}
if(-not $installer.Contains("rev-parse 'FETCH_HEAD^{commit}'")){throw 'Annotated release tag is not peeled to commit'}
Write-Host 'PASS: tagged/branch/SHA bootstrap source resolution.'
$temp=Join-Path ([IO.Path]::GetTempPath()) ('lfo-manifest-test-'+[guid]::NewGuid().ToString('N'))
try{
    $old=Join-Path $temp 'manifests\registry.ollama.ai\library\test-model\latest'
    $new=Join-Path $temp 'manifests-v2\ollama.com\library\test-model\latest'
    if(Test-OllamaStoreHasModel $temp 'test-model:latest'){throw 'Absent manifest accepted'}
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $old)|Out-Null
    Set-Content -LiteralPath $old -Value '{}'
    if(-not (Test-OllamaStoreHasModel $temp 'test-model:latest')){throw 'Legacy manifest not detected'}
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $new)|Out-Null
    Set-Content -LiteralPath $new -Value '{}'
    if((Get-OllamaLibraryManifestPath $temp 'test-model:latest') -ne $new){throw 'v2 manifest not preferred'}
    Remove-Item -LiteralPath $old
    if(-not (Test-OllamaStoreHasModel $temp 'test-model:latest')){throw 'v2-only manifest not detected'}
    foreach($name in @('ConvertTo-LfoSafeConsoleText','Get-LfoMarkdownInlineSpans','Get-LfoTransferFile','Write-LfoTransferExport','Get-LfoTableCells','Get-LfoVisibleWidth','Split-LfoTableCell','Get-LfoTableLayout','Get-LfoMarkdownTableBlock','Split-LfoImportPrompts','Get-LfoGenerationBudget','Get-LfoPartialJsonAnswer','Add-LfoStructuredAnswerPolicy','Get-LfoRequestedRouteMode','Get-LfoStreamBlockBoundary','Read-LfoChatNdjson','Write-LfoStreamThinkingChunk','Show-QwenThinking','Wait-LfoCodexExit','Get-LfoSlashCommands','Get-LfoSlashCommandState','Show-LfoSlashHelp','Add-LfoLocalEvidencePolicy')){
        $fn=@($asts['src/QwenChat.ps1'].FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true))
        if($fn.Count -ne 1){throw "Missing helper $name"}
        . ([scriptblock]::Create($fn[0].Extent.Text))
    }
    $spans=@(Get-LfoMarkdownInlineSpans 'Plain **bold** and *italic*')
    if(($spans.Text -join '') -ne 'Plain bold and italic'){throw 'Markdown inline mismatch'}
    if(-not ($spans|Where-Object {$_.Text -eq 'bold' -and $_.Color -eq 'White'})){throw 'Markdown color mismatch'}
    if((ConvertTo-LfoSafeConsoleText ('a'+[char]27+'b')) -ne 'ab'){throw 'Unsafe terminal control'}
    $file=Get-LfoTransferFile $temp 'reply.md'
    Write-LfoTransferExport $file 'original **Markdown**'
    if([IO.File]::ReadAllText($file) -ne 'original **Markdown**'){throw 'Export changed raw Markdown'}
    $rejected=$false;try{Get-LfoTransferFile $temp '..\outside.md'|Out-Null}catch{$rejected=$true}
    if(-not $rejected){throw 'Path traversal accepted'}
    $rejected=$false;try{Write-LfoTransferExport $file 'overwrite'}catch{$rejected=$true}
    if(-not $rejected){throw 'Export overwrite accepted'}
    $layout=Get-LfoTableLayout @('| Name | Description |','| --- | ---: |','| **RAM** | Long text that wraps correctly |','| GPU | Compute |') 28
    if($null -eq $layout -or $layout.Rows.Count -ne 3 -or $layout.Rows[1][0] -ne 'RAM' -or $layout.Align[1] -ne 'right'){throw 'Table layout failed'}
    if((($layout.Widths|Measure-Object -Sum).Sum+7) -gt 28){throw 'Table exceeds width'}
    $block=Get-LfoMarkdownTableBlock @('| Column 1 | Column 2 | Description','| :--- | :--- | :--- |','| A | X | Long description that must wrap across several lines |','B | Y | More words without outer pipes','Paragraph outside the table') 0 32
    if($null -eq $block -or $block.EndIndex -ne 3 -or $block.Layout.Rows.Count -ne 3){throw 'Optional outer pipes not recognized'}
    if((($block.Layout.Widths|Measure-Object -Sum).Sum+10) -gt 32){throw 'Optional-pipe table exceeds width'}
    $wrapped=@(Split-LfoTableCell $block.Layout.Rows[1][2] $block.Layout.Widths[2])
    if($wrapped.Count -lt 2){throw 'Long table cell did not wrap'}
    foreach($part in $wrapped){if((Get-LfoVisibleWidth $part) -gt $block.Layout.Widths[2]){throw 'Wrapped table cell exceeds column width'}}
    if($null -ne (Get-LfoMarkdownTableBlock @('A | B','Not a separator') 0 32)){throw 'Non-table misclassified'}
    $pieces=@(Split-LfoTableCell 'a verylongunbrokenword and more text' 5)
    foreach($piece in $pieces){if((Get-LfoVisibleWidth $piece) -gt 5){throw 'Cell wrap exceeds width'}}
    $nl=[string][char]10;$crlf=[string][char]13+$nl
    $entries=@(Split-LfoImportPrompts ('First line'+$nl+'Second line'+$crlf+' ||| '+$crlf+'/think on'+$nl+'|||'+$nl+'/analyze'+$nl+'|||'+$nl))
    if($entries.Count -ne 3 -or $entries[0] -ne ('First line'+$nl+'Second line') -or $entries[1] -ne '/think on' -or $entries[2] -ne '/analyze'){throw 'Import split failed'}
    if(@(Split-LfoImportPrompts 'literal ||| inline').Count -ne 1){throw 'Inline separator was split'}
    $many=@(Split-LfoImportPrompts ((1..1000|ForEach-Object{"Prompt $_"}) -join ($nl+'|||'+$nl)))
    if($many.Count -ne 1000 -or $many[999] -ne 'Prompt 1000'){throw 'Large import split failed'}
    # Exercise exact array-capture expressions from the real experiment runner.
    $source=Get-Content -LiteralPath (Join-Path $root 'LFO.ps1') -Raw -Encoding UTF8
    $plan='{"warmup":{"prompts":["Warmup"]},"workload":{"setupPrompts":["Setup"],"prompts":["Measured"]}}' | ConvertFrom-Json
    foreach($variable in @('warmupPrompts','setupPrompts','measuredPrompts')){
        $pattern='(?m)\$'+$variable+' = @\(Get-LfoPromptArray \$plan\.[\w.]+\)'
        $match=[regex]::Match($source,$pattern)
        if(-not $match.Success){throw "Missing array capture: $variable"}
        . ([scriptblock]::Create($match.Value))
    }
    if($measuredPrompts.Count -ne 1 -or $measuredPrompts[0] -isnot [string] -or $measuredPrompts[0] -ne 'Measured'){throw 'Single measured prompt collapsed'}
    $batch=Join-Path $temp 'batch.json'
    New-LfoBatchInputFile $batch @($setupPrompts + @($measuredPrompts[0]))
    $items=@((Get-Content $batch -Raw -Encoding UTF8|ConvertFrom-Json).prompts)
    if($items.Count -ne 2 -or $items[0].text -ne 'Setup' -or $items[1].text -ne 'Measured'){throw 'Single setup/measured prompt batch corrupted'}
    $rejected=$false;try{New-LfoBatchInputFile $batch @('')}catch{$rejected=$true}
    if(-not $rejected){throw 'Empty batch prompt accepted'}
    $g=@{NumPredictNormal=1024;NumPredictThink=2048;UmaNumPredictNormal=4096;UmaNumPredictThink=8192}
    $msgs=@(@{role='user';content='Short prompt'})
    if((Get-LfoGenerationBudget $g $false 'UMA' 16384 $msgs @{}) -ne 4096){throw 'UMA normal budget mismatch'}
    if((Get-LfoGenerationBudget $g $true 'UMA' 16384 $msgs @{}) -ne 8192){throw 'UMA think budget mismatch'}
    if((Get-LfoGenerationBudget $g $true 'GPU' 8192 $msgs @{}) -ne 2048){throw 'Legacy generation budget changed'}
    $long=@(@{role='user';content=('x'*36000)})
    if((Get-LfoGenerationBudget $g $true 'UMA' 16384 $long @{}) -ge 8192){throw 'UMA context headroom not applied'}
    if((Get-LfoPartialJsonAnswer '{"memory_ops":[{"answer":"secret"}],"answer":"First\nSecond') -ne ('First'+[char]10+'Second')){throw 'Truncated answer recovery failed'}
    if((Get-LfoPartialJsonAnswer '{"memory_ops":[{"answer":"secret"}]') -ne ''){throw 'Nested answer exposed'}
    if((Get-LfoPartialJsonAnswer '{"answer":"escaped \"quote\" and \u00') -ne 'escaped "quote" and'){throw 'Partial escape recovery failed'}
    if((Get-LfoPartialJsonAnswer '{"answer":"Complete","memory_ops":[') -ne 'Complete'){throw 'Complete answer prefix lost'}
    if((Add-LfoStructuredAnswerPolicy 'base' 'GPU') -cne 'base'){throw 'Legacy answer policy changed'}
    $answerPolicy=Add-LfoStructuredAnswerPolicy 'base' 'UMA'
    if(-not $answerPolicy.StartsWith('base') -or -not $answerPolicy.Contains('\"') -or -not $answerPolicy.Contains('verbatim')){throw 'UMA structured answer policy missing'}
    if((Get-LfoRequestedRouteMode 'Bez pouzitia FRONTIER vysvetli RAM.' 'AUTO') -ne 'LOCAL'){throw 'Explicit local-only instruction not enforced'}
    if((Get-LfoRequestedRouteMode 'Translate the phrase without using FRONTIER.' 'AUTO') -ne 'AUTO'){throw 'Embedded phrase changed route'}
    if((Get-LfoRequestedRouteMode 'Search the web' 'LOCAL') -ne 'LOCAL'){throw 'Session LOCAL override lost'}
    if((Get-LfoRequestedRouteMode 'Explain RAM' 'FRONTIER') -ne 'FRONTIER'){throw 'Session FRONTIER override lost'}
    if((Get-LfoPartialJsonAnswer '{"answer":"LOCAL","route":"LOC' 'route' -RequireComplete) -ne ''){throw 'Incomplete route accepted'}
    if((Get-LfoPartialJsonAnswer '{"memory_ops":[{"route":"LOCAL"}],"route":"FRONTIER"}' 'route' -RequireComplete) -ne 'FRONTIER'){throw 'Nested route confused with root'}
    $fence='~'*3
    $blocks='First'+$nl+$nl+$fence+'python'+$nl+'x = 1'+$nl+$nl+'y = 2'
    if((Get-LfoStreamBlockBoundary $blocks) -ne 7){throw 'Preview flushed incomplete fence'}
    $blocks+=$nl+$fence+$nl+$nl+'Next'
    if((Get-LfoStreamBlockBoundary $blocks) -ne ($blocks.Length-4)){throw 'Closed fence not flushed'}
    $chunks=@(
        (@{message=@{content='{"route":"LOCAL","answer":"A';thinking='reason '};done=$false}|ConvertTo-Json -Depth 8 -Compress),
        (@{message=@{content='\nB","memory_note":"-","memory_ops":[]}';thinking='end'};done=$false}|ConvertTo-Json -Depth 8 -Compress),
        (@{message=@{content=''};done=$true;done_reason='stop';eval_count=7;prompt_eval_count=3}|ConvertTo-Json -Depth 8 -Compress)
    )
    $reader=New-Object IO.StringReader(($chunks -join $nl))
    try{$result=Read-LfoChatNdjson $reader ([Diagnostics.Stopwatch]::StartNew()) 'local_generation' $false 'AUTO' $false}finally{$reader.Dispose()}
    $envelope=$result.message.content|ConvertFrom-Json
    if($envelope.answer -ne ('A'+$nl+'B') -or $result.message.thinking -ne 'reason end' -or $result.eval_count -ne 7 -or $result.done_reason -ne 'stop' -or -not $result.lfo_streamed){throw 'NDJSON assembly lost content or metrics'}
    $reader=New-Object IO.StringReader($chunks[0]);$rejected=$false
    try{Read-LfoChatNdjson $reader ([Diagnostics.Stopwatch]::StartNew()) 'local_generation' $false 'AUTO' $false|Out-Null}catch{$rejected=$true}finally{$reader.Dispose()}
    if(-not $rejected){throw 'Missing final stream chunk accepted'}
    # AUTO may display the answer before the route field arrives, even if
    # the final route is FRONTIER. No memory side channel is displayed.
    $script:previewCalls=New-Object 'System.Collections.Generic.List[string]'
    function Write-LfoStreamPreview([string]$Answer){
        [void]$script:previewCalls.Add($Answer)
        return $true
    }
    $previewChunks=@(
        (@{message=@{content='{"answer":"Provisional\n\nNext'};done=$false}|ConvertTo-Json -Depth 8 -Compress),
        (@{message=@{content='","memory_note":"private marker","memory_ops":[],"route":"FRONTIER"}'};done=$true;done_reason='stop'}|ConvertTo-Json -Depth 8 -Compress)
    )
    $reader=New-Object IO.StringReader(($previewChunks -join $nl))
    try{$result=Read-LfoChatNdjson $reader ([Diagnostics.Stopwatch]::StartNew()) 'local_generation' $true 'AUTO' $false}finally{$reader.Dispose()}
    if($script:previewCalls.Count -lt 2 -or $script:previewCalls[0] -ne ('Provisional'+$nl+$nl+'Next')){throw 'AUTO preview waited for route'}
    if(($script:previewCalls -join ' ') -match 'private marker'){throw 'Memory bookkeeping leaked into preview'}
    if(($result.message.content|ConvertFrom-Json).route -ne 'FRONTIER'){throw 'Preview changed final routing'}
    # Thinking is independently streamed when explicitly enabled. The
    # final response keeps the original text, and the final renderer must
    # not replay the thinking already displayed.
    $thinkChunks=@(
        (@{message=@{thinking='Reasoning first';content=''};done=$false}|ConvertTo-Json -Depth 8 -Compress),
        (@{message=@{thinking=' and last';content=''};done=$false}|ConvertTo-Json -Depth 8 -Compress),
        (@{message=@{thinking='';content='{"answer":"Visible answer\n\nNext","route":"LOCAL"}'};done=$true;done_reason='stop'}|ConvertTo-Json -Depth 8 -Compress)
    )
    $script:previewCalls.Clear()
    $reader=New-Object IO.StringReader(($thinkChunks -join $nl))
    try{$captured=@(Read-LfoChatNdjson $reader ([Diagnostics.Stopwatch]::StartNew()) 'local_generation' $true 'AUTO' $false $true 6>&1)}finally{$reader.Dispose()}
    $result=@($captured|Where-Object {$_ -isnot [Management.Automation.InformationRecord]})[0]
    $shown=($captured|Where-Object {$_ -is [Management.Automation.InformationRecord]}|ForEach-Object {[string]$_.MessageData}) -join ''
    if($result.message.thinking -ne 'Reasoning first and last' -or -not $result.lfo_thinking_previewed -or $null -eq $result.lfo_first_thinking_seconds){throw 'Thinking stream assembly failed'}
    if($shown -notmatch '--- thinking ---.*Reasoning first and last.*--- answer ---'){throw 'Thinking display sequence failed'}
    if($script:previewCalls.Count -lt 1 -or $script:previewCalls[0] -notmatch '^Visible answer'){throw 'Thinking blocked answer preview'}
    $script:ThinkEnabled=$true
    if(@(Show-QwenThinking $result 6>&1).Count -ne 0){throw 'Thinking replayed after streaming'}
    $script:ThinkEnabled=$false
    $reader=New-Object IO.StringReader(($thinkChunks -join $nl))
    try{$captured=@(Read-LfoChatNdjson $reader ([Diagnostics.Stopwatch]::StartNew()) 'local_generation' $false 'AUTO' $false $false 6>&1)}finally{$reader.Dispose()}
    if(@($captured|Where-Object {$_ -is [Management.Automation.InformationRecord]}).Count -ne 0){throw 'Disabled thinking leaked to console'}
    $fake=[pscustomobject]@{Waits=(New-Object 'System.Collections.Generic.List[int]')}
    $fake|Add-Member ScriptMethod WaitForExit {param([int]$Milliseconds);[void]$this.Waits.Add($Milliseconds);return $true}
    if(-not (Wait-LfoCodexExit $fake 30 $true) -or $fake.Waits[0] -gt 5000){throw 'Interactive Codex wait interval incorrect'}
    $fake.Waits.Clear()
    if(-not (Wait-LfoCodexExit $fake 30 $false) -or $fake.Waits[0] -ne 30000){throw 'Benchmark Codex wait changed'}
    # A fake process returns immediately after one unsuccessful wait.
    # This exercises overwrite and newline cleanup without sleeping five seconds.
    $fakeHeartbeat=[pscustomobject]@{Calls=0}
    $fakeHeartbeat|Add-Member ScriptMethod WaitForExit {param([int]$Milliseconds);$this.Calls++;return ($this.Calls -gt 1)}
    $heartbeatOutput=@(Wait-LfoCodexExit $fakeHeartbeat 30 $true 6>&1)
    $heartbeatRecords=@($heartbeatOutput|Where-Object {$_ -is [Management.Automation.InformationRecord]})
    if($heartbeatRecords.Count -ne 2){throw 'Codex heartbeat did not produce status and final newline'}
    $heartbeatMessage=$heartbeatRecords[0].MessageData
    if(-not ([string]$heartbeatMessage).StartsWith([string][char]13) -or -not $heartbeatMessage.NoNewLine){throw 'Codex heartbeat did not overwrite current line'}
    if($heartbeatRecords[1].MessageData.NoNewLine){throw 'Codex heartbeat left terminal line open'}
    # Every documented command has a valid form; every invalid slash entry
    # stays in the local UI. Optional arguments preserve their defaults.
    $validCommands=@('/help','/help think','/help /route','/think on','/THINK OFF','/route auto','/route local','/route frontier','/stream on','/stream off','/analyze','/analyze 001','/analyze 100','/files','/import prompt file.txt','/export','/export answer.md','/export-log','/paste','/clear','/exit')
    foreach($cmd in $validCommands){if((Get-LfoSlashCommandState $cmd) -ne 'VALID'){throw "Valid command rejected: $cmd"}}
    $invalidCommands=@('/think','/think maybe','/route','/route web','/stream','/stream yes','/analyze 0','/analyze 101','/analyze x','/import','/files x','/export-log x','/paste x','/clear x','/exit x','/help two words')
    foreach($cmd in $invalidCommands){if((Get-LfoSlashCommandState $cmd) -ne 'USAGE'){throw "Invalid command bypassed help: $cmd"}}
    foreach($cmd in @('/th','/thnik','/unknown','/')){if((Get-LfoSlashCommandState $cmd) -ne 'UNKNOWN'){throw "Unknown slash command accepted: $cmd"}}
    if((Get-LfoSlashCommandState 'Explain /think on') -ne 'PROMPT'){throw 'Ordinary prompt mistaken for command'}
    $helpOutput=@(Show-LfoSlashHelp '/think' 6>&1)
    if(($helpOutput -join ' ') -notmatch '/think on.*?/think off'){throw 'Missing thinking parameter help'}
    $helpOutput=@(Show-LfoSlashHelp '' -ExplicitHelp 6>&1)
    foreach($key in (Get-LfoSlashCommands).Keys){if(($helpOutput -join ' ') -notmatch [regex]::Escape($key)){throw "Help missing $key"}}
    # Check actual dispatcher contains the guard before routing, including
    # queued interactive imports. Experiment adapter still calls Invoke-Qwen directly.
    $chatSource=Get-Content -LiteralPath (Join-Path $root 'src/QwenChat.ps1') -Raw -Encoding UTF8
    $loop=$chatSource.Substring($chatSource.LastIndexOf('while ($true) {'))
    if($loop.IndexOf('$commandState=Get-LfoSlashCommandState $prompt') -lt 0 -or $loop.IndexOf('$commandState=Get-LfoSlashCommandState $prompt') -gt $loop.IndexOf('switch -Regex')){throw 'Missing pre-dispatch command guard'}
    if(-not $loop.Contains("if("+ '$commandState' +" -eq 'PROMPT'){Invoke-Qwen "+'$prompt'+"}")){throw 'Default dispatcher can send slash commands to inference'}
    $evidencePolicy=Add-LfoLocalEvidencePolicy 'base' 'LOCAL'
    if($evidencePolicy -notmatch 'no live external lookup' -or $evidencePolicy -notmatch 'LOCAL is explicitly enforced' -or $evidencePolicy -notmatch 'not fresh verification'){throw 'Missing local evidence boundary'}
    if((Add-LfoLocalEvidencePolicy 'base' 'AUTO') -match 'LOCAL is explicitly enforced'){throw 'AUTO incorrectly forced local'}
    . (Join-Path $root 'src/LfoTurnTelemetry.ps1')
    $testPhases=@(
        [pscustomobject]@{kind='model';phase='local_generation';prompt_eval_count=100;eval_count=20;decode_seconds=0.5},
        [pscustomobject]@{kind='model';phase='answer_recovery';prompt_eval_count=200;eval_count=180;decode_seconds=4.5},
        [pscustomobject]@{kind='frontier';phase='frontier_handoff';prompt_eval_count=$null;eval_count=$null;decode_seconds=$null},
        [pscustomobject]@{kind='model';phase='memory_recovery';prompt_eval_count=50;eval_count=10;decode_seconds=1.0}
    )
    $totals=Get-LfoAnswerGenerationTotals $testPhases
    if($totals.calls -ne 2 -or $totals.prompt_tokens -ne 300 -or $totals.generated_tokens -ne 200 -or $totals.decode_tokens_per_second -ne 40){throw 'Answer telemetry totals incorrect'}
    $testPhases[1].eval_count=$null
    $totals=Get-LfoAnswerGenerationTotals $testPhases
    if($null -ne $totals.generated_tokens -or $null -ne $totals.decode_tokens_per_second){throw 'Unknown token metrics treated as zero'}
    . (Join-Path $root 'src/LfoEvidenceProvenance.ps1')
    foreach($status in @('NONE','REQUESTED','OBSERVED','UNKNOWN')){
        $row=[pscustomobject]@{route='LOCAL';external_evidence_status=$status;assistant='unchanged'}
        if((Get-LfoExternalEvidenceStatus $row) -cne $status){throw 'Historical evidence status not preserved'}
        if((Get-LfoHistoricalTurnLabel $row) -cne "[route=LOCAL; external_evidence=$status]"){throw 'Incorrect historical evidence label'}
        if($row.assistant -cne 'unchanged'){throw 'Historical content changed'}
    }
    foreach($row in @([pscustomobject]@{route='FRONTIER'},[pscustomobject]@{route='FRONTIER';external_evidence_status='VERIFIED'},[pscustomobject]@{route='FRONTIER';external_evidence_status='requested'})){
        if((Get-LfoExternalEvidenceStatus $row) -cne 'UNKNOWN'){throw 'Missing or invalid metadata promoted'}
    }
    # Real L3 fallback reads a synthetic historical row from a temp JSONL.
    . (Join-Path $root 'src/LfoL3Runtime.ps1')
    $evidenceDir=Join-Path $temp 'evidence-fixtures'
    New-Item -ItemType Directory -Force -Path $evidenceDir|Out-Null
    $row=[ordered]@{event='turn';epoch=1;turn_id=7;route='FRONTIER';external_evidence_status='REQUESTED';user='question';assistant='claim'}
    $row|ConvertTo-Json -Compress|Set-Content -LiteralPath (Join-Path $evidenceDir 'conversation-2026-01.jsonl') -Encoding UTF8
    $candidate=[pscustomobject]@{Id=1;SourceLayer='L0';SourceRef='turn:7'}
    $found=@(Get-LfoL3RuntimeL0Evidence @($candidate) $evidenceDir 1)
    if($found.Count -ne 1 -or $found[0].Text -cne 'T7 [route=FRONTIER; external_evidence=REQUESTED] U:question A:claim'){throw 'L3 provenance inheritance failed'}
    if(-not $chatSource.Contains("-ExternalEvidenceStatus "+'$externalEvidenceStatus')){throw 'Runtime evidence status not passed to persistence'}
    Write-Host 'PASS: additive turn evidence metadata, legacy UNKNOWN and L3 provenance inheritance.'
    Write-Host 'PASS: local evidence policy and answer-generation telemetry aggregation.'
    Write-Host 'PASS: all slash-command parameter validation, help and inference guard.'
    Write-Host 'PASS: thinking preview, answer continuation, no duplicate reasoning, and Codex wait modes.'
    Write-Host 'PASS: AUTO preview independent of final route.'
    Write-Host 'PASS: explicit routing, Markdown stream boundaries, NDJSON assembly and incomplete transport rejection.'
    Write-Host 'PASS: UMA generation ceilings, context estimate and partial JSON isolation.'
    Write-Host 'PASS: singleton experiment prompt arrays and batch input validation.'
    Write-Host 'PASS: aligned table layout, width, wrapping, multiline import and 1000-entry splitting.'
    Write-Host 'PASS: v1/v2 manifests, Markdown spans, control stripping, raw export, path and overwrite guards.'
}finally{Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}
