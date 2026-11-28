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
    Profiles = @{
        COMPACT_CPU = @{ PredicateContract = 'COMPACT'; CpuGate = $true }
        SCOPED_CPU  = @{ PredicateContract = 'SCOPED';  CpuGate = $true }
    }
}
