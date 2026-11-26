# Turn-level runtime provenance. No inference, storage migration or tool calls.
# This describes external operations in one historical turn, not the truth
# of its assertions or the verification status of any individual L2 fact.
function Get-LfoExternalEvidenceStatus($Row){
    $status=[string]$Row.external_evidence_status
    if($status -cin @('NONE','REQUESTED','OBSERVED','UNKNOWN')){return $status}
    return 'UNKNOWN'
}

function Get-LfoHistoricalTurnLabel($Row){
    $route=[string]$Row.route
    if($route -cnotin @('LOCAL','FRONTIER')){$route='UNKNOWN'}
    return ('[route={0}; external_evidence={1}]' -f $route,(Get-LfoExternalEvidenceStatus $Row))
}


# Reserved wrapper annotation. Keep the delivered text intact for audit/export.
function Get-LfoNoLookupAnnotation {
    return '[LFO: No external lookup was performed in this turn. Current facts and cited sources have not been independently reverified.]'
}

# Strip only exact, terminal, standalone annotation paragraphs outside fenced
# code. Older logs do not distinguish model-generated and wrapper text.
function Remove-LfoNoLookupAnnotation([AllowEmptyString()][string]$Text){
    $pattern='(?:\A|\r?\n[ \t]*\r?\n)'+[regex]::Escape((Get-LfoNoLookupAnnotation))+'[ \t]*(?:\r?\n[ \t]*)*\z'
    while($Text){
        $m=[regex]::Match($Text,$pattern)
        if(-not $m.Success){break}
        $prefix=$Text.Substring(0,$m.Index)
        $fence='';$fenceLength=0
        foreach($line in ($prefix -split '\r?\n')){
            if($line -match '^\s*(\x60{3,}|~{3,})(.*)$'){
                $marker=$Matches[1];$rest=$Matches[2].Trim()
                if(-not $fence){$fence=$marker.Substring(0,1);$fenceLength=$marker.Length}
                elseif($marker.Substring(0,1) -eq $fence -and $marker.Length -ge $fenceLength -and -not $rest){$fence='';$fenceLength=0}
            }
        }
        if($fence){break}
        $Text=$prefix
    }
    return $Text
}

function Get-LfoHistoricalAssistantText($Row){
    $answer=[string]$Row.assistant
    $hasMetadata=if($Row -is [System.Collections.IDictionary]){$Row.Contains('runtime_annotation')}else{$null -ne $Row.PSObject.Properties['runtime_annotation']}
    if($hasMetadata){
        if([string]$Row.runtime_annotation -ceq (Get-LfoNoLookupAnnotation)){
            # Remove exactly the wrapper-owned suffix, even if a model left
            # an unclosed code fence in the delivered answer.
            $suffix=[Environment]::NewLine+[Environment]::NewLine+(Get-LfoNoLookupAnnotation)
            $pattern='\r?\n\r?\n'+[regex]::Escape((Get-LfoNoLookupAnnotation))+'\z'
            return [regex]::Replace($answer,$pattern,'')
        }
        return $answer
    }
    if([string]$Row.route -eq 'LOCAL'){
        return Remove-LfoNoLookupAnnotation $answer
    }
    return $answer
}

# Hold the reserved standalone line for the definitive render. This avoids
# displaying a model imitation before the wrapper adds its own annotation.
# Literal uses elsewhere remain available at final render.
function Get-LfoAnnotationPreviewLimit([AllowEmptyString()][string]$Text){
    $m=[regex]::Match($Text,('(?m)^'+[regex]::Escape((Get-LfoNoLookupAnnotation))+'[ \t]*\r?$'))
    if($m.Success){return $m.Index}
    return $Text.Length
}
