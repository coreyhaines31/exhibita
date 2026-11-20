# Model step latency

Issue #28: held-out 2 measured the model step at 11.5 s median and 13.9 s p90, against a bar of 3 s and 10 s. This note is what the time is spent on, what changed, and what is left. Measured on 2026-11-18 on the same machine as held-out 2 (M4 Pro, 48 GB, macOS 26.6.2), Ollama 0.40.13 with its MLX runner, `qwen3.8:27b` (nvfp4, the only model installed). Held-out 2 was not rerun or read.

**Result (2026-11-18): the bar is not met with this model on this Mac.** The model step went from a 7.5 s median to 6.7 to 7.3 s on the dev file; p90 from 13.8 s to 9.4 to 13.9 s. Reading the screen listing costs 4 to 5 s on every new screen, and nothing on the request side removes that.

**Update (2026-11-19): warming the screen up meets the bar on the dev file.** The editor now has the model read the screen when D goes down or the typed field opens. With the instruction arriving 2 s later, `qwen3.8:27b`'s model step is 2.2 s median and 4.7 s p90, at the same accuracy (58 of 62). See [Warming up](#warming-up-2026-11-19).

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

## Warming up (2026-11-19)

Same Mac, Ollama 0.40.13, `qwen3.8:27b` on the MLX runner and `ornith-1.5:9b` on Ollama's llama.cpp runner (`ollama ps` shows which), one model loaded at a time. Held-out 2 was not run or read.

### What the runner reuses

Direct calls to `/api/chat` with the shipping messages (`swift run exhibit-eval prompts --split all`), reading `prefix_cache` lines in `/opt/homebrew/var/log/ollama.log`:

- The MLX runner keeps two kinds of checkpoint: one where a request diverges from the previous one (`matched`), and one 5 tokens before the end of each prompt (an identical request again: `total=977 matched=976 cached=972`). It resumes only from a checkpoint at or before the point of divergence.
- With the old single user message (listing, pointer, instruction), no warm call can be reused past the system prompt: a warm call's end checkpoint lands inside the chat template's tail (about 10 tokens with `think: false`), after the point where the instruction diverges. Tried, all `cached=456`: the listing alone, the listing plus `Instruction:`, the listing and the instruction as two user messages, `think` left out. Two warm calls work (the second diverges right after the listing), but read the listing twice, about 9 s on the 27B, so they gain nothing.
- What works: the screen in its own user turn, then a fixed assistant reply, then the instruction. The warm call is the first two messages (system, screen) with `num_predict: 1`; its end checkpoint falls inside the assistant header that the real request repeats. Pricing screen, 27B: warm call 3.8 s (902 tokens); the instruction then read 33 tokens and took 1.2 s (`matched=901 cached=897`), against 4.9 to 5.5 s cold. The second and third instructions on the screen: 1.3 s each.
- `num_predict: 1` is the least that works everywhere; the warm call's one output token costs about 0.3 s. `keep_alive` is left to the server: the warm call keeps the model loaded like any request.
- llama.cpp (`ornith-1.5:9b`) resumes from any prefix, so it would warm with either shape; with this one the warm call took 1.2 s and the instruction 0.9 s (1.9 s cold).
- Ollama runs one request at a time per model, so an instruction that arrives while the warm call is still reading waits for it and then resumes: never much slower than cold (see the 0 s row).
- Loading after an unload: 11.4 s for the 27B, about 5 s for the 9B. The warm call pays it while the person speaks.

### The chat shape and accuracy

The instruction in its own turn cost the 9B three dev answers (it lost the answer format once and marked things not asked for twice) until the answer format was repeated after the instruction; with that, both models are at or above their old accuracy. Dev set, `--split all`, one run each, same day:

| Chat | `qwen3.8:27b` exact | `ornith-1.5:9b` exact |
|---|---|---|
| Old: one user message | 57/62 | 52/62 |
| Screen turn, reply, instruction | 57/62 | 49/62 |
| Same, answer format repeated after the instruction (shipped) | 58/62 | 52/62 |

### Numbers on the dev file

`instructions.json`, `--split all`, 62 instructions, 24 to the model (23 answered by the 9B: `billing-03` ran to the 400-token cap every run and failed). Cold is today's eval order: instructions on one screen run back to back, so the third and later on a screen are already fast. "Warmed N s ahead" sends the warm-up (`swift run exhibit-eval interpret --warm N`), at most once per screen as the editor does, then the instruction N seconds later. "First on screen" is the median of the first model instruction on each of the 10 screens, the case warming is for. The 9B was unloaded before each cold and 2 s run, since llama.cpp otherwise keeps earlier runs' prompts.

| Model | Mode | Runs | Exact | Missed redaction, kind or literal | Missed redaction, semantic | Model step median | Model step p90 | First on screen | Warm-up itself |
|---|---|---|---|---|---|---|---|---|---|
| `qwen3.8:27b` | cold | 3 | 58/62 (94%) every run | 0 | 0 | 5.4 to 5.5 s | 7.3 s | 5.6 to 5.7 s | |
| `qwen3.8:27b` | warmed 2 s ahead | 3 | 58/62 every run | 0 | 0 | 2.2 s | 4.6 to 4.7 s | 4.0 to 4.1 s | 4.5 s median |
| `qwen3.8:27b` | warmed 5 s ahead | 1 | 58/62 | 0 | 0 | 1.8 s | 2.6 s | 1.7 s | 4.5 s |
| `qwen3.8:27b` | warmed 0 s ahead | 1 | 58/62 | 0 | 0 | 2.5 s | 6.7 s | 6.3 s | 4.4 s |
| `ornith-1.5:9b` | cold | 3 | 52/62 (84%) every run | 0 | 0 (1 of 3 failed) | 1.5 s | 2.4 s | 2.0 to 2.1 s | |
| `ornith-1.5:9b` | warmed 2 s ahead | 3 | 52/62 every run | 0 | 0 (1 of 3 failed) | 0.9 s | 1.5 to 1.6 s | 0.9 s | 1.3 s |
| `ornith-1.5:9b` | warmed 5 s ahead | 1 | 52/62 | 0 | 0 | 0.9 s | 1.5 s | 0.9 s | (cached) |
| Bar | | | 85% on held-out | 0 | | 3 s | 10 s | | |

- No answer flipped between the three runs of either model this time.
- With the instruction 2 s behind, the 27B's first instruction on a screen still waits for the rest of the warm-up (4.5 s), so it takes about 4 s; spoken instructions are usually 2 to 4 s long, and the transcriber's finish adds to that. From 5 s on it is under 2 s.
- With no gap at all (0 s) the first instruction on a screen is 0.6 s slower than cold (6.3 against 5.7 s): it waits for the whole warm-up and then reads its own turn, which a cold request would have read in one go. Later instructions on the screen are as fast as warmed.
- The warm-up loads the model (about 25 GB for the 27B) when D goes down, even if the built-in commands then answer the instruction.

Raw rows: `results/A_then_model_qwen3.8-27b-all.json`, `A_then_model_qwen3.8-27b_warmed_2_s_ahead-all.json`, `A_then_model_ornith-1.5-9b-all.json`, `A_then_model_ornith-1.5-9b_warmed_2_s_ahead-all.json`.

### Sending less of the screen

Not changed. Choosing targets or positions by the instruction's words would make the screen turn depend on the instruction, which the warm-up cannot know, and would undo the reuse above. With warming, the listing's length only sets the warm-up's own cost (4.5 s on the 27B), which matters only for instructions given in less time than that. Trimming that does not depend on the instruction (dropping more lines, or positions altogether) was not measured.

### Still unmeasured

- Held-out 2 for `gemma4:26b-nvfp4` and for the editor-open warm-up (held-out 2 with warming at D: `heldout2-results.md`).
- A real dictation: the gap between D going down and the instruction reaching the model, measured in the app rather than assumed as 2 s.
- OpenAI-compatible servers (LM Studio, llama.cpp's own server) with the new chat shape and the one-token warm-up.
- A server running more than one request at a time (`OLLAMA_NUM_PARALLEL` above 1): the warm-up and the instruction would then run side by side and the instruction would gain nothing.
- Models other than the three installed (see below for `gemma4:26b-nvfp4`).

## `gemma4:26b-nvfp4` (2026-11-19)

Pulled for issue 28: Gemma 4's 26B mixture-of-experts model (25.2B parameters, 3.8B active per token), in the nvfp4 tag so it runs on the MLX runner like `qwen3.8:27b` (`ollama ps`: `mlx`). 16 GB download. Same dev file, same Mac, the other models stopped first, three runs per mode.

| Mode | Exact | Missed redaction, kind or literal | Missed redaction, semantic | Model step median | Model step p90 | First on screen | Warm-up itself |
|---|---|---|---|---|---|---|---|
| cold | 56/62 (90%) every run | 0 | 2 | 1.1 to 1.5 s | 1.7 to 3.1 s | 1.1 to 1.5 s | |
| warmed 2 s ahead | 56/62 every run | 0 | 3 | 0.8 to 1.1 s | 1.1 to 3.8 s | 0.7 to 1.1 s | 0.7 to 1.0 s |
| warmed 5 s ahead | 56/62 every run | 0 | 3 | 0.8 to 0.9 s | 1.3 to 1.5 s | 0.8 s | 0.8 s |

- It reads the listing about five times faster than the 27B (about 1000 tokens in 0.6 to 1 s) and loads in 11.7 s. Memory in use (`ollama ps`): 16 GB once loaded, 24 GB after the eval's runs.
- The warm-up reuse works on its runner: after a 0.7 s warm-up the instruction read 66 tokens (`matched=972 cached=972`).
- The same five model instructions are wrong in every run (`billing-03`, `table-02`, `editor-03`, `pricing-04`, `team-04`). The semantic misses are all `billing-03`, "hide anything that identifies the customer": it blurs the email, phone and customer id but not the name or the card (warmed, one more).
- Verdict: faster than `qwen3.8:27b` at every point, but less accurate and with missed semantic redactions, so `RecommendedModels` keeps `qwen3.8:27b` first and does not list it. Settings describes it from these numbers (`ModelGuide`).
- The eval's model preload (an empty screen) got a prose answer from it, which used to abort the run; the preload's answer is now ignored.

Raw rows: `results/A_then_model_gemma4-26b-nvfp4-all.json`, `..._warmed_2_s_ahead-all.json`, `..._warmed_5_s_ahead-all.json`.

## Warming when an editor opens (2026-11-19)

An editor that opens with its text read warms the screen at once, but only when the model in effect is already in the server's memory (Ollama's `GET /api/ps`; an OpenAI-compatible server has no such list and is never warmed at open), so opening a capture never loads a model. Otherwise the warm-up waits for D or the typed field as before.

On the dev file this is the eval's `--warm 10 --if-loaded` (the model is loaded by the eval's preload, as it would be after an earlier instruction), one run of `qwen3.8:27b`:

| Mode | Exact | Missed redaction, kind or literal | Missed redaction, semantic | Model step median | Model step p90 | First on screen |
|---|---|---|---|---|---|---|
| cold | 58/62 | 0 | 0 | 5.4 to 5.5 s | 7.3 s | 5.6 to 5.7 s |
| warmed at D, 2 s ahead | 58/62 | 0 | 0 | 2.2 s | 4.6 to 4.7 s | 4.0 to 4.1 s |
| warmed at open, 10 s ahead | 58/62 | 0 | 1 | 2.0 s | 2.9 s | 1.9 s |

The first instruction on a screen goes from about 4 s (warmed at D) to about 2 s. The one semantic miss is `billing-03` leaving the card unblurred this run, an answer this model flips between runs (it was right in the six runs above); it does not come from the warm-up, whose request is the same as at D. Raw rows: `results/A_then_model_qwen3.8-27b_warmed_10_s_ahead_if_loaded-all.json`.
