# L4-D1 Detector Evaluation Results

**Date:** 2026-10-13
**Core local model:** `qwen3.5-4b-core-cpu5k:latest`
**Protocol:** `schema`
**Mode:** offline bounded experiment; no R1 writes; no runtime hook.

## Deterministic baseline
- scored cases: 30
- relational abstention: 4/4
- TP/FP/FN/TN: 16 / 2 / 4 / 128
- micro F1: 0.8421
- exact-set accuracy: 0.8000
- model calls: 0

## Local-model detector
| Measure | Run 1 | Run 2 |
| --- | ---: | ---: |
| Micro precision | 0.8000 | 0.8000 |
| Micro recall | 0.8000 | 0.8000 |
| Micro F1 | 0.8000 | 0.8000 |
| Macro F1 | 0.7333 | 0.7333 |
| Exact-set accuracy | 0.7333 | 0.7333 |
| Coverage | 0.6667 | 0.6667 |
| Relational abstention | 2/4 | 2/4 |
| Model calls | 4 | 4 |
| Latency seconds | 97.3184 | 95.5884 |

Prediction-set stability: **1.0000** (34/34).

All model batches parsed successfully. A transport/schema/ID/count failure is a hard experiment failure and is not converted to abstention.

## Private curated sanity check
- cases: 10
- baseline micro F1: 0.0000
- model micro F1: 0.2500
- baseline exact: 0.8000
- model exact: 0.6000
- model calls: 1

## Decision
**DOES_NOT_YET_BEAT_RELIABLE_BASELINE**

Total valid model calls: 9
Total measured model-request latency: 218.6955 seconds.

The decision concerns only whether this bounded detector deserves further research. It does not authorize runtime integration.