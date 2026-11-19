# Unit 7 live checklist

Everything in unit 7 (dictation, the typed instruction field, and the free-form model setting from issue 11) that only a person at a Mac can check. The package tests (`DictationSessionTests`, `DictationInterpretingTests`, `InstructionEquivalenceTests`, `ModelSettingsTests`), lint, the Debug build, the app tests and the offscreen renders in `docs/samples/app/editor-*.png` and `settings-free-form-*.png` passed. They use a fake transcriber and fake models. **Nothing below has been run**: no microphone was used, no permission was asked for, and the app was never launched.

Build and sign as in `docs/product/unit4-live-checklist.md`. A signed build matters here: the microphone needs the `com.apple.security.device.audio-input` entitlement under the hardened runtime, and an unsigned build may be refused the microphone without a prompt.

Write down the macOS version and the Mac for every run. Speech uses `SpeechAnalyzer` on macOS 26 and later and `SFSpeechRecognizer` (on-device only) on macOS 14 to 25, so run the whole list once on each if you can.

Use a page with an email address, a made-up API key, a button and a few words, for example a settings page on a test account with `example.com` addresses.

## 1. First dictation and permissions

| Step | Expected |
|---|---|
| Fresh install (or `tccutil reset Microphone com.exhibitaformac.ExhibitA` and `tccutil reset SpeechRecognition com.exhibitaformac.ExhibitA`), launch, open Settings | No microphone or speech prompt at launch, at the first capture, or when the editor opens. |
| Open the editor on a capture and hold D | macOS asks for the microphone once, with the text "Exhibit A listens only while you hold D in the editor...". The status strip shows "Getting the microphone ready". |
| macOS 14 to 25 only | A second prompt for speech recognition, with "Exhibit A turns what you say while holding D into text, on this Mac only...". |
| macOS 26 only | Note whether a speech recognition prompt appears too. The code does not ask for it on 26 (the spike needed none for files). If live microphone transcription fails without it, that is a bug to file. |
| Allow, still holding D or not | If D was released during the prompt: "Ready. Hold D and speak." and nothing is listening. |
| Hold D again and say "blur the emails" | Red light and "Listening", then the words as they are heard. Release: a short "Working", then "“blur the emails” Blurred 1 email." and the blur is on the canvas. |
| ⌘Z once | The whole batch goes. |

## 2. Denial and availability

| Step | Expected |
|---|---|
| Deny the microphone (System Settings, Privacy & Security, Microphone, off), hold D | "Exhibit A can't use the microphone. Allow it in System Settings, or press / to type." with an "Open System Settings" key that opens the Microphone pane. B, A and the other keys still work. |
| macOS 14 to 25: deny speech recognition, hold D | "Speech recognition is off for Exhibit A..." with a link to the Speech Recognition pane. |
| Unplug or disable every microphone (a Mac mini with none), hold D | "No microphone is connected. Press / to type instead." |
| Set the Mac's language to one without on-device recognition (macOS 14 to 25), hold D | "On-device speech isn't available for ... on this Mac, and Exhibit A never sends audio off it." Watch Little Snitch or `nettop` if available: no connection to Apple's speech servers. |
| macOS 26, a language whose model is not installed | "Downloading the speech model, N%. Esc cancels." with the percentage moving. Esc: "Download cancelled. Hold D to try again." Hold again and let it finish: listening starts if D is still held, otherwise "Ready. Hold D and speak." Note how long the download took and its size (not measured yet). |

## 3. The voice table, timed (acceptance)

The spec's budget is 1.5 s from releasing D to marks on the grammar path, for a five-second sentence. Use a stopwatch, or a screen recording at 60 fps and count frames from the key-up to the marks. Say each row three times; write down every time and whether the result was right.

| Say | Expected | Times (s) | Right? |
|---|---|---|---|
| "Blur the emails" | Every email blurred, summary names the count | | |
| "Circle Pricing and point at Sign up" (on a page with both) | Circle on "Pricing", arrow to "Sign up" | | |
| "Highlight this" with the pointer resting on a line | That line highlighted; move the pointer away before releasing D and it still uses where the pointer was at key-down | | |
| "Circle the avatar" | With no model: "Needs a model" and nothing changes (nothing else in the sentence was understood). With a model: "Couldn't find: avatar." | | |
| "Blur the emails and circle the logout button" with no model and no "Logout" on screen | Emails blurred, "Couldn't find: logout button." | | |
| A five-second sentence: "blur the emails and the keys and circle update plan" | All three marks, one ⌘Z removes them | | |

Also:

- Hold D, say nothing, release: nothing at all happens.
- Hold D, say something, press Esc before releasing: "Dictation cancelled", nothing changes.
- Hold D for a long time: the key repeat does not restart listening or flicker the status.
- Hold D and switch to another app with ⌘Tab before releasing: listening stops (the editor stops on losing key focus).
- Start a text label (T, click), type "dad": the label reads "dad"; nothing starts listening.
- Mouse: press and hold the D plate in the toolbar, speak, let go: same as the key.
- Noisy room (music or a fan): note the word errors and whether the grammar still reads the instruction. The spike's mis-hearings ("appointed update plan" for "point at Update plan", "point it" for "point at") are worth trying on purpose.
- Names on the screen ("Watanabe", product names): are they heard as written? The screen's text lines are passed to the recognizer as hints.

## 4. The typed instruction field

| Step | Expected |
|---|---|
| Press / | The status strip becomes a text field with "Type what to change...", focused. |
| Type "circle update plan", ↩ | Same path as speech: the circle, then the summary. |
| Press /, then Esc | The field closes; the window does not. |
| On a keyboard layout where / needs ⇧ (German: ⇧7) | ⇧ and the / key opens the field. |

## 5. The model path (issue 11)

| Step | Expected |
|---|---|
| Settings, Instructions in your own words, with Ollama running and never chosen (issue 96) | The Model menu lists Ollama's models with `qwen3.8:27b (recommended)` selected; "Using qwen3.8:27b from Ollama on this Mac." No click needed; an editor uses it. |
| Quit Ollama, Check Again | "No model server is running on this Mac..." with `ollama pull qwen3.8:27b` and a copy button that copies it. Start Ollama, Check Again: back to "Using ...". |
| Choose ornith-1.5:9b, reopen Settings | Still ornith-1.5:9b: a choice is never replaced by the default. |
| Choose None, then say or type "hide anything that identifies the customer" | "Needs a local model: choose one in Settings, or try “blur the emails”." and a Settings key that opens Settings. Nothing changes. |
| Choose a model, press Test with Ollama running | "Reachable. ... answered in N s, loading included if it wasn't loaded." Write down N cold and warm. |
| Other, model name with a typo, Test | "The server is running but has no model called ...". |
| Other, endpoint http://192.168.1.20:11434 | "The model endpoint must be on this Mac ...; 192.168.1.20 is not, so nothing was sent." Test is off, and nothing is sent (check with Little Snitch or `nettop`). |
| With a model chosen, stop Ollama, Check Again | "Ollama isn't answering, so ... can't be used. Open Ollama, or start it:" with `ollama serve` to copy. |
| Ollama running, say "hide anything that identifies the customer" | "Asking the local model. This can take several seconds." then each mark named and "Check it; ⌘Z undoes all of it." Time it; model-latency.md expects 5 to 8 s on a new screen with a 27B model. |
| While the model works, hold D or type another instruction | "Still working on the last instruction. Try again when it finishes." Only the first instruction's marks appear. |
| While the model works, close the window | No marks are added after closing; reopen from history to check. |
| Stop Ollama, say the same | "The local model isn't answering. Is it running? No changes made." |
| LM Studio or llama.cpp on a /v1 URL, if installed | Test and an instruction both work. Not checked by anyone yet. |

## Open question

WhisperKit for macOS 14 and 15 was not added. `SFSpeechRecognizer` with on-device recognition is the path there, and whether its accuracy and the 1.5 s budget hold on those systems is unknown until this list is run on one.
