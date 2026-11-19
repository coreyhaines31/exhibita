Run on macOS 26.6.2, file instructions-heldout2.json, split heldout2, 36 instructions.

### heldout2

| Interpreter | Answered | Exact, of answered | Exact, of all | Missed redaction, kind or literal | Missed redaction, semantic | Over-redacted | Not found right | Median ms | p90 ms | Model step median ms | Model step p90 ms |
|---|---|---|---|---|---|---|---|---|---|---|---|
| A grammar | 23/36 | 22/23 (96%) | 22/36 (61%) | 0 (10 of 10 blur instructions answered) | 0 (1 of 1 blur instructions answered) | 0 | 0/4 (0%) | 0.68 | 2.09 | n/a | n/a |
| A then model (qwen3.8:27b) | 36/36 | 32/36 (89%) | 32/36 (89%) | 0 (12 of 12 blur instructions answered) | 0 (2 of 2 blur instructions answered) | 2 | 4/4 (100%) | 1.64 | 13475 | 11546 | 13887 |

Missed redaction targets are expected blur targets no blur covers, split into instructions that name a kind, a literal string or the pointer, and semantic ones (tagged "semantic"). Over-redacted counts blurs that touch no expected target. Not found right: of instructions whose answer is "not on the screen", those reported as not found with nothing marked in their place. Model step: time of the model call alone, on the instructions the grammar declined. Missed and over-redacted count answered instructions only.

