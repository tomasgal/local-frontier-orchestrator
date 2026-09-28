@{
    # Example only. Keep machine-specific values in an untracked local file.
    Model = 'qwen3.5:4b-q4_K_M'

    Ollama = @{
        Host = '127.0.0.1:11434'

        # Optional: set an explicit executable path for a portable Ollama build.
        # Otherwise Start-Ollama.ps1 resolves ollama.exe from PATH.
        Executable = $null

        # Optional local model directory.
        ModelsDirectory = $null

        # Runtime sizing belongs to the host profile, not QwenChat request logic.
        ContextLength   = 32768
        NumParallel     = 1
        MaxLoadedModels = 1
        NoCloud         = $true
    }

    Frontier = @{
        CodexTimeoutSec = 300
        MaxCallsPerTurn = 1
        ReadOnly        = $true
    }

    # Example launcher capacity values. These affect how much persistent/recent
    # context is injected, not what the memory system considers important.
    MemoryCapacity = @{
        ContextLengthHint = 32768
        RecentTurns = 6
        MemoryContextMaxChars = 12000
        RecentContextMaxChars = 12000
    }
}
