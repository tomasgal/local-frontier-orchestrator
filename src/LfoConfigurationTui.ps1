# DOS-inspired two-panel terminal UI. Nerd Font glyphs are optional; no font files.
function Get-LfoConfigurationViewport([int]$Columns,[int]$Lines){
    if($Columns -lt 65 -or $Lines -lt 18){throw 'Terminal too small for full-screen UI.'}
    # Leave the final cell to EL; never trigger terminal auto-wrap.
    $width=$Columns-1
    $left=[Math]::Min(26,[Math]::Max(19,[int][Math]::Floor($width/5)))
    [pscustomobject]@{Width=$width;Height=$Lines;Left=$left;Right=$width-$left-3;Rows=$Lines-9}
}
function Get-LfoConfigurationHint($Entry,[bool]$Session,[int]$Focus=1){
    if($null -eq $Entry){return [pscustomobject]@{Meaning='No settings in this section.';Action='Tab: switch panels.';Impact='';LongHelp=''}}
    $action=if(-not $Entry.Editable){'Read-only; cannot be changed here.'}elseif($Focus -eq 0){'Tab or Right: select the parameter panel.'}else{
        switch($Entry.Kind){
            'enum' {'Left/Right or Enter: cycle '+($Entry.Choices -join ' / ')}
            'bool' {'Space, Left/Right or Enter: toggle ON/OFF.'}
            'int' {'Enter: type a whole number; blank cancels.'}
            'number' {'Enter: type a decimal number (use a decimal point).'}
            default{'Enter: edit value.'}
        }
    }
    $impact=if(-not $Entry.Editable){'Managed by bootstrap or repository; displayed for information.'}elseif($Session -and $Entry.Apply -eq 'Live'){'F10 applies to this session; F2 also saves the persistent default.'}elseif($Entry.Apply -eq 'Live'){'F2 saves the default for subsequent LFO launches.'}else{'F2 saves; relaunch LFO to apply. Current session is unchanged.'}
    [pscustomobject]@{Meaning=$Entry.Description;Action=$action;Impact=$impact;LongHelp=$Entry.LongHelp}
}
function Split-LfoConfigurationHelpText([string]$Text,[int]$Width){
    if($Width -lt 1){throw 'Invalid help width.'}
    $remaining=$Text.Trim()
    while($remaining.Length -gt $Width){
        $cut=$remaining.LastIndexOf(' ',$Width)
        if($cut -le 0){$cut=$Width}
        $remaining.Substring(0,$cut).TrimEnd()
        $remaining=$remaining.Substring($cut).TrimStart()
    }
    if($remaining){$remaining}
}
function Show-LfoConfigurationTui {
    param($Registry,[hashtable]$Values,[string]$Path,[string]$Section='Epistemic',[switch]$Session,[switch]$Ascii)
    $work=@{};foreach($id in $Values.Keys){$work[$id]=$Values[$id]}
    $sections=@('Models','Inference','Routing','Epistemic','Memory','Hardware','Interface','Research','Services')
    $icons=@(0xf1b2,0xf0eb,0xf074,0xf05b,0xf1c0,0xf2db,0xf108,0xf0c3,0xf085)
    $si=[array]::IndexOf($sections,$Section);if($si -lt 0){$si=0}
    $ri=0;$offset=0;$focus=0;$status='Tab: panels | Enter: edit | arrows: navigate/change'
    $esc=[string][char]27
    $useAnsi=(-not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected)
    function Label($value){if($value -is [bool]){if($value){return 'ON'}else{return 'OFF'}};return [string]$value}
    function Fit([string]$s,[int]$w){$s=[regex]::Replace($s,'[\x00-\x1f\x7f]','?');if($s.Length -gt $w){$s=$s.Substring(0,$w)};return $s.PadRight($w)}
    function UpdateValue($entry,[int]$direction){
        if(-not $entry.Editable){return 'Managed setting; read-only.'}
        $old=Get-LfoConfigurationValue $Registry $work $entry.Id
        if($entry.Kind -eq 'bool'){$work[$entry.Id]=-not $old;return 'Changed (not saved).'}
        if($entry.Kind -eq 'enum'){
            $i=[array]::IndexOf($entry.Choices,$old)
            $work[$entry.Id]=$entry.Choices[($i+$direction+$entry.Choices.Count)%$entry.Choices.Count]
            return 'Changed (not saved).'
        }
        return 'Press Enter to edit numeric values.'
    }
    function EditValue($entry){
        if(-not $entry.Editable){return 'Managed setting; read-only.'}
        if($entry.Kind -in @('enum','bool')){return (UpdateValue $entry 1)}
        $old=Get-LfoConfigurationValue $Registry $work $entry.Id
        $inputValue=Read-Host ('New value (current '+$old+'; blank cancels)')
        if($inputValue -eq ''){return 'Cancelled.'}
        try{$work[$entry.Id]=ConvertTo-LfoConfigurationValue $entry $inputValue;return 'Changed (not saved).'}catch{return $_.Exception.Message}
    }
    function ShowContextHelp($entry){
        if($null -eq $entry){return}
        $h=Get-LfoConfigurationHint $entry ([bool]$Session) 1
        $lines=@(
            $entry.Id
            ''
            $h.Meaning
            ''
            $h.LongHelp
            ''
            ('Default: '+(Label $entry.Default))
            ('Current: '+(Label (Get-LfoConfigurationValue $Registry $work $entry.Id)))
            $h.Action
            $h.Impact
            ''
            'Tab: switch panels. F2 saves persistent settings. F5 manages profiles.'
            'F10 exits (applies live changes in chat). Esc discards unsaved edits.'
            'F4 toggles Nerd Font / ASCII.'
        )
        $page=0
        while($true){
            $w=[Math]::Max(20,[Console]::WindowWidth-3)
            $hgt=[Math]::Max(5,[Console]::WindowHeight-3)
            $wrapped=@(foreach($line in $lines){if($line -eq ''){''}else{Split-LfoConfigurationHelpText $line $w}})
            $maxPage=[Math]::Max(0,[Math]::Ceiling($wrapped.Count/$hgt)-1)
            $page=[Math]::Min($page,$maxPage)
            [Console]::Write($esc+'[37;44m'+$esc+'[2J'+$esc+'[H')
            [Console]::WriteLine($esc+'[30;46m'+(Fit ' LFO-CONFIG | CONTEXT HELP' $w)+$esc+'[37;44m')
            for($j=0;$j -lt $hgt;$j++){
                $idx=$page*$hgt+$j
                $line=if($idx -lt $wrapped.Count){$wrapped[$idx]}else{''}
                [Console]::WriteLine((Fit $line $w))
            }
            [Console]::Write($esc+'[34;47m'+(Fit (' Up/Down: page | Esc/Enter/F1: back | '+($page+1)+'/'+($maxPage+1)) $w)+$esc+'[0m')
            $key=[Console]::ReadKey($true).Key
            if($key -in @('Escape','Enter','F1','F10')){break}
            if($key -in @('DownArrow','PageDown')){$page=[Math]::Min($maxPage,$page+1)}
            if($key -in @('UpArrow','PageUp')){$page=[Math]::Max(0,$page-1)}
        }
        [Console]::Write($esc+'[37;44m'+$esc+'[2J'+$esc+'[H')
    }
    function DoSave {
        try{Save-LfoConfiguration $Registry $work $Path;return 'Saved persistent settings.'}catch{return ('Save failed: '+$_.Exception.Message)}
    }
    function DoValidate {
        try{Assert-LfoConfiguration $Registry $work;return 'Configuration valid (static checks only).'}catch{return ('Invalid: '+$_.Exception.Message)}
    }
    function ProfileAction {
        $action=Read-Host 'Profile: save or load (s/l; blank cancels)'
        if($action -notin @('s','l')){return 'Cancelled.'}
        $name=Read-Host 'Profile name (letters, digits, hyphen, underscore)'
        if($name -cnotmatch '^[A-Za-z0-9_-]{1,60}$'){return 'Invalid profile name.'}
        $profilePath=Join-Path (Join-Path (Split-Path -Parent $Path) 'profiles') ($name+'.json')
        try{
            if($action -eq 's'){
                if((Test-Path -LiteralPath $profilePath) -and (Read-Host 'Overwrite profile? y/N') -ne 'y'){return 'Cancelled.'}
                Save-LfoConfiguration $Registry $work $profilePath
                return ('Saved profile '+$name)
            }
            if(-not (Test-Path -LiteralPath $profilePath -PathType Leaf)){return 'Profile not found.'}
            $new=Read-LfoConfiguration $Registry $profilePath
            Assert-LfoConfiguration $Registry $new
            $work.Clear();foreach($id in $new.Keys){$work[$id]=$new[$id]}
            return ('Loaded '+$name+' (F2 saves as default).')
        }catch{return $_.Exception.Message}
    }
    if($useAnsi){
        $oldEncoding=$null
        try{
            $oldEncoding=[Console]::OutputEncoding
            [Console]::OutputEncoding=New-Object Text.UTF8Encoding($false)
            [Console]::Write($esc+'[?1049h'+$esc+'[?25l')
            $lastWidth=0;$lastHeight=0;$canPoll=$true
            while($true){
                $view=Get-LfoConfigurationViewport ([Console]::WindowWidth) ([Console]::WindowHeight)
                $width=$view.Width;$height=$view.Height
                $items=@($Registry.Values|Where-Object Section -eq $sections[$si])
                if($ri -ge $items.Count){$ri=[Math]::Max(0,$items.Count-1)}
                $rows=$view.Rows
                if($ri -lt $offset){$offset=$ri};if($ri -ge $offset+$rows){$offset=$ri-$rows+1}
                $left=$view.Left;$right=$view.Right
                $blue=$esc+'[37;44m';$cyan=$esc+'[30;46m';$yellow=$esc+'[93;44m';$grey=$esc+'[34;47m'
                $rule=if($Ascii){'-'}else{[string][char]0x2500}
                $sb=New-Object Text.StringBuilder
                if($width -ne $lastWidth -or $height -ne $lastHeight){
                    [void]$sb.Append($blue+$esc+'[2J')
                    $lastWidth=$width;$lastHeight=$height
                }
                [void]$sb.Append($esc+'[H'+$blue+(Fit ' LFO-CONFIG  |  Configuration Manager  |  v9.7-dev' $width)+$esc+'[K')
                [void]$sb.Append([Environment]::NewLine+$cyan+(Fit (' '+$sections[$si]+'  |  '+$(if($Session){'session + persistent'}else{'persistent settings'})) $width)+$esc+'[K'+$blue)
                [void]$sb.Append([Environment]::NewLine+(Fit ($rule*$width) $width)+$esc+'[K')
                for($i=0;$i -lt $rows;$i++){
                    $leftText=''
                    if($i -lt $sections.Count){$glyph=if($Ascii){'>'}else{[string][char]$icons[$i]};$leftText=' '+$glyph+' '+$sections[$i]}
                    $lc=if($i -eq $si){$cyan}else{$blue}
                    [void]$sb.Append([Environment]::NewLine+$lc+(Fit $leftText $left)+$blue+' | ')
                    $index=$i+$offset
                    if($index -lt $items.Count){
                        $item=$items[$index];$v=Label (Get-LfoConfigurationValue $Registry $work $item.Id)
                        $key=($item.Id -replace '^(Chat\.|Epistemic\.|Session\.|Runtime\.|Services\.|Models\.)','')
                        $suffix=if($item.Editable){' ['+$item.Apply+']'}else{' [RO]'}
                        $rowText=Fit ($key+' = '+$v+$suffix) $right
                        $rc=if($focus -eq 1 -and $index -eq $ri){$cyan}else{$blue}
                        [void]$sb.Append($rc+$rowText+$blue)
                    }else{[void]$sb.Append(' '*$right)}
                    [void]$sb.Append($esc+'[K')
                }
                $entry=if($items.Count){$items[$ri]}else{$null}
                $hint=Get-LfoConfigurationHint $entry ([bool]$Session) $focus
                $mark=if($Ascii){'i'}else{[string][char]0xf05a}
                [void]$sb.Append([Environment]::NewLine+$blue+(Fit ($rule*$width) $width)+$esc+'[K')
                [void]$sb.Append([Environment]::NewLine+$yellow+(Fit (' '+$mark+' '+$hint.Meaning) $width)+$esc+'[K')
                [void]$sb.Append([Environment]::NewLine+$blue+(Fit (' Action: '+$hint.Action) $width)+$esc+'[K')
                [void]$sb.Append([Environment]::NewLine+$blue+(Fit (' Effect: '+$hint.Impact) $width)+$esc+'[K')
                [void]$sb.Append([Environment]::NewLine+$blue+(Fit (' '+$status) $width)+$esc+'[K')
                [void]$sb.Append([Environment]::NewLine+$grey+(Fit ' F1 Help  F2 Save  F4 Font  F5 Profiles  F9 Validate  F10 Exit' $width)+$esc+'[K'+$esc+'[0m')
                [Console]::Write($sb.ToString())
                # Resize while idle when the console exposes nonblocking key polling.
                if($canPoll){
                    $resized=$false
                    try{
                        while(-not [Console]::KeyAvailable){
                            if([Console]::WindowWidth -ne ($width+1) -or [Console]::WindowHeight -ne $height){$resized=$true;break}
                            Start-Sleep -Milliseconds 100
                        }
                    }catch{$canPoll=$false}
                    if($resized){continue}
                }
                $k=[Console]::ReadKey($true).Key
                switch($k){
                    'Tab' {$focus=1-$focus}
                    'UpArrow' {if($focus -eq 0){$si=($si+$sections.Count-1)%$sections.Count;$ri=0;$offset=0}else{$ri=[Math]::Max(0,$ri-1)}}
                    'DownArrow' {if($focus -eq 0){$si=($si+1)%$sections.Count;$ri=0;$offset=0}else{$ri=[Math]::Min([Math]::Max(0,$items.Count-1),$ri+1)}}
                    'LeftArrow' {if($focus -eq 1 -and $items.Count){$status=UpdateValue $items[$ri] -1}}
                    'RightArrow' {if($focus -eq 1 -and $items.Count){$status=UpdateValue $items[$ri] 1}else{$focus=1}}
                    'Spacebar' {if($focus -eq 1 -and $items.Count){$status=UpdateValue $items[$ri] 1}}
                    'Enter' {if($focus -eq 0){$focus=1}else{if($items.Count){[Console]::Write($esc+'[?25h'+$esc+'[0m'+$esc+'[2J'+$esc+'[H');$status=EditValue $items[$ri];[Console]::Write($esc+'[?25l')}}}
                    'F1' {if($items.Count){ShowContextHelp $items[$ri]}}
                    'F2' {$status=DoSave}
                    'F4' {$Ascii=-not $Ascii;$status=if($Ascii){'ASCII symbols'}else{'Nerd Font symbols (requires client font)'}}
                    'F5' {[Console]::Write($esc+'[?25h'+$esc+'[0m'+$esc+'[2J'+$esc+'[H');$status=ProfileAction;[Console]::Write($esc+'[?25l')}
                    'F9' {$status=DoValidate}
                    'Escape' {return $null}
                    'F10' {if($Session){try{Assert-LfoConfiguration $Registry $work;return $work}catch{$status=$_.Exception.Message}}else{return $null}}
                }
            }
        }catch{Write-Host 'Full-screen console unavailable; switching to line mode.'}
        finally{
            try{[Console]::Write($esc+'[0m'+$esc+'[?25h'+$esc+'[?1049l')}finally{
                if($null -ne $oldEncoding){[Console]::OutputEncoding=$oldEncoding}
            }
        }
    }
    while($true){
        Write-Host ('LFO-CONFIG | '+$sections[$si]+' | '+$status)
        $items=@($Registry.Values|Where-Object Section -eq $sections[$si])
        for($i=0;$i -lt $items.Count;$i++){Write-Host ('{0,2} {1} = {2} [{3}]' -f ($i+1),$items[$i].Id,(Label (Get-LfoConfigurationValue $Registry $work $items[$i].Id)),$items[$i].Apply)}
        Write-Host 'n/p section | number edit | h<number> help | s save | f profiles | v validate | q exit | x cancel'
        $choice=Read-Host 'Select'
        if($null -eq $choice -or $choice -eq 'x'){return $null}
        if($choice -eq 'q'){if($Session){try{Assert-LfoConfiguration $Registry $work;return $work}catch{$status=$_.Exception.Message;continue}};return $null}
        switch($choice){
            'n'{$si=($si+1)%$sections.Count}
            'p'{$si=($si+$sections.Count-1)%$sections.Count}
            's'{$status=DoSave}
            'f'{$status=ProfileAction}
            'v'{$status=DoValidate}
            default{
                if($choice -match '^h([0-9]+)$'){
                    $idx=[int]$Matches[1]
                    if($idx -ge 1 -and $idx -le $items.Count){
                        $h=Get-LfoConfigurationHint $items[$idx-1] ([bool]$Session) 1
                        Write-Host $h.Meaning;Write-Host $h.LongHelp;Write-Host $h.Action;Write-Host $h.Impact
                        $null=Read-Host 'Enter to return'
                    }
                }else{$idx=0;if([int]::TryParse($choice,[ref]$idx) -and $idx -ge 1 -and $idx -le $items.Count){$status=EditValue $items[$idx-1]}}
            }
        }
    }
}
