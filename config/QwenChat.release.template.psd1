@{
    # Generated-install template. Installer replaces __LFO_*__ placeholders.
    Model = '__LFO_MODEL__'
    BaseUri = '__LFO_OLLAMA_BASEURI__'
    CodexTimeoutSec = 300
    HistoryMaxMessages = 12

    Memory = @{
        Enabled = $true
        # Complete-build provenance: capture stage identity/content references in L0.
        L0StageSourcesEnabled = $true
        DataDirectory = '__LFO_DATA_DIRECTORY__'

        RecentTurns = 4
        ContextMaxChars = 600
        RecentContextMaxChars = 6000
        RetrievalMaxChars = 2500
        RetrievalMaxItems = 3
        RetrievalScanMaxTurns = 500

        CompactionMaxPendingNotes = 4
        CompactionMaxPendingChars = 108
        NoteMaxChars = 40
        StateMaxChars = 160
        NoteNumPredict = 32
        CompactionNumPredict = 96
        NoteInputUserMaxChars = 800
        NoteInputAssistantMaxChars = 250
        Temperature = 0.05

        StructuredEnabled = $true
        StructuredReadEnabled = $true
        StructuredReadMaxItems = 6
        StructuredReadMaxChars = 800

        # Frozen L3 remains reconstructible; the complete-build profile opts in
        # to its accepted read/index path. Unknown queries still fail open.
        L3ReadEnabled = $true
        L3ReadMaxItems = 3
        L3ReadMaxChars = 1200
        L3IndexEnabled = $true
        L3TopicRules = @()
    }

    ResearchLogging = @{
        Enabled = $true
        IncludeRawText = $true
        IncludeMemorySnapshots = $true
    }

    # L4 runtime infrastructure is enabled for provenance/store access, while
    # policy/intervention remains explicitly default-OFF. No D1 detector hook.
    Epistemic = @{
        Enabled = $true
        Endpoint = '__LFO_L4_ENDPOINT__'
        CredentialPath = '__LFO_L4_CREDENTIAL__'
        RecordRuntimeStatus = $true
        PolicyEnabled = $false
        InterventionEnabled = $false
        WindowTurns = 8
    }

    LocalGeneration = @{
        NumPredictNormal = 1024
        NumPredictThink  = 2048
        Temperature      = 0.10
        CompactReadSchemaEnabled = $false
        LeanReadPolicyEnabled = $false
        LowerTrustL2EvidenceEnabled = $false
        MixedUserEvidenceWriteEnabled = $false
    }

    SynthesisGeneration = @{
        NumPredictNormal = 1536
        NumPredictThink  = 3072
        Temperature      = 0.25
        PresencePenalty  = 0.15
        UnfinishedEvalThreshold = 1500
    }

    Frontier = @{
        MaxPromptChars = 12000
    }

    HardGates = @{
        ProductSpecPattern     = '(?i)(\bpresn\p{L}*\b|\bexact(?:ly)?\b|\bšpecifikáci\p{L}*\b|\bspecification\p{L}*\b|\bspecs?\b|\brozmer\p{L}*\b|\bdimensions?\b|\bpríkon\p{L}*\b|\bpower\s+(?:draw|consumption|limit)\b|\bTBP\b|\bTDP\b|\bnapájac\p{L}*\s+konektor\p{L}*\b|\bpower\s+connector\p{L}*\b|\bhmotnos\p{L}*\b|\bweight\b)'
        ProductIdentityPattern = '(?i)(\b(?:ASRock|NVIDIA|AMD|Intel|ASUS|MSI|Gigabyte|Lenovo|Dell|HP|Acer|Apple|Samsung|Sony|Canon|Nikon|Corsair|Crucial|Kingston|Western\s+Digital|WD|Seagate|Sapphire|PowerColor|XFX|PNY|Zotac|Palit|Gainward)\b|\b(?:RTX|GTX|RX|Arc|Ryzen|Core|GeForce|Radeon|iPhone|Galaxy|ThinkPad)\b|\b[A-Z]{1,6}\d{2,5}[A-Z0-9._+-]*\b)'
        Rules = @(
            @{ Reason = 'explicit-frontier-or-web'; Pattern = '(?i)(\bask[_ -]?codex\b|\bdopyt\p{L}*\s+na\s+frontier\b|\bpouži\p{L}*[^.!?]{0,60}\bfrontier\b|\bopýtaj\p{L}*[^.!?]{0,40}\bcodex\b|\buse\s+(?:the\s+)?(?:frontier|codex)\b|\bask\s+(?:the\s+)?(?:frontier|codex)\b|\bsearch the web\b|\bbrowse the web\b|\blook it up online\b|\bna webe\b|\bcez web\b|\bna internete\b|\bonline zdroj\p{L}*\b|\bvyhľadaj\p{L}*\s+(?:na\s+)?webe\b|\bzisti\p{L}*\s+(?:na\s+)?webe\b)' }
            @{ Reason = 'explicit-freshness'; Pattern = '(?i)(\bdnes\b|\bvčera\b|\bzajtra\b|\bpráve teraz\b|\btento týždeň\b|\btento mesiac\b|\bnajnovš\p{L}*\b|\bnajčerstv\p{L}*\b|\blatest\b|\bnewest\b|\btoday\b|\byesterday\b|\btomorrow\b|\bthis week\b|\bthis month\b|\bas of\b|\bup[- ]to[- ]date\b)' }
            @{ Reason = 'live-state'; Pattern = '(?i)(\bčo sa (?:práve |teraz |aktuálne )?deje\b|\bwhat(?:''s| is) happening\b|\bpočasie\b|\bpredpoveď počasia\b|\bweather\b|\bforecast\b|\blive score\b|\bvýsledok zápasu\b|\bexchange rate\b)' }
            @{ Reason = 'current-version-or-release'; Pattern = '(?i)(\baktuáln\p{L}*\s+(?:stabiln\p{L}*\s+)?verzi\p{L}*\b|\baktuáln\p{L}*\s+release\b|\bcurrent\s+(?:stable\s+)?version\b|\bcurrent\s+release\b|\bnovš\p{L}*\s+verzi\p{L}*\b)' }
            @{ Reason = 'url-needs-fetch'; Pattern = '(?i)https?://' }
        )
        FollowUpPattern = '(?i)^\s*(a\s+)?(čo|co|ako|a\s+čo|a\s+co|toto|to|tam|ten|tá|ta|tú|tu|tie|rovnako|oproti tomu|what about|and what|this|that|it|same|there)\b'
        FollowUpMaxPromptChars = 220
        FollowUpContextChars   = 1800
    }
}
