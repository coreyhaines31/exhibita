Run on macOS 26.6.2, file instructions.json, split all, 62 instructions.

### dev

| Interpreter | Answered | Exact, of answered | Exact, of all | Missed redaction, kind or literal | Missed redaction, semantic | Over-redacted | Not found right | Median ms | p90 ms | Model step median ms | Model step p90 ms |
|---|---|---|---|---|---|---|---|---|---|---|---|
| A grammar | 23/31 | 22/23 (96%) | 22/31 (71%) | 0 (5 of 5 blur instructions answered) | 0 (0 of 0 blur instructions answered) | 0 | 1/3 (33%) | 0.29 | 1.03 | n/a | n/a |
| A then model (qwen3.8:27b) | 31/31 | 29/31 (94%) | 29/31 (94%) | 0 (5 of 5 blur instructions answered) | 1 (1 of 1 blur instructions answered) | 0 | 3/3 (100%) | 0.36 | 6542 | 6542 | 8573 |

A then model (qwen3.8:27b): 8 model calls, medians: load 0.04 s, prompt 984.00 tokens in 4.32 s, output 30.00 tokens in 2.48 s; 0 reasoned.

### heldout

| Interpreter | Answered | Exact, of answered | Exact, of all | Missed redaction, kind or literal | Missed redaction, semantic | Over-redacted | Not found right | Median ms | p90 ms | Model step median ms | Model step p90 ms |
|---|---|---|---|---|---|---|---|---|---|---|---|
| A grammar | 15/31 | 15/15 (100%) | 15/31 (48%) | 0 (6 of 6 blur instructions answered) | 0 (0 of 0 blur instructions answered) | 0 | 1/3 (33%) | 0.55 | 1.68 | n/a | n/a |
| A then model (qwen3.8:27b) | 30/31 | 29/30 (97%) | 29/31 (94%) | 0 (7 of 7 blur instructions answered) | 0 (2 of 2 blur instructions answered) | 0 | 3/3 (100%) | 1326 | 8618 | 7476 | 12538 |

A then model (qwen3.8:27b): 15 model calls, medians: load 0.03 s, prompt 986.00 tokens in 4.33 s, output 26.00 tokens in 2.18 s; 0 reasoned.

### all

| Interpreter | Answered | Exact, of answered | Exact, of all | Missed redaction, kind or literal | Missed redaction, semantic | Over-redacted | Not found right | Median ms | p90 ms | Model step median ms | Model step p90 ms |
|---|---|---|---|---|---|---|---|---|---|---|---|
| A grammar | 38/62 | 37/38 (97%) | 37/62 (60%) | 0 (11 of 11 blur instructions answered) | 0 (0 of 0 blur instructions answered) | 0 | 2/6 (33%) | 0.36 | 1.53 | n/a | n/a |
| A then model (qwen3.8:27b) | 61/62 | 58/61 (95%) | 58/62 (94%) | 0 (12 of 12 blur instructions answered) | 1 (3 of 3 blur instructions answered) | 0 | 6/6 (100%) | 0.46 | 8162 | 6721 | 9406 |

A then model (qwen3.8:27b): 23 model calls, medians: load 0.03 s, prompt 984.00 tokens in 4.32 s, output 28.00 tokens in 2.18 s; 0 reasoned.

Missed redaction targets are expected blur targets no blur covers, split into instructions that name a kind, a literal string or the pointer, and semantic ones (tagged "semantic"). Over-redacted counts blurs that touch no expected target. Not found right: of instructions whose answer is "not on the screen", those reported as not found with nothing marked in their place. Model step: time of the model call alone, on the instructions the grammar declined. Missed and over-redacted count answered instructions only.

