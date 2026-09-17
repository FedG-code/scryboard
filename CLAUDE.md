# Scryboard

An iOS custom keyboard for searching Magic: The Gathering cards and sending their images in any messaging app, without saving anything to the photo gallery. Android planned later.

**UX model:** the Tenor GIF keyboard. Search bar at the top of the keyboard, results as a scrollable grid of card thumbnails, tap a card → full image is copied to the clipboard → user long-presses and pastes into the chat. A brief "Copied — tap and hold to paste" toast confirms the copy.

## Current environment constraint (read first)

Development happens on two machines:

- **Work Mac (current):** Swift toolchain and CLI only — Command Line Tools, no Xcode. **Do not create, open, or modify any Xcode project, workspace, or `.pbxproj` file, and do not touch code signing.** All work here is confined to the `ScryboardKit/` Swift package: `swift build` and `swift test --disable-xctest` from `ScryboardKit/`. Push as far as possible here; everything that genuinely needs Xcode goes in the handoff list below.
- **Personal Mac mini (later):** Xcode work happens here — app/extension targets, signing, device testing. Milestones marked [Xcode] are blocked until then.

If asked to do [Xcode] work while the constraint above is in effect, stop and say so instead of improvising.

## Core decisions (settled — do not revisit without asking)

- **Pasteboard flow, not link insertion.** Tapping a card writes the image to `UIPasteboard.general`. We do not insert Scryfall URLs as text.
- **No server component.** The keyboard talks directly to the Scryfall API. Zero backend, zero hosting costs.
- **No local card database, no offline mode.** Scryfall's server evaluates all search syntax (including `otag:`), so there is nothing to sync or bundle. The user is in a messaging context and therefore online.
- **No gallery writes, ever.** Images live in the extension's cache directory (evictable) and the pasteboard only.
- **Free forever.** Scryfall's API terms prohibit paywalling their data, and the WotC Fan Content Policy prohibits charging. No IAP, no subscriptions, no required accounts. Voluntary donation links live in the GitHub README only, not in-app.
- **Public repo.** Never commit signing material (certificates, provisioning profiles, `.p8`/`.p12` files).
- **iOS first, Android later.** The Kotlin client will be a port of the proven Swift client, not a parallel first draft.

## Repository layout

```
scryboard/
├── CLAUDE.md
├── README.md              (public-facing; contains the attribution block)
├── LICENSE                (GPL-3.0)
├── .gitignore
├── ScryboardKit/          (SwiftPM package: Scryfall client + image cache; no UIKit)
│   ├── Package.swift
│   ├── Sources/ScryboardKit/
│   └── Tests/ScryboardKitTests/
├── ios/                   [Xcode] created later on the personal machine
│   └── Scryboard.xcodeproj
│       ├── Scryboard/            (container app target)
│       └── ScryboardKeyboard/    (keyboard extension target)
└── android/               (future; Kotlin port of ScryboardKit + IME)
```

`ScryboardKit` is platform-neutral Swift (Foundation only, no UIKit imports) so it can serve both the container app and the extension, and so its logic is portable to Kotlin later.

## ScryboardKit design (current focus)

### Scryfall API contract

Base: `https://api.scryfall.com`

- Every request sends a descriptive `User-Agent` (e.g. `Scryboard/1.0 (github.com/FedG-code/scryboard)`) and `Accept: application/json`. Scryfall rejects requests without proper headers. Centralize this in one request-building path.
- Rate limit: stay well under 10 requests/second. Debouncing and request cancellation are the enforcement mechanism.
- Endpoints:
  - `GET /cards/autocomplete?q=` — name suggestions for plain-text input
  - `GET /cards/search?q=` — full syntax search (server evaluates `otag:`, `is:`, `cmc<=`, colors, everything); paginated via `next_page`
  - `GET /cards/named?fuzzy=` — resolve a single name to a card
- Image URIs come from the card object's `image_uris`, or `card_faces[n].image_uris` for double-faced layouts. Model both; expose a convenience that returns the front face's URIs uniformly. Sizes used: `small` (146×204, grid thumbnails) and `normal` (488×680, pasteboard copy).
- Handle Scryfall's error object (HTTP 4xx with a JSON `details` field) as a typed error, distinct from transport failures. A 404 from `/cards/named` means "no such card," not a bug.

### Query routing

The search bar routes input by shape:

- Plain text (no syntax operators) → `/cards/autocomplete`, fired per keystroke (it is built for this).
- Input containing any of `:` `<` `>` `=` or quotes → `/cards/search`, debounced ~300 ms, with in-flight request cancellation on new input.

Implement routing as a pure function `classify(query) -> .autocomplete | .search` with exhaustive unit tests — this logic ports directly to Kotlin.

### Async design

- `async/await` throughout; cancellation via structured concurrency (a new query cancels the previous `Task`).
- The debounce/cancel behavior lives in the client layer, not the UI, so both platforms and both iOS targets inherit it.
- All types `Sendable`-clean; the extension will call this from a UI context under strict concurrency.

### Testing

- Unit tests run with `swift test`, no simulator, no network: inject the HTTP layer via a protocol (e.g. `HTTPTransport`) and use canned Scryfall JSON fixtures (a normal card, a double-faced card, a search page with `next_page`, an error object).
- The test suite is the specification the Kotlin port will be written against. Keep fixture JSON in the repo.

## iOS app design (deferred, [Xcode])

Single Xcode project, two targets:

1. **Scryboard** (container app) — required by Apple. Minimal but non-empty for review: onboarding (enable keyboard, Full Access, paste-permission explainer), attribution screen, optionally a card browser reusing ScryboardKit.
2. **ScryboardKeyboard** (keyboard extension, `UIInputViewController`) — the product. UIKit.

Extension facts to design around:

- Extensions cannot summon the system keyboard for their own text fields → render a minimal custom QWERTY in-extension for the search bar. Globe and delete keys are required.
- `RequestsOpenAccess` = YES in the extension Info.plist (network access requires Full Access).
- Hard memory ceiling (~60–80 MB); iOS kills the extension silently when exceeded. Downsample thumbnails at decode time via `CGImageSourceCreateThumbnailAtIndex`; `NSCache` with a count limit; never retain the full-size JPEG beyond the pasteboard write; zero third-party dependencies.
- iOS 16+: first paste into each receiving app triggers a one-time system permission prompt. Expected; mention in onboarding.
- Tap action: fetch `normal` JPEG → `UIPasteboard.general.setData(_, forPasteboardType: UTType.jpeg.identifier)` → toast → release.

## Legal / attribution requirements (non-negotiable)

- In-app about screen and App Store description include: "Card data and images provided by Scryfall. Scryboard is unofficial Fan Content permitted under the Wizards of the Coast Fan Content Policy. Not approved or endorsed by Scryfall or Wizards of the Coast. Magic: The Gathering is a trademark of Wizards of the Coast LLC."
- Never display Scryfall's logo or imply endorsement. Text attribution only.
- Never crop, watermark, or alter card images; never separate art from its attribution.
- App icon and branding are original. No Magic card back, no card art, no Scryfall visual identity.
- "Magic: The Gathering" may appear in the App Store description but not in the app's name field.

## Milestones (reordered)

1. ~~**ScryboardKit package**~~ — **done.** HTTP transport protocol + live URLSession implementation with mandatory headers; card/search/autocomplete/error models incl. `card_faces`; query classification; debounced, cancellable search pipeline; 55 tests across 8 suites with checked-in fixtures, green and warning-free.
2. **[Xcode] Project skeleton** — container app + extension targets; keyboard selectable in Settings; globe/delete work; ScryboardKit added as a local package dependency to both targets.
3. **[Xcode] In-keyboard QWERTY + search field** wired to ScryboardKit.
4. **[Xcode] Results grid** with downsampled thumbnails and memory-safe scrolling.
5. **[Xcode] Tap-to-copy** with toast; verify paste into WhatsApp and iMessage end-to-end on device. ← the "it works" moment.
6. **[Xcode] Container app onboarding + attribution screen.**
7. **Polish** — the logic is done in ScryboardKit; what remains is [Xcode] UI.
   - ~~printing selection~~ — `ScryfallClient.printings(of:)`, matched on
     `oracle_id` with an exact-name fallback, newest printing first.
   - ~~error/empty/offline states~~ — `SearchOutcome` separates `.empty` from
     `.failure` (Scryfall reports "nothing matched" as a 404, which must not read
     as an error), and `TransportFailure` separates offline from timed out.
   - double-faced card flip — model side done (`Card.hasDistinctFaceImages`
     gates the affordance, `imageURL(_:face:)` feeds both the grid and the
     pasteboard write); the flip control itself is [Xcode].
8. **android/** — Kotlin port of ScryboardKit against the milestone-1 test spec; IME with Commit Content API (true image insertion, no pasteboard).

## [Xcode] Handoff list — do these on the Mac mini

Everything deferred or worked around because this machine has no Xcode. Work
through it before starting milestone 2.

1. **Delete the swift-testing dependency from `ScryboardKit/Package.swift`** — the
   `dependencies:` block and the matching `.product(name: "Testing", …)` line in
   the test target. Command Line Tools ship neither XCTest nor Swift Testing, so
   the suite had nothing to link against here; Xcode bundles its own copy and the
   two collide. Once it is gone, plain `swift test` works and the project is back
   to zero dependencies. The test source needs no changes — it is already written
   against Swift Testing.

2. **Re-verify `SearchPipeline.liveSleeper`.** The live debounce is a stored
   `static let` rather than an inline `sleep:` default argument, because an
   `await` inside a default-argument expression called across a module boundary
   aborts the process in the concurrency task allocator ("freed pointer was not
   the last allocation") on Swift 6.2.3. If a later toolchain fixes it, the
   workaround can be reverted — `realClockDebounce` in the pipeline suite is the
   regression guard. Do not reintroduce `await` into a default argument.

3. **Decide where the image cache lives.** The repository layout above calls
   `ScryboardKit` "Scryfall client + image cache", but the conventions keep it
   Foundation-only, and downsampling needs `CGImageSourceCreateThumbnailAtIndex`
   from ImageIO. ImageIO is not UIKit and is available on both platforms, so
   either relax the rule for ImageIO or put the cache in the extension target.
   Nothing in milestone 1 depends on the answer; milestone 4 does.

4. **Check `URLSessionTransport.makeDefaultSession()` under the extension memory
   ceiling.** It is ephemeral with 10s/20s timeouts and `waitsForConnectivity`
   off, chosen on reasoning rather than measurement.

5. **Milestones 2–6** as listed above — targets, signing, device testing.

## Conventions

- Swift, latest stable toolchain; strict concurrency. UIKit in the extension.
- No third-party dependencies without explicit discussion (the memory ceiling is the reason).
- ScryboardKit stays Foundation-only; anything importing UIKit belongs in the app targets.
- Commits keep the suite green: `swift test --disable-xctest` from `ScryboardKit/` (see the handoff list for why the flag is needed).
