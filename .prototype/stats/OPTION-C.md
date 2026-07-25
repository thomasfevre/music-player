# Option C exploration

The shared ChatGPT conversation reframed Option C. The valuable loop is not merely collecting listening totals:

1. A track starts a session and provides context.
2. The Auto-DJ proposes transitions, not absolute song ratings.
3. Completion, early skips, replays, favorites, and lightweight positive or negative feedback refine the session.
4. A Comfort, Balanced, or Discovery choice controls entropy without an accident-prone slider.
5. Sparse metadata is compensated by one audio-analysis pass at import.
6. Recommendation remains deterministic and local; audio understanding may be added separately.

The prototype therefore compares:

- **C1, Listening journal:** retrospective and easy to understand, but mostly observational.
- **C2, Taste model:** transparent and differentiating, but needs careful wording to maintain trust.
- **C3, Live session:** the daily-use product surface, with immediate control and visible recommendations.

## Feasibility-adjusted direction

Use **C3 as the product direction**, but build it as a progressive hybrid rather than making
audio analysis a prerequisite for the whole experience:

1. **Listening signals first.** Record typed local events for manual selection, natural
   completion, early and late skip, replay, favorite, and explicit positive or negative
   feedback. This is required whatever recommendation technique is chosen.
2. **Behavioral Auto-DJ.** Rank transitions with those signals, existing metadata, repetition
   avoidance, and a Comfort, Balanced, or Discovery policy. This can ship without an ML model
   and gives the cold-start limitations an honest boundary.
3. **Audio enrichment.** Analyze each file once after import, store a versioned profile
   separately from the library record, and use it to improve unknown or sparsely tagged tracks.
4. **Learned embeddings only after a device spike.** A music-specific Core ML model is
   technically plausible, but its license, conversion, app-size impact, inference time,
   thermals, and recommendation quality must be measured on real iPhones before it becomes a
   product dependency.

C2 should be a secondary explanation and correction screen. It must expose only signals the app
actually knows; opaque embedding proximity should not be presented as a precise human-readable
reason. C1 can remain a lightweight history view or an internal validation screen rather than the
main promise.

## Proposed module seams

- **ListeningHistory** records and summarizes playback events. The player emits events but owns
  no recommendation logic.
- **TrackAnalysis** exposes one small asynchronous `analyze(file:)` interface. A metadata-only
  implementation can exist before an optional Core ML implementation.
- **AutoDJ** ranks candidate tracks from a listening context, stored signals, and optional audio
  profiles. It fills the existing queue without taking over playback mechanics.

Raw embeddings and an unbounded event log should not be added to `Track` or `library.json`.
Keeping them in versioned, replaceable stores makes reanalysis and deletion cleanup local and
prevents the core library model from becoming coupled to a particular model.

## Decision gates before production

1. Instrument playback and verify on an iPhone that a natural completion, a manual skip, an
   automatic transition, a replay, and a direct selection are never confused.
2. Run a behavior-only Auto-DJ against real sessions. The first useful metric is the share of
   proposed tracks that are not skipped in their first 20 seconds, split by session mode.
3. Timebox an audio-analysis spike on 30 to 50 representative MP3s. Measure import-to-profile
   time, peak memory, energy, model size, and whether the nearest tracks feel meaningfully closer
   than a metadata-only baseline.
4. Test on the user's current iPhone and the oldest device the app still supports. Background
   execution is opportunistic on the current iOS 17 target, so analysis must be resumable and the
   app must remain useful while some tracks are still pending.
5. Clear the model and library licenses before shipping. A research model being downloadable is
   not sufficient permission to embed it in an App Store application.

If the audio spike fails, C3 still remains viable as a behavior-first Auto-DJ. If behavioral
recommendations also fail to reduce early skips after enough sessions, keep C1 as useful history
and do not promote a misleading recommendation feature.
