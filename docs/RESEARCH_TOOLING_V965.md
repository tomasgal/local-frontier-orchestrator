# v9.6.5 research experiment tooling

v9.6.5 adds a small provider-neutral, offline research layer motivated by pilot work on frozen-response Human–AI experiments. It does **not** change L0–L4 semantics, enable P1/P2 in normal chat or call a model by itself.

## Mediator parameter sweep

Use `schema/research/mediator-parameter-sweep.schema.json` and `experiments/research/mediator-parameter-sweep.example.json`.

~~~powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\research\Invoke-LfoResearchTooling.ps1 -Mode ExpandParameterSweep -InputPath .\experiments\research\mediator-parameter-sweep.example.json
~~~

The JSONL output has stable configuration IDs. Candidate parameters are for development/pilot work; the chosen configuration must be justified and frozen before confirmatory collection.

## Frozen-response / replay bank

Use `schema/research/replay-bank.schema.json` and `experiments/research/replay-bank.example.json`.

~~~powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\research\Invoke-LfoResearchTooling.ps1 -Mode ValidateReplayBank -InputPath .\experiments\research\replay-bank.example.json
~~~

The schema separates `correct`, `natural-error` and `controlled-misleading` advice. `mechanismEvidence` is separate, so an error occurring in both neutral and leading prompts can be retained without being mislabeled as sycophancy.

## Paired model audit

Use `schema/research/model-audit.schema.json` and `experiments/research/model-audit.example.json`.

~~~powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\research\Invoke-LfoResearchTooling.ps1 -Mode BuildModelAuditManifest -InputPath .\experiments\research\model-audit.example.json
~~~

Populate `observedAnswer`, `rawResponse`, provider/model metadata and capture time using the chosen collection workflow, then analyze the completed JSONL with `-Mode AnalyzeModelAudit`.

The descriptive labels are bookkeeping categories, not psychological diagnoses and not a substitute for inferential analysis.

## Boundary

The helper is offline and provider-neutral. It contains no credentials, provider-specific API logic or participant data and never touches production LFO memory.
