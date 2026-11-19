# Second held-out set

`instructions-heldout2.json` holds 36 instructions (split `heldout2`) for the unit 8 acceptance run (issue 11). The first held-out half in `instructions.json` has been seen, so this set replaces it as the measure of the bar in `docs/product/spike-interpreter.md`.

## Who may read it, and when

- Read it only to run the single final unit 8 evaluation, with the grammar and the shipping prompt frozen first.
- Do not read the instructions or expectations while writing or tuning the grammar, the prompt or the target listing. Tune on `--split dev` in `instructions.json` only.
- Run it once. If unit 8 code changes after that run, the set has been seen and a new one is needed for any later claim.
- The author wrote it without reading `ExhibitInterpret`, the model prompt, the spike's failure notes or any results, and never ran an interpreter on it.

## Fixtures

Three new screens, rendered like the first ten (headless `agent-browser`, 1280 by 800; targets from the real `exhibit targets`, `input` set to the file name):

- `calendar`: a week view with an event detail panel. "Interview Talia Brooks" wraps onto two lines in the grid, and "1:1 Rafael Ortiz" appears twice.
- `crm`: a contact record whose name recurs inside activity lines, two phone numbers, and an email shown twice.
- `ticket`: a support ticket where the customer pasted a key and a card number, with the customer's name in five places.

20 instructions use the new screens and 16 use the existing ten (every one of them at least once).

## Mix

| Category | Count | Ids |
|---|---|---|
| Redaction by kind or literal text | 10 | calendar-01, calendar-02, crm-01, ticket-01, ticket-02, billing-01, inbox-01, terminal-01, editor-01, chat-01 |
| Single non-redaction mark by text | 8 | calendar-03, crm-02, ticket-03, ticket-04, dashboard-01, pricing-01, login-01, team-01 |
| Several operations in one sentence | 6 | calendar-04, crm-03, ticket-05, billing-02, inbox-02, team-02 |
| Semantic or vague | 5 | calendar-05, crm-04, ticket-06, terminal-02, table-01 |
| Not on the screen | 4 | calendar-06, crm-05, ticket-07 (half present), dashboard-02 |
| Pointer | 3 | calendar-07, ticket-08, chat-02 |

Ids above drop the `h2-` prefix. The categories overlap only through tags: crm-03 and ticket-01 also redact, ticket-07 is also a multi-operation sentence.

Nine instructions read as speech to text would deliver them, lowercase with no punctuation and one mis-hearing each (tag `speech`): "re schedule", "priscilla vans", "reply do in 42 min", "merch" for Merge, "for word" for Forward, "build 01" for build-01, "lucia marino", "arrow hear", "active uses".

## Decisions on ambiguous cases

- **Names that wrap** (calendar-01): "blur talia brooks" expects both halves of the wrapped event ("Interview Talia" and "Brooks") as well as every line containing the full name. A substring match alone misses the wrapped event, which would leave the name readable; that is scored as a miss. Blurring her email too is an accepted alternative.
- **Names inside longer lines** (crm-01, ticket-02, inbox-01, chat-01): the expectation is every line containing the name. Accepted extras: the person's email (crm-01, ticket-02, inbox-01), the first-name-only "Thanks Priscilla." line (ticket-02), and the "LM" avatar initials (chat-01).
- **The literal "build-01"** (terminal-01) is said as "build 01"; the expectation is the four prompt lines containing it, not the "deployadb" lines.
- **"Hide this"** (calendar-07) on "Organizer: Rafael Ortiz" counts as a blur of that line.
- **Label or value**: "circle active uses" accepts the label, the value or both; "highlight the deal value" accepts the amount alone or with its "Value" label; "circle where the lead came from" accepts "Webinar" alone or with "Lead source"; "box the biggest account" (highest MRR, Ember Health at $1,980) accepts the name, the amount or both.
- **"Blur everything the customer pasted that they shouldn't have"** (ticket-06) is the key and the card only. The email and phone were shared on purpose, so blurring them is over-redaction, which the bar reports but allows.
- **"Blur the customer emails"** on the dashboard (no email targets) expects not found and nothing blurred.
- **"Highlight the refund amount and box merch"** expects the box on Merge and not found for the refund amount.

## Wiring

`exhibit-eval` reads only `instructions.json` today. The loader must learn to read this file (and its `heldout2` split) before the unit 8 run; that change is not made here.
