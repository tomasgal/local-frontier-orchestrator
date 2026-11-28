@{
    SchemaVersion = 1
    DefaultProfile = 'COMPACT_CPU'
    Profiles = @{
        COMPACT_CPU = @{ PredicateContract = 'COMPACT'; CpuGate = $true }
        SCOPED_CPU  = @{ PredicateContract = 'SCOPED';  CpuGate = $true }
    }
}
