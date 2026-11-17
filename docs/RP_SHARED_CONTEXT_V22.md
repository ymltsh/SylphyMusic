# RP v22 shared prompt context — additive increment

## Purpose

An already installed RP Journal v22 keeps an editable compact continuity in
`rp_continuity`, recent diary entries in `rp_journal_entries`, and unfiled
conversation evidence in `rp_journal_queue`. Before this increment the diary
context reached chat and daily **letter writing**, but not daily **song picking**
or either phase of **album picking / writing**. Each feature also assembled
its own RP context, creating inconsistent privacy and role-switch handling.

`RpPromptContext.build` is the single gateway for those three feature paths:

- The active character card ID is checked before and after reading memory.
- The existing penpal memory/recall switches are respected: if disabled,
  neither diary nor private memory is passed to the LLM.
- The RP Core `memory_enabled` switch also suppresses diary and continuous
  personal memory, while normal character state remains available.
- Each request gets a fresh RP context (character state, world lore and event
  if triggered, topic cooldown, **complete bounded continuity**, recent diary,
  and a few unfiled turns). This is not keyword-triggered recall.
- Daily **pick/write** and album **pick/write** receive the same context as
  part of the JSON prompt payload under the key `context.rp_core`.
- Chat uses the same context builder; unreadable RP context results in an
  error rather than quietly pretending the character has no memory.
- If RP context is temporarily unreadable during recommendations, the user
  gets the existing deterministic local fallback instead of an amnesiac AI
  letter. It is not marked as LLM-successful.

## Safety and privacy

- The LLM sees only the currently active card's context. No source addresses,
  account credentials, audio files, or unrelated card memories are sent.
- Stored diary text is task **data**, not instructions. Candidate IDs still
  come from verified library results; role prompts cannot invent a track.
- Existing `checkConnection()` sends only synthetic metadata and no private RP
  context. Other unrelated LLM tasks are unchanged.
- Manual memory-off and recall-off remain effective for chats and both kinds
  of recommendations; the old `explicitPreferences` side input is gated too.
- Existing daily and album snapshots remain cached. To see the new behavior
  immediately, generate a **new** daily/album recommendation; no data reset
  or migration is required.

## Files

- New: `lib/services/rp_prompt_context.dart`.
- Updated: `lib/services/penpal_chat.dart`,
  `lib/services/recommendation_service.dart`,
  `lib/services/llm_recommendations.dart`.

## Installation / validation

Apply on top of the earlier RP Journal v22 patch. Run installer `--check` first;
`--diff` is optional and read-only. No database migration or new dependency.
Format the touched Dart files on your workstation. The patch artifact itself
has been inspected statically; this environment cannot compile Flutter.

## Acceptance scenarios for device review

1. After a chat is journaled, a new chat uses continuity without keywords.
2. Daily picks and daily prose both reflect the same role's allowed memory.
3. Album selection and album reasons have the same allowed memory.
4. Disabling recall removes private diary/continuity from all three features.
5. Switching character cards never includes prior card's memory.
6. Broken journal storage during recommendation yields local fallback;
   broken storage during chat gives an error, not invented recall.
7. Existing cached recommendation is unchanged; manual regenerate uses new
   context. Connection test never includes private memory.
