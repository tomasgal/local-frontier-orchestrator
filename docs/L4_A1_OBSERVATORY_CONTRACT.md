# L4-A1 Observatory Analytics Contract

**Status:** A1-A candidate  
**Dependency:** `v9.6-l4-r2-frozen`  
**Scope:** explicit, read-only Observatory analytics over stored L4 observations.

A1 does not reopen R1 or R2. It defines the smallest analytic surface worth
implementing before any automatic detector or Balancer work.

## Epistemic boundary

A1 describes **stored annotations**. It does not establish that an annotation is
true, important, prevalent, diagnostic, or causally explanatory.

The analytic unit is an `EpistemicObservation` already accepted by frozen R1/R2.

A1 must never convert repeated annotations into a persistent psychological
profile such as "the user has confirmation bias." The strongest permitted form
is descriptive, for example:

> In source store S, epoch E, turns 20-40, annotation signature X occurred in
> three distinct source turns.

## Chronology

Conversation chronology is:

1. `source.epoch`;
2. `source.turn_id`;
3. stage order from the numeric suffix of `source.stage_id` when a within-turn
   tie-break is needed.

`observed_at` is annotation metadata. It is **not** conversation chronology,
because an observation may be recorded after the source conversation occurred.

A1 does not aggregate across stores or epochs.

## Explicit analytic window

Every Observatory request selects:

- exactly one `source.store_id`;
- exactly one `source.epoch`;
- inclusive `first_turn`;
- inclusive `last_turn`.

Raw excerpts are not returned by default. Aggregate support is bounded to at
most 50 observation IDs/source references per result. Full source text requires
an explicit R1 provenance resolver call.

## A1-Q1 — Window summary

Question:

> What annotations are present in this explicit turn window?

Return observation count, distinct annotated-turn count, and counts by actor,
stage, observation type and interaction.

## A1-Q2 — Linked response transitions

Question:

> For directly linked annotations, how does a later/response annotation relate
> to its explicitly referenced antecedent?

R1 stores `related_observation_id` on the current observation. A1 gives that
link the semantic direction:

`related/parent observation -> current/child observation`

This differs from the string orientation used by the frozen R2-C engineering
helper (`child->parent`). R2 remains frozen; A1 defines the semantic Observatory
direction without rewriting it.

Only links whose parent and child both lie inside the selected window count
toward the transition aggregate. Cross-boundary links are reported separately
as `excluded_boundary_links`.

## A1-Q3 — Recurrence

Question:

> Which explicit annotation structures repeat across distinct source turns in
> this window?

A1 recurrence requires at least **two distinct source turn IDs**.

Initial signatures:

1. `actor | observation_type`
2. `parent_actor -> child_actor | child_interaction`

Repeated annotations within only one source turn are not recurrence.

Recurrence means repeated stored annotation structure. It is not a trait,
diagnosis, user model, or prediction.

## A1-Q4 — Window comparison

Question:

> How do two explicit non-overlapping windows in the same store and epoch
> differ descriptively?

Return deltas for observation-type counts, interaction counts and distinct-turn
counts for recurrence signatures.

A1 does not label a delta as improvement, deterioration, trend, prevalence
change, causal effect, or intervention effect.

## A1-Q5 — Provenance drill-back

Every aggregate must be auditable.

Bounded support references may contain only observation ID, source store ID,
relative L0 file, epoch, turn ID, stage ID and exact source-content SHA256.

Raw source text is resolved only on an explicit follow-up request through the
frozen R1 resolver. Observatory analytics must not expand raw L4/L0 history
into ordinary prompts automatically.

## Non-goals

A1 does **not** add automatic annotation/detector calls, inter-rater scoring,
detector accuracy/calibration, cross-user/store profiling, cross-epoch identity
assumptions, policy capsules, response intervention, ordinary prompt injection,
graph/vector dependencies, plugins, or mandatory LLM calls.

## A1 execution sequence

### A1-A — analytic contract

Freeze the questions, chronology, windows, result semantics and guardrails in
this document plus `config/L4A1Observatory.contract.json`.

### A1-B — implementation + deterministic gate

Implement read-only Q1-Q5 over frozen R1/R2 and validate exact expected results
on deterministic fixtures, including pagination, window-boundary links and
provenance drill-back.

### A1-C — evidence + closure

Use the deterministic fixture and then a small explicitly curated
non-synthetic corpus to determine whether these questions are practically
useful. Private source text remains local by default; public evidence should
contain only approved or aggregate material.

Only after A1 closure decide whether the next versioned milestone is a bounded
automatic-detector experiment or further Observatory work.
