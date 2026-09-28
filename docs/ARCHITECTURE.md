# Architecture

## 1. Purpose

Local Frontier Orchestrator is a research-oriented local-first AI gateway. It separates three concerns that are often collapsed into one model call:

1. **conversation and local execution**;
2. **routing / escalation policy**;
3. **frontier research or stronger reasoning**.

The current reference implementation uses a small Qwen model through Ollama for the local layer and native Codex CLI for frontier escalation.

## 2. Primary Qwen-first flow

```text
user request
    |
    v
hard capability / freshness policy
    |
    +-- forced FRONTIER ------------------------------+
    |                                                 |
    v                                                 |
local Qwen route decision                             |
    |                                                 |
    +-- LOCAL -> answer ------------------------------+
    |
    +-- FRONTIER
           |
           v
     bounded ask_codex
           |
           v
   codex exec (read-only)
           |
           v
  frontier result / web research
           |
           v
 Qwen final synthesis / critique
           |
           v
          user
```

### Why keep Qwen after the frontier call?

Conversation continuity alone does not require rewriting the frontier output, but the research architecture intentionally keeps a local post-processing layer.

The desired behaviour is **creative but anchored**:

- concrete researched facts, numbers, identifiers, dates, dimensions, prices, caveats, and source links should not be silently replaced by model memory;
- Qwen may reorganize and explain the result;
- Qwen may identify a conflict or uncertainty;
- Qwen may add stable background knowledge or interpretation when clearly distinguishable from the researched evidence;
- the local layer may later implement bias-aware critique and metacognitive interventions.

This creates a useful boundary:

```text
frontier evidence -> sticky provenance
local layer       -> interpretation, critique, presentation, policy
```

The distinction is a behavioural target, not a formal guarantee. It must be evaluated empirically over long-term use.

## 3. Routing

The MVP combines two mechanisms.

### Deterministic hard gates

Some task classes should not depend on a small model's confidence:

- explicit requests to browse/search/use frontier;
- current or recent information;
- live state;
- current software versions/releases;
- URLs that need to be fetched;
- exact specifications of named external products.

These rules are intentionally narrow.

### Model routing

When no hard gate fires, Qwen returns one of:

```text
ROUTE: LOCAL
ROUTE: FRONTIER
```

Malformed routing fails closed to LOCAL rather than silently spending frontier resources.

## 4. Frontier transport

The frontier action is a wrapper around native `codex exec`.

Current constraints:

- read-only sandbox;
- no interactive approval;
- web search available to the frontier;
- prompt via UTF-8 stdin;
- bounded prompt size;
- timeout;
- one frontier call per user turn;
- no generic command execution exposed to Qwen.

This is deliberately not a general tool-use framework yet.

## 5. Runtime profiles

The orchestration layer should not hard-code a single machine profile.

Runtime/model profiles own:

- model tag;
- quantization;
- CPU/GPU offload;
- context length;
- thread count;
- model storage;
- accelerator-specific settings.

This supports heterogeneous deployments: a modern GPU host, an older CPU-oriented host, or an edge/SBC accelerator can all present the same orchestration contract.

## 6. Policy and configuration boundary

The Windows reference implementation keeps process-control logic separate from behavioural policy:

```text
src/QwenChat.ps1              orchestration / transport
config/QwenChat.config.psd1  hard gates and generation defaults
policy/orchestrator-system.txt
policy/synthesis-system.txt
policy/frontier-subagent.txt
```

This is intentionally different from host runtime configuration. GPU/CPU placement, context length, thread count, quantization, and model storage remain properties of the selected Ollama runtime/model profile.

A change to language policy or synthesis behaviour should not require editing the Codex process wrapper. Conversely, moving to a weaker or stronger host should not require rewriting routing logic.

Avoid using a single surprising answer as a reason to retune the sampler or routing policy. The system is stochastic; changes should be driven by repeated, categorized failures or explicit experimental conditions.

## 7. Context, persistent memory, and logs

QwenChat v9 treats terminal restarts as continuation of one ongoing conversation. `/exit` ends the process but preserves memory. `/clear` explicitly resets active working memory and recent conversational context while retaining historical logs.

The persistent layer separates:

```text
recent raw turns              bounded conversational continuity
working_memory.json           compacted durable working context
pending_notes.jsonl           one semantic Qwen note per completed turn
conversation / trace JSONL    append-only history and research evidence
```

After every completed turn, a separate bounded local Qwen call extracts a compact memory note. Every configured number of successful notes (default six), another local call merges them into `working_memory.json`, tracking current focus, topic frequency, decisions, preferences, and open loops.

Frequency is a **retrieval/salience signal, not an epistemic signal**. Repetition must never upgrade a user claim into a verified fact.

Bounded working memory and recent dialogue are supplied to LOCAL Qwen, FRONTIER Codex delegation, and post-frontier Qwen synthesis. Qwen receives no filesystem tool; the PowerShell wrapper owns persistence and logging.

Host-specific capacity remains separate from memory semantics. A constrained 5k host can expose fewer recent turns and smaller character budgets than a 22k GPU host while running the same shared memory code.

Per-turn bias signals are kept in the research trace, not fed back into compacted working memory, reducing the risk of self-reinforcing labels.

Durable factual/project memory should not be conflated with opaque model weights.

## 8. Synthesis policy

The current prototype uses non-zero sampling during frontier synthesis because the local layer is intentionally allowed to act as an editor and critic rather than a byte-for-byte pipe.

The desired property is not maximal copying. It is **semantic fidelity for sourced facts plus useful transformation for presentation and reasoning**.

Long-term evaluation should therefore track at least:

- factual preservation;
- unsupported additions;
- loss of caveats;
- source-link preservation;
- useful restructuring;
- independent critique;
- latency and token cost.

## 9. Security boundary

The local model should not be trusted as a shell command generator.

A deterministic wrapper owns:

- the executable;
- fixed Codex arguments;
- sandbox mode;
- web policy;
- timeout;
- environment filtering;
- prompt transport.

Future write-capable modes should be separate capabilities rather than a silent expansion of `ask_codex`.

## 10. Alternative Codex-first branch

Experiments with Codex Router demonstrate a complementary architecture:

```text
Codex interface -> Codex Router -> local model
```

This can expose the local model through the Codex agent interface. It is technically functional, but small local models can be burdened by a large agent/tool context and require further tuning.

The Qwen-first and Codex-first paths are treated as separate experimental branches rather than forced into one runtime dependency graph.
