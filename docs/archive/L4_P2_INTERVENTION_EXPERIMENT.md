# L4-P2 Bounded Intervention Experiment

P2 tests whether the frozen P1 recommendation surface can change a local model's
response in a bounded, default-OFF experiment without merging policy with
detection or Observatory analytics.

## Frozen P1 dependency

P2 depends on `v9.6-l4-p1-frozen` / `28c0ba622761b03af445a8e08939b38396926e0c` and verifies the exact frozen rules
Git blob `e29a1d5f346786e3e2afbf70e3f14b898fcf29ee`.

A material portability defect was discovered before P2 acceptance or model
calls: P1 declares rules SHA-256 `d837c9b6d62e387c6482b83449495d5dc5c4d2092976ef459892bceabe2ee7c3`, while the committed
canonical rules content has SHA-256 `a5da19563afcb4ac9698acce7aff423daf9b3e400cfe5af40f3a46aea4fe0106`. P2 does not
modify the frozen tag. Its experiment harness verified the exact tag/commit/blob
and used a temporary compatibility lock outside the repository solely to execute
the unchanged frozen P1 policy code.

## Architecture

`
synthetic bounded P1 evidence
  -> exact frozen P1 Policy Capsule
  -> frozen P2 intervention adapter
  -> paired CONTROL / INTERVENTION local-model request
  -> predeclared exact-choice scoring
`

Within an active pair, user prompt, model, seed and generation settings are
identical. Only the frozen intervention instruction differs. Pair order
alternates AB/BA. NO_ACTION adds no instruction and its request construction is
identical.

P2 is offline/default-OFF: no detector call, R1 write, production-memory write
or persistent user profiling.