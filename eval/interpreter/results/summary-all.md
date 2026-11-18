Run on macOS 26.6.2, split all, 62 instructions.

### heldout

| Interpreter | Answered | Exact, of answered | Exact, of all | Missed redaction targets | Over-redacted targets | Median ms | p90 ms |
|---|---|---|---|---|---|---|---|
| A grammar | 17/31 | 15/17 (88%) | 15/31 (48%) | 3 (in 10 blur instructions) | 5 | 0.80 | 2.20 |
| B Apple on-device | 31/31 | 9/31 (29%) | 9/31 (29%) | 8 (in 10 blur instructions) | 18 | 2626 | 3554 |
| A then B | 31/31 | 16/31 (52%) | 16/31 (52%) | 7 (in 10 blur instructions) | 20 | 2.38 | 2956 |
| C ollama:qwen3.8:27b | 31/31 | 27/31 (87%) | 27/31 (87%) | 3 (in 10 blur instructions) | 1 | 1977 | 10508 |
| A then C | 31/31 | 28/31 (90%) | 28/31 (90%) | 3 (in 10 blur instructions) | 5 | 2.38 | 8588 |

### dev

| Interpreter | Answered | Exact, of answered | Exact, of all | Missed redaction targets | Over-redacted targets | Median ms | p90 ms |
|---|---|---|---|---|---|---|---|
| A grammar | 23/31 | 22/23 (96%) | 22/31 (71%) | 0 (in 7 blur instructions) | 0 | 0.26 | 0.98 |
| B Apple on-device | 31/31 | 12/31 (39%) | 12/31 (39%) | 9 (in 7 blur instructions) | 14 | 2469 | 4247 |
| A then B | 31/31 | 23/31 (74%) | 23/31 (74%) | 4 (in 7 blur instructions) | 11 | 0.30 | 2560 |
| C ollama:qwen3.8:27b | 31/31 | 27/31 (87%) | 27/31 (87%) | 1 (in 7 blur instructions) | 0 | 1818 | 8881 |
| A then C | 31/31 | 28/31 (90%) | 28/31 (90%) | 1 (in 7 blur instructions) | 0 | 0.30 | 1570 |

### all

| Interpreter | Answered | Exact, of answered | Exact, of all | Missed redaction targets | Over-redacted targets | Median ms | p90 ms |
|---|---|---|---|---|---|---|---|
| A grammar | 40/62 | 37/40 (93%) | 37/62 (60%) | 3 (in 17 blur instructions) | 5 | 0.33 | 1.85 |
| B Apple on-device | 62/62 | 21/62 (34%) | 21/62 (34%) | 17 (in 17 blur instructions) | 32 | 2558 | 3672 |
| A then B | 62/62 | 39/62 (63%) | 39/62 (63%) | 11 (in 17 blur instructions) | 31 | 0.66 | 2887 |
| C ollama:qwen3.8:27b | 62/62 | 54/62 (87%) | 54/62 (87%) | 4 (in 17 blur instructions) | 1 | 1977 | 10508 |
| A then C | 62/62 | 56/62 (90%) | 56/62 (90%) | 4 (in 17 blur instructions) | 5 | 0.66 | 2220 |

C: Ollama has no structured output for qwen3.8:27b, so its JSON was not constrained.
