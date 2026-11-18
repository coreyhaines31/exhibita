# Unit 0: interpreter and speech spike

Run 2026-11-18 on an M4 Pro Mac with macOS 26.6.2. Issue #3.

## Answer in brief

- **The grammar (A)** answered 17 of the 31 held-out instructions with no model. It was right on 15 of those 17, in under 3 ms. Both of its held-out errors were redaction errors, and both come from specific bugs listed below.
- **Apple's on-device model (B)** got 29% of held-out instructions right, at about 2.6 s each. With the grammar in front of it (A then B), 52% were right, but the model's answers on the instructions the grammar declined were mostly wrong, and it over-blurred heavily. **Do not ship it in v1.**
- **A local model (C)**, here `qwen3.8:27b` through Ollama, got 87% right on its own and **90% with the grammar first (A then C)**. Its median time was 1.7 s on the instructions the grammar declined, with a slowest case of 11.6 s.
- **Speech:** `SpeechTranscriber` (macOS 26) transcribed 10 synthetic utterances on device in a median of 77 ms per file after the first (291 ms cold), with 4 word errors in 49 words and no permission prompt. Synthetic speech flatters these numbers.

**Recommendation:** unit 7 ships the grammar, with the two fixes listed below. Unit 8 ships the local model endpoint as the free-form tier and leaves Apple's on-device model out. The bar for unit 8 is under "The bar for unit 8".

## Method

### Fixtures

Ten screens written as small HTML pages in `eval/interpreter/fixtures/` and rendered headless at 1280 by 800 with `agent-browser`:

- billing settings
- inbox
- chat thread
- spreadsheet
- code editor with a `.env` file
- pricing page
- dashboard
- login form
- terminal
- team settings with avatars

Their target lists come from the real `exhibit targets` (Vision OCR plus secret detection) and are committed beside them, so the eval sees what the app would see, including OCR quirks: "deployadb" for "deploy@db", "SrC" for "src", and a chart read as "•ill|". Names, addresses and keys are made up. Keys avoid provider prefixes so push protection does not trip.

### Instructions

There are 62 instructions in `eval/interpreter/instructions.json`, each with an expected result written by hand from the target lists before any interpreter existed. The set:

- covers all seven marks
- redaction by kind and by text
- several operations in one sentence
- vague and semantic requests
- pointer requests (the pointer position is part of the input)
- things that are not on the screen
- speech-like input: lowercase, no punctuation, "prising", "e mails", "sign op", "in voices"

An expectation names targets by kind, exact line, substring or target id. Where a careful person could defend another answer (for example "circle the churn rate": the value, the label, or both), the expectation lists alternatives, and any one counts.

They are split 31 dev and 31 held out, at least two per screen in each half. The grammar and both prompts were tuned only on dev. Every held-out run was done once, at the end, with code that was then frozen (commit `914dafe`).

Two caveats about leakage, stated plainly:

1. The same author wrote the held-out instructions and the grammar, so the held-out half guards against tuning to results, not against the author's knowledge. Words in the grammar's "needs judgement" list that had come only from held-out instructions ("except", "biggest", "first", "new") were removed before any run.
2. The held-out half has now been seen. Unit 8 needs a fresh held-out set (see the bar below).

### Scoring

For each instruction, operations are grouped by mark kind, each group with the set of target ids its picks resolve to. An answer is an **exact match** when those sets equal the expected ones and it reports "not found" exactly when the expectation does. Labels, colours and step order are not scored.

For instructions that expect a blur:

- **Missed redaction targets** counts expected targets that no predicted blur covers. A blur on a whole line counts as covering the email inside it.
- **Over-redacted targets** counts predicted blurs that touch no expected target.

These are counted only where the interpreter answered.

Latency is wall-clock time for one interpretation, after a warm-up call that loads the model.

### Interpreters

- **A, the grammar:** `GrammarInterpreter` in `ExhibitInterpret`. It reads verbs, kinds, pointer words, whole lines, lines containing a phrase, and close mis-hearings (edit distance 1 or 2 on a whole line). It declines anything that needs judgement, any phrase it cannot find and any tie, so the next interpreter can try. Its coverage is the share of instructions it answers.
- **B, Apple's on-device model:** FoundationModels `SystemLanguageModel.default`, which reported `available` on this Mac. It uses guided generation with a `DynamicGenerationSchema` whose refs are an enum of the listed targets, so it cannot name a target that does not exist. Sampling is greedy, with at most 400 response tokens.
- **C, a local model:** Ollama 0.40.13 at `127.0.0.1:11434`, model `qwen3.8:27b` (18 GB, nvfp4 on Ollama's MLX runner), thinking off, temperature 0. Ollama refused structured output for this model ("structured output is unavailable"), so the answer format went in the prompt and refs were checked after the fact. Unknown refs are dropped, never guessed. One large model says little about the 3B to 8B models most people would run; none were pulled.
- **A then B, A then C:** the grammar first, the model only where the grammar declined. This is how the free tier would ship. These rows are computed from the A and model runs. The grammar is deterministic, so re-running it adds nothing.

Both models see the same prompt and the same listing (`TargetListing`): refs `t1`, `t2`, ... in reading order, kind, masked text and box. Sensitive targets appear as "(hidden email address)" and similar. A text line made entirely of mask characters that duplicates a sensitive target is dropped, and the target under the pointer is named. No model ever sees the image or a secret.

### Prompt iterations (dev only)

| Version | Change | B on dev | C on dev |
|---|---|---|---|
| 1 | Rules list, `operations` plus `notFound` arrays | 1/31; twice overflowed the 4,096-token context | not run |
| 2 | One worked example, caps of 4 operations, 12 targets and 400 tokens | 2/31 | not run |
| 3 | Each part quotes the instruction's own words; a part with no targets means not found | 10/31 | not run |
| 4 | One part per thing named; plural means all, singular means one | 13/31 | 27/31 |

Version 4 is frozen. Apple's model was not fully deterministic: the same prompt with greedy sampling scored 13/31 on dev while tuning and 12/31 in the final run.

## Results

### Held out (the headline)

| Interpreter | Answered | Exact, of answered | Exact, of all | Missed redaction targets | Over-redacted targets | Median ms | p90 ms |
|---|---|---|---|---|---|---|---|
| A grammar | 17/31 (55%) | 15/17 (88%) | 15/31 (48%) | 3 | 5 | 0.80 | 2.20 |
| B Apple on-device | 31/31 | 9/31 (29%) | 9/31 (29%) | 8 | 18 | 2626 | 3554 |
| A then B | 31/31 | 16/31 (52%) | 16/31 (52%) | 7 | 20 | 2.38 | 2956 |
| C qwen3.8:27b | 31/31 | 27/31 (87%) | 27/31 (87%) | 3 | 1 | 1977 | 10508 |
| A then C | 31/31 | **28/31 (90%)** | **28/31 (90%)** | 3 | 5 | 2.38 | 8588 |

There are 10 held-out instructions that expect a blur. In both chain rows, all 3 missed and 5 of the over-redacted targets come from the grammar's two bugs, which are listed under "Grammar (A)" below.

### Dev

| Interpreter | Answered | Exact, of answered | Exact, of all | Missed redaction targets | Over-redacted targets | Median ms | p90 ms |
|---|---|---|---|---|---|---|---|
| A grammar | 23/31 (74%) | 22/23 (96%) | 22/31 (71%) | 0 | 0 | 0.26 | 0.98 |
| B Apple on-device | 31/31 | 12/31 (39%) | 12/31 (39%) | 9 | 14 | 2469 | 4247 |
| A then B | 31/31 | 23/31 (74%) | 23/31 (74%) | 4 | 11 | 0.30 | 2560 |
| C qwen3.8:27b | 31/31 | 27/31 (87%) | 27/31 (87%) | 1 | 0 | 1818 | 8881 |
| A then C | 31/31 | 28/31 (90%) | 28/31 (90%) | 1 | 0 | 0.30 | 1570 |

All 62 together, and every answer, are in `eval/interpreter/results/`. `summary-all.md` has the tables, and one JSON file per interpreter has each instruction's output.

### Latency of the model step

The chain medians above are small because the grammar answers most instructions in under a millisecond. Timing only the instructions the grammar declined:

| Model | Split | Instructions | Median ms | Slowest ms |
|---|---|---|---|---|
| B Apple on-device | held out | 14 | 2558 | 3865 |
| B Apple on-device | dev | 8 | 2202 | 4373 |
| C qwen3.8:27b | held out | 14 | 1690 (p90 10686) | 11605 |
| C qwen3.8:27b | dev | 8 | 1447 | 6566 |

Qwen's time varies with how much it writes. The slowest answers were long blur lists on large screens.

## Failures

### Grammar (A)

- **"blur kenji watanabe" (held out):** the grammar blurred only the sidebar line that reads exactly "Kenji Watanabe". It missed the three message headers that contain the name ("Kenji Watanabe 10:02 AM"). The cause: the whole-line preference, which is right for "circle Pricing", was also applied to blur. A redaction must never be narrowed this way. **Fix in unit 7:** for blur and highlight, use every line containing the phrase, as the CLI's `--text` does.
- **"blur grace holloway and her email" (held out):** "her" was dropped as a determiner, so "her email" became every email on the sheet (5 over-redacted). **Fix in unit 7:** a possessive or other qualifier before a kind word ("her email", "the payments key") means decline.
- **"circle the total" (dev):** the grammar circled the label "Total", not "$5,130". This is defensible, but it is wrong against the expectation.
- **Declines it should keep:** "hide anything that identifies the customer", "circle the message about the failing job", "box the commit that fixed the retry backoff", "number the three plans", "highlight november" (the screen says "Nov") and "circle the export button". These all went to the model.

### Apple on-device (B)

- **Extra parts:** "circle this" became a circle and an arrow. "box the start free trial buttons" became arrows. "point at open tickets and label it needs triage" became two arrows labelled "at" and a text mark.
- **Plurals and kinds:** "blur the email column" blurred 1 of 6 emails. "Redact the API key and the phone number" made a text label and arrows, so both secrets were missed.
- **Filling the screen:** "blur the faces" (none on screen) and "blur everybody's emails except the pending invite" blurred page titles, nav items and headers; 12 targets were over-redacted on one instruction.
- **Wrong target:** "circle the free trial button on the pro plan" circled "3 projects". "highlight the biggest customer" highlighted "Reports". "circle sign op" circled "Sign in".
- **Not found:** it said "not found" only twice in 62 answers. When something was missing, it marked something else instead ("blur the credit card" blurred an email).

### Qwen 27B (C)

- **"blur kenji watanabe":** it also chose only the sidebar line, so 3 targets were missed.
- **"blur all the secrets":** it added the support email; the expectation was keys only.
- **"circle the churn rate" and "box the cancelled account":** it marked the whole row or tile (label, value and change) instead of one item.
- **"blur the faces" (none on screen):** it blurred the avatar initials "EV", "JP", "MK" and "SA" instead of reporting none. This is arguably reasonable, but it is wrong against the expectation.
- **"hide anything that identifies the customer":** it hid the name, email, phone and customer ID, but not the card number.

It reported missing things correctly: "highlight the discount code", "circle the export button", and the missing half of "blur the emails and circle the log out button".

## Speech

`swift run exhibit-eval speech` generates ten instructions with `say -o` (nothing plays) and transcribes the files with `SpeechAnalyzer` and `SpeechTranscriber` (en-US, `.transcription` preset) on device.

| Measure | Result |
|---|---|
| Transcription time, per utterance of 0.9 to 2.6 s | median 77 ms after the first; first (cold) 291 ms |
| Word errors | 4 of 49 (8%) |
| Grammar reads the transcript the same as the typed text | 8 of 10 |

The errors were:

- "Point at Update plan" was heard as "Appointed update plan".
- "point at open tickets" was heard as "Point it open tickets".
- "Watanabe" was heard as "Wadanabi". The grammar's close match still found the name.

The two "point at" errors broke the grammar, which suggests teaching it "point it" and similar near-misses in unit 7.

Caveats:

- `say` is clean, evenly paced and has no background noise or accent. Real dictation will do worse.
- These are whole files, faster than real time. For push-to-talk, the number that matters is the time from releasing the key to the final text, with audio streamed while the key is held. That was not measured.
- No permission prompt appeared. `SFSpeechRecognizer` authorization is "not determined" for this tool and was deliberately not requested, so the older API was **not assessed**.
- `AssetInventory` reported en-US as `supported`, not `installed`, yet transcription ran and en-US is in `SpeechTranscriber.installedLocales`. No download was requested, so the download size is **not measured**.

## Not assessed, and why

- **Apple's model on other Macs and older systems:** only one Mac, with Apple Intelligence available. It needs macOS 26 and an eligible device; the availability reasons are `deviceNotEligible`, `appleIntelligenceNotEnabled` and `modelNotReady`.
- **Smaller local models, LM Studio, and Ollama structured output:** I was told not to pull models or install software. The one model available did not support Ollama's structured output.
- **Hosted models (the issue mentions Claude):** spec decision 4 keeps cloud interpretation out of v1 and paid. Not run.
- **Speech on macOS 14 and 15:** `SpeechAnalyzer` is macOS 26 only. WhisperKit, the spec's assumption for older systems, would be a new third-party dependency and was not added. Its latency and download size are still open.
- **Live microphone input:** never used; the tool only reads files.

## The bar for unit 8

Unit 8 is accepted when, on a **fresh held-out set** of at least 30 instructions written before any unit 8 tuning (this held-out half has now been seen), with the shipping prompt and the grammar first:

1. **Accuracy:** A then model gets at least 85% exact.
2. **Redaction misses:** zero missed redaction targets on instructions that name a kind or a literal string ("blur the emails", "blur kenji watanabe"). At most 1 missed target per 10 semantic redaction instructions ("anything that identifies the customer"). Over-redaction is allowed but reported.
3. **Not found:** when something is not on the screen, the model reports it as not found, and never marks something else in its place, in at least 4 of 5 such instructions.
4. **Latency:** for the model step, a median of at most 3 s and a p90 of at most 10 s on an M-series Mac, with the "interpreting" state shown. Each model a user can pick should be tested against this bar. One 27B model passing it does not show that an 8B model does.
5. **The grammar alone** stays at least 95% exact on what it answers, with zero missed redaction targets on what it answers.

On this run, A then C met items 1 and 3 (90% held out; not found right in all 6 such instructions, 3 of them held out) and the latency median (1.7 s). Its model-step p90 was 10.7 s on held out, just over the bar, and 8.7 s over all 22 declined instructions. It failed item 2 through the grammar's narrowing bug and the same miss by Qwen, so the grammar fix comes first. A then B met none of them.

## What should change in the spec

1. **Free and paid table, and Decision 1:** the free-form tier is "a local model the user runs (Ollama or LM Studio endpoint)". Drop "Apple's on-device model" for v1, or put it behind an "experimental" setting that is off by default. Re-run `exhibit-eval` when Apple ships a new model; it is one command.
2. **Voice table:** "Hide anything that identifies the customer" needs a configured local model. Without one, the grammar declines.
3. **States:** add "needs a model". When the grammar declines and no model is set up, show the transcript, "This needs a model; set one up in Settings", and change nothing.
4. **Voice:** marks from a model are applied at once with one ⌘Z, as the spec says. At about 1 wrong answer in 10, the summary of what was done ("Blurred 4 emails") matters more than it looked, and should name each mark.
5. **Interpreter contract:** the local endpoint path must not depend on structured output. Some Ollama runners refuse it, so the app checks refs itself (as the eval does).
6. **Speech:** on macOS 26, use `SpeechTranscriber`. It needed no prompt for file input here and was fast. The "speech model downloading" state may be rare on 26, but test it on a clean account. WhisperKit for macOS 14 and 15 is still unverified.
7. **Build units, unit 8:** replace "meets the bar set in unit 0" with the bar above.
8. **Readiness, dictation accuracy:** change it to "measured on synthetic speech only (8% word errors); real voices not assessed".

## Reproduce

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd Packages/ExhibitCore
swift run exhibit-eval interpret --split heldout                         # grammar, Apple and Ollama
swift run exhibit-eval interpret --split all --only grammar,ollama --ollama-model <name>
swift run exhibit-eval speech
```

Tune only with `--split dev`. To re-render fixtures, use `agent-browser --session exhibit-spike` (open, set viewport 1280 800, screenshot). To rebuild target lists, use `exhibit targets`, then replace each file's absolute `input` path with the fixture's file name.
