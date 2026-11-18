# Held-out 2 results

Run once on 2026-11-18, after all interpreter and `say` code on `feature/26-say-command` was committed and pushed (last code commit 13:43, run finished 13:46). No interpreter code changed afterwards. Set: `eval/interpreter/instructions-heldout2.json`, 36 instructions, written by an author who could not read the interpreter. Machine: M4 Pro, 48 GB, macOS 26.6.2, Ollama `qwen3.8:27b`.

Reproduce: `swift run exhibit-eval interpret --file instructions-heldout2.json --split heldout2 --only grammar,model`. Raw rows: `eval/interpreter/results/*-heldout2.json`.

## Against the bar

| Requirement | Bar | Measured | Result |
|---|---|---|---|
| Grammar then model, exact | 85% or more | 32/36 (89%) | pass |
| Missed redaction targets, kind or literal | 0 | 0 across 12 blur instructions | pass |
| Missed redaction targets, semantic | 1 per 10 at most | 0 across 2 blur instructions | pass, on a small sample |
| "Not on the screen" reported right | 4 of 5 | 4/4 | pass |
| Grammar alone, exact on what it answers | 95% or more | 22/23 (96%) | pass |
| Grammar alone, missed redactions | 0 | 0 across 11 blur instructions | pass |
| Model step, median | 3 s or less | 11.5 s | **gap** |
| Model step, p90 | 10 s or less | 13.9 s | **gap** |

Accuracy and redaction safety meet the bar. Latency does not.

## Latency

The 13 model calls split into two groups: five took 2.0 to 3.7 s, eight took 9.2 to 15.4 s. The spike measured a 1.7 s median with the same model, so the slow group is new. Not diagnosed. Candidates: the model reasoning before it answers on some prompts, the longer shipping prompt, or generation length. Tracked as a follow-up issue; the grammar path is unaffected (median under 1 ms).

## The four misses

| Id | Instruction | What happened |
|---|---|---|
| h2-crm-03 | "Blur the email and phone numbers, then highlight the deal value." | Grammar. Blurs right; highlight took every line holding "deal" or "value" instead of the one figure. Over-highlight, no redaction error. |
| h2-ticket-06 | "blur everything the customer pasted that they shouldn't have" | Model. Blurred the key and card, and also an email and a phone number that were not expected (2 over-redactions). Errs on the safe side. |
| h2-ticket-07 | "highlight the refund amount and box merch" | Model. Reported both as not found. "merch" is rightly absent; the refund amount was on screen. |
| h2-table-01 | "box the biggest account" | Model. Boxed the amount cell, not the account's row or name. |

No miss left something visible that should have been hidden.

## Limits

Typed instructions on synthetic screenshots, one model, one machine, one run. Only two semantic redactions, so that row says little. Real voices, smaller models and Macs with less memory are unmeasured.
