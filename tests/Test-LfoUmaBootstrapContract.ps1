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

foreach($name in @('Get-OllamaLibraryManifestPath','Test-OllamaStoreHasModel')){
    $fn=@($asts['install/Install-LFO.ps1'].FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true))
    if($fn.Count -ne 1){throw "Missing helper $name"}
    . ([scriptblock]::Create($fn[0].Extent.Text))
}
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
    foreach($name in @('ConvertTo-LfoSafeConsoleText','Get-LfoMarkdownInlineSpans','Get-LfoTransferFile','Write-LfoTransferExport','Get-LfoTableCells','Get-LfoVisibleWidth','Split-LfoTableCell','Get-LfoTableLayout','Get-LfoMarkdownTableBlock','Split-LfoImportPrompts','Get-LfoGenerationBudget','Get-LfoPartialJsonAnswer','Add-LfoStructuredAnswerPolicy','Get-LfoRequestedRouteMode','Get-LfoStreamBlockBoundary','Read-LfoChatNdjson')){
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
    Write-Host 'PASS: AUTO preview independent of final route.'
    Write-Host 'PASS: explicit routing, Markdown stream boundaries, NDJSON assembly and incomplete transport rejection.'
    Write-Host 'PASS: UMA generation ceilings, context estimate and partial JSON isolation.'
    Write-Host 'PASS: singleton experiment prompt arrays and batch input validation.'
    Write-Host 'PASS: aligned table layout, width, wrapping, multiline import and 1000-entry splitting.'
    Write-Host 'PASS: v1/v2 manifests, Markdown spans, control stripping, raw export, path and overwrite guards.'
}finally{Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}
