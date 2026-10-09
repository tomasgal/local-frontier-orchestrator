@{
    # Common QwenChat defaults. Host-specific GPU/CPU/context placement remains in the Ollama model/runtime profile.
    Model = 'qwen3.5:4b-q4_K_M'
    BaseUri = 'http://127.0.0.1:11434'
    CodexTimeoutSec = 300
    HistoryMaxMessages = 12

    Memory = @{
        Enabled = $true
        DataDirectory = '%LOCALAPPDATA%\LocalFrontierOrchestrator'

        # Shared semantics; host launchers may override capacity parameters.
        RecentTurns = 4
        ContextMaxChars = 600
        RecentContextMaxChars = 6000
        RetrievalMaxChars = 2500
        RetrievalMaxItems = 3
        RetrievalScanMaxTurns = 500

        # v9.3 pressure-triggered compaction: only non-empty, non-duplicate
        # micro-notes fill the pending buffer. Compact when either threshold
        # is reached. Exact data remains authoritative in raw JSONL logs.
        CompactionMaxPendingNotes = 4
        CompactionMaxPendingChars = 108
        NoteMaxChars = 40
        StateMaxChars = 160
        NoteNumPredict = 32
        CompactionNumPredict = 96
        NoteInputUserMaxChars = 800
        NoteInputAssistantMaxChars = 250
        Temperature = 0.05

        # v9.4 L2 structured factual state. L0/L1 remain authoritative for
        # evidence and conversational continuity.
        StructuredEnabled = $true

        # Dev4 read path is opt-in until isolated extraction/semantic validation.
        # Applies only to current L2 facts in this conversation epoch.
        StructuredReadEnabled = $false
        StructuredReadMaxItems = 6
        StructuredReadMaxChars = 800
    }

    ResearchLogging = @{
        Enabled = $true
        IncludeRawText = $true
        IncludeMemorySnapshots = $true
    }

    LocalGeneration = @{
        NumPredictNormal = 1024
        NumPredictThink  = 2048
        Temperature      = 0.10

        # Dev5 candidate A: omit memory_note/memory_ops from the local output
        # schema only when a read-only LOCAL turn received current L2 facts.
        # Opt-in experiment, not a release default. Compare with dev4.
        CompactReadSchemaEnabled = $false

        # Dev5 candidate B: independently opt-in to omit the redundant full
        # L2 WRITE extraction policy on A-eligible read-only LOCAL turns.
        # Requires candidate A; all read/write persistence guards remain.
        LeanReadPolicyEnabled = $false

        # Dev5 candidate C (lower-trust data placement, not a security proof):
        # when A+B already apply, move retrieved L2 records out of the
        # high-priority system text into a separate quoted user-role message,
        # immediately before the actual current user prompt. Opt-in only.
        LowerTrustL2EvidenceEnabled = $false

        # Dev5 experimental mixed question + explicit current-user RAM update.
        # Pure current-turn quote/span parser authorizes at most one typed op;
        # model-generated L2 ops remain guarded. Requires A+B L2 read path.
        # OFF by default until TEMP-only integration and LIVE acceptance.
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
