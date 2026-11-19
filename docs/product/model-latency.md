# Model step latency

Issue #28: held-out 2 measured the model step at 11.5 s median and 13.9 s p90, against a bar of 3 s and 10 s. This note is what the time is spent on, what changed, and what is left. Measured on 2026-11-18 on the same machine as held-out 2 (M4 Pro, 48 GB, macOS 26.6.2), Ollama 0.40.13 with its MLX runner, `qwen3.8:27b` (nvfp4, the only model installed). Held-out 2 was not rerun or read.

**Result: the bar is not met with this model on this Mac.** The model step went from a 7.5 s median to 6.7 to 7.3 s on the dev file; p90 from 13.8 s to 9.4 to 13.9 s. Reading the screen listing costs 4 to 5 s on every new screen, and nothing on the request side removes that.

## Method

1. Called `/api/chat` directly with the shipping request body (system prompt, screen listing, `"think": false`, `num_predict` 400) for dev-file instructions, and read `load_duration`, `prompt_eval_count`, `prompt_eval_duration`, `eval_count`, `eval_duration` and the `thinking` field. Ran the same messages through `/v1/chat/completions`.
2. Read the runner's own log (`/opt/homebrew/var/log/ollama.log`), whose `prefix_cache` lines say how many prompt tokens matched the cache and how many it could actually reuse.
3. Added these fields to the eval's result rows (`modelTimings`) and a median breakdown to its summary, then ran `swift run exhibit-eval interpret --split all --only grammar,model` (the 62 instructions of `instructions.json`; the grammar declines 24 of them, which go to the model) before and after each change.

The machine was shared with other work during the runs, so generation speed varied between 10 and 30 tokens a second for the same output. Prompt reading was steadier.

## Where the time goes

Direct calls, shipping body:

| Call | Load | Prompt read | Output | Total |
|---|---|---|---|---|
| First call after the model unloaded | 11.6 s | 1265 tokens, 14.2 s | 29 tokens, 1.6 s | 27.5 s |
| Same instruction again | 0 | 0.1 s (cached) | 29 tokens, 0.9 s | 1.0 s |
| New instruction, same screen, second one | 0 | 1262 tokens, 10.2 s | 36 tokens, 1.3 s | 11.5 s |
| New instruction, same screen, third and later | 0 | 0.2 to 0.3 s | 20 to 50 tokens, 0.8 to 1.7 s | 1.0 to 2.0 s |
| New screen, model warm | 0 | 6.8 to 8.6 s for the listing | 25 to 30 tokens, about 1 s | 8 to 10 s |

- **Reasoning is not the cause on Ollama's own API.** `think: false` is honoured: no `thinking` field, 20 to 66 output tokens. Generation is 1 to 3 s.
- **Reading the prompt is the cause.** The model reads about 125 tokens a second, which by a rough estimate is near the GPU's compute limit for a 27B model. A listing of 30 to 50 targets was 800 to 1200 tokens, so 7 to 10 s.
- **The cache helps less than it looks.** This model mixes attention with recurrent layers, and the MLX runner can only resume from saved checkpoints, not from any matching prefix (`cache hit total=926 matched=907 cached=456`: 907 tokens matched, 456 reusable). A checkpoint is saved where a request diverges from the cache. So the system prompt (456 tokens) is reused across screens once warm, the first and second instructions on a new screen both read the whole listing, and only the third and later are fast. That is the two groups held-out 2 saw: 2 to 4 s and 9 to 15 s.
- **The OpenAI-compatible path did reason.** Through Ollama's `/v1`, the same request wrote 256 tokens with 801 characters of reasoning and took 13.0 s; with `reasoning_effort: "none"` it wrote 45 tokens in 6.1 s.
- **Loading** is 11.6 s, once per Ollama `keep_alive` (5 minutes by default).

## What changed

| Change | Why | Effect |
|---|---|---|
| Per-call timings in eval rows and the summary | So the phase is visible in every future run | `modelTimings` in `results/*.json` |
| `/v1` requests send `reasoning_effort: "none"` and `chat_template_kwargs.enable_thinking: false`, and ask again without them on HTTP 400 | The OpenAI-compatible path reasoned despite the prompt | 13.0 s to 6.1 s on Ollama's `/v1` |
| Shorter listing: `t12 "Update plan" 29,22` (top-left corner in tens of pixels, no size, no `text` keyword) | The model reads digits one at a time; exact boxes were about half the listing | Median prompt 1398 to 984 tokens, reading 6.3 s to 4.3 s |

Kept as it was: `num_predict` 400 (answers are 20 to 66 tokens; the cap only matters for a runaway answer), and `keep_alive` (holding about 25 GB for longer is the person's choice; `OLLAMA_KEEP_ALIVE` on the server sets it).

## Numbers on the dev file

`instructions.json`, `--split all`, 24 model calls per run.

| Run | Model step median | Model step p90 | Prompt (median) | Output (median) | Exact, grammar then model |
|---|---|---|---|---|---|
| Before | 7.5 s | 13.8 s | 1398 tokens, 6.3 s | 29 tokens, 2.1 s | 58/62 (dev 28/31) |
| After, run 1 | 7.3 s | 13.9 s | 986 tokens, 4.6 s | 29 tokens, 3.3 s | 57/62 (dev 29/31) |
| After, run 2 | 6.7 s | 9.4 s | 984 tokens, 4.3 s | 28 tokens, 2.2 s | 58/62 (dev 29/31) |
| Bar | 3 s | 10 s | | | 85% |

Missed redactions stayed at 0 for kind or literal blurs and 1 of 3 semantic blurs answered in every run (`billing-03`, the same miss before and after). Run to run the model flips one or two answers (`team-04`, `table-02`); `table-02` failed once with an answer that ran to the token cap.

After the changes, a warm model on a new screen still spends about 4.5 s reading the listing and 1 to 3 s writing the answer, so the first instruction on a screen takes 5 to 8 s. With this model on this Mac, a median of 3 s needs most instructions to land on a screen the runner has already seen twice, which is not how `say` is used.

## Still unmeasured

- Smaller models (an 8B model should read the prompt 3 to 4 times faster; none is installed here, and none was pulled for this).
- Macs with less memory or fewer GPU cores, where reading the prompt is slower still.
- The llama.cpp runner, which may resume from any prefix and so make repeated instructions on one screen cheap.
- LM Studio and llama.cpp servers with the new `/v1` switches: only Ollama's `/v1` was checked. A server that refuses them gets the request again without them.
- Held-out 2 with these changes: not rerun.

## Smaller models (2026-11-18)

Same development file (`instructions.json`, `--split all`, 62 instructions), same Mac, shortened listing, one run each. The grammar answers 38 of the 62 in every row; the model answers the rest.

| Model | Download | Exact, all 62 | Exact, of the model's own answers | Missed redaction targets | Model step median | Model step p90 |
|---|---|---|---|---|---|---|
| `qwen3.8:27b` | 18 GB | 58 (94%) | about 21 of 24 | 0 | 6.7 to 7.3 s | 9.4 to 13.9 s |
| `ornith-1.5:9b` | 6.6 GB | 52 (84%) | 15 of 24 | 1, semantic | 2.2 s | 3.1 s |
| `bonsai-2:4b` | 1.6 GB | 42 (68%) | 5 of 19, 5 declined | 6 | 1.8 s | 2.2 s |
| Bar | | 85% on held-out | | 0 kind or literal | 3 s | 10 s |

- `ornith-1.5:9b` meets the speed bar and reads the listing about four times faster (984 tokens in 1.4 s). It gets the easy free-form cases and fails the ones that need reasoning across rows ("the customer that is past due", "the remove button for mei", "the biggest customer"), and on "hide anything that identifies the customer" it left one identifying line unblurred.
- `bonsai-2:4b` is not usable: it reports most things as not found and missed six redaction targets.
- No model tested meets both bars. The choice is speed with a 9B model or accuracy with a 27B one.
- Not run on held-out 2, so these are development-set numbers and will flatter both.

Raw rows: `eval/interpreter/results/A_then_model_ornith-1.5-9b-all.json`, `A_then_model_bonsai-2-4b-all.json`.
