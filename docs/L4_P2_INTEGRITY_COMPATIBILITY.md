# P2 integrity compatibility v1

The P2 map accepted by the original experiment has 19 CRLF line endings and
one final LF. Its SHA-256 is
`312f05eb128d59c83bc61558610df7e9320184e0a64b5476845ae123cc56c456`, matching
the historical lock and recorded offline/live evidence. Git normalized that
artifact to LF. The committed map has SHA-256
`15611e74cc1c038fd1ae827b51504dd948345b7b2fdb58fd6ec9e1c9e44b9c8e` and Git
blob `aa380c1dbd0e294512dd2c7968ad2c0e34fe339c`. An ordinary CRLF checkout has
SHA-256 `0e01512620f25c8174131940c7ce854ec3f661238261a76911d75951b1a6a4b2`.

The original runtime hashed the checkout bytes directly and rejected either
normal Git representation. The preserved accepted artifact was recovered and
verified against its historical hash; its decoded map matches the frozen map.
The defect is serialization portability, with no changed intervention text.

## Versioned repair

`config/L4P2Integrity.compatibility-v1.json` binds the immutable tag
`v9.6-l4-p2-frozen`, commit `e648bba1201db639244b120b5f5db74e0c6f4059`,
map blob, canonical SHA-256, historical SHA-256 and serialization rules.

The repaired adapter decodes strict UTF-8, accepts an optional UTF-8 BOM and
normalizes CRLF to LF. It checks the exact canonical SHA-256 and computes the
Git blob identity. It then reconstructs the accepted mixed-EOL bytes and
requires their hash to equal both the compatibility contract and the unchanged
pre-acceptance lock. It also checks map/lock/contract versions. It parses the
same verified text used for hashing, avoiding a second map-file read.

No JSON reserialization, whitespace trimming or instruction rewriting is
allowed. A missing final LF or any content edit fails closed. This contract
protects against accidental corruption and incompatible packaging; it is not
a signature against an attacker who can replace trusted code and configuration.

The existing `InterventionMapSha256` output continues to identify the exact
historical accepted artifact, whose bytes are now explicitly reconstructed
and verified. Additional fields make the identities distinct:

- `InterventionMapFileSha256`: actual supplied file bytes;
- `InterventionMapCanonicalSha256`: normalized committed representation;
- `InterventionMapGitBlob`: computed canonical Git blob;
- `InterventionIntegrityContract`: explicit compatibility schema.

The intervention schema and version remain unchanged because all pre-existing
output fields and all instruction strings preserve the frozen behavior.
Consumers that require an exact closed property set must account for these
four additive provenance fields.

## Verification and evidence boundary

Run the unchanged `tests/Test-LfoEpistemicIntervention.ps1` (94 checks), passing
explicit P1 rules and a local P1 compatibility lock as documented in the P2
experiment. The frozen P1 defect and tag remain unchanged.

`tests/Test-LfoEpistemicInterventionIntegrity.ps1` covers LF, CRLF, historical
mixed endings, optional BOM, malformed encoding, map/lock/contract tampering,
version mismatch, default OFF and NO_ACTION request identity. It loads the
frozen adapter separately and compares every original output field across
all five decisions with enablement both OFF and ON, using the recovered
accepted artifact for the old adapter.

All tests are offline, with zero model calls or database writes. The repair
preserves historical frozen maps, locks, fixtures, manifests, documents and
tags. Only current development code, a new compatibility contract and new
regression documentation/tests change. This is an engineering reproducibility
repair, not new intervention-efficacy evidence, deployment authorization,
cross-host model replication or completion of I1.
