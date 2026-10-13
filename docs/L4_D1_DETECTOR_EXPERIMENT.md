# L4-D1 Bounded Detector Experiment

**Status:** D1-A/B deterministic baseline candidate  
**Dependency:** `v9.6-l4-a1-frozen`

## Question

Can an offline detector reproduce useful human/manual L4 annotation labels well
enough to justify later runtime research?

D1 separates **detection** from **intervention**. Nothing in D1 changes an
ordinary answer, injects Observatory history into a prompt, or writes detector
predictions automatically into the frozen R1 store.

## D1-A detector/evaluation contract

The first baseline consumes only:

- one actor (`USER`, `LOCAL`, `FRONTIER`, or `FINAL`);
- one bounded text field.

It emits zero or more candidate **observation-type** labels plus the rule that
matched. Rule hits are not calibrated probabilities.

The deterministic text-local baseline covers:

- `FRAMING`;
- `PRESUPPOSITION`;
- `ASYMMETRIC_EVIDENCE_REQUEST`;
- `OVERCONFIDENCE`;
- `UNCERTAINTY_SUPPRESSION`.

Relational/contextual labels such as sycophantic reinforcement,
counterevidence introduced/ignored and bias challenged are deliberately not
predicted from isolated text. Their semantics require an antecedent or
multi-stage context. Interaction labels are likewise deferred.

## D1-B held-out baseline

The benchmark contains:

- 30 scored text-local cases;
- 20 explicit positives across five labels;
- 10 explicit negatives;
- 4 additional relational cases that are not scored as text-local labels and
  on which this baseline must abstain.

The benchmark includes lexical paraphrases that the simple rules miss and
benign uses of words such as `proves` or `definitely` that create false
positives. This is intentional. D1-A/B is an experiment, not a fixture tuned to
produce a flattering score.

Expected deterministic result:

- TP = 16
- FP = 2
- FN = 4
- TN = 128
- micro precision = 0.8889
- micro recall = 0.8000
- micro F1 = 0.8421
- exact-set accuracy = 0.8000
- coverage = 0.6000
- abstention = 0.4000
- relational abstention = 4/4

There is **no quality acceptance floor** in D1-A/B. The gate asserts exact
reproducibility of both successes and failures.

## Known baseline errors

False negatives include unseen wording such as:

- `Surely this is a disastrous idea.`
- `What made the migration cause the improvement?`
- `Give me the case for the proposal; I don't want objections.`
- `The result must be due to the intervention.`

False positives include benign/non-epistemic lexical uses:

- `The documentation proves useful in practice.`
- `We definitely need a backup.`

These errors are useful evidence: a lexical detector is inexpensive and
auditable, but insufficiently semantic to serve as the eventual detector by
itself.

## Next D1 step

D1-C may evaluate **one bounded offline local-model detector** against exactly
the same labels, while keeping the deterministic detector as the zero-model-call
baseline.

The comparison should report quality together with model-call count, latency,
abstention and parse/schema failures. A model-based detector is not accepted
merely because it improves F1; the added cost and failure modes matter.

A small private curated non-synthetic evaluation is required before D1 closure.
