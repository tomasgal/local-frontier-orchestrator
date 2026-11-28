@{
    SchemaVersion = 1
    DefaultProfile = 'COMPACT_CPU'
    # Scheduling is independent of semantic profile and device placement.
    # Portable conservative default; MS1 experiments can explicitly enable parallelism.
    Execution = @{
        Parallelism = $false
        Topology = 'AUTO'
        EdgeDeviceId = ''
        MainDeviceId = ''
    }
    # Model roles are independent of placement, scheduling and semantic profile.
    # Empty frontier binding means no frontier dispatch by this experimental policy.
    Models = @{
        Main = @{ Adapter = 'OLLAMA_CHAT'; ModelId = 'lfo-qwen3.5-35b-uma16k:latest' }
        Edge = @{ Adapter = 'FLM_SYSTEMONE'; ModelId = 'd3:nano' }
        Frontier = @{ Adapter = ''; ModelId = ''; Enabled = $false }
    }
    Profiles = @{
        COMPACT_CPU = @{ PredicateContract = 'COMPACT'; CpuGate = $true }
        SCOPED_CPU  = @{ PredicateContract = 'SCOPED';  CpuGate = $true }
    }
}
