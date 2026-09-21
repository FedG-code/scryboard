# Scryboard

An iOS custom keyboard for searching Magic: The Gathering cards and sending their images in any messaging app, without saving anything to the photo gallery. Android planned later.

## UX model (settled 2026-09-21)

The emoji keyboard and the Tenor GIF keyboard, not a typing keyboard with a
search bar bolted on. The extension is a **card browser first**; the QWERTY is
something it can show, not what it is.

- **Grid mode is the default.** Opening the keyboard shows a search-bar pill
  across the top and a scrollable grid of card thumbnails, nothing else. No
  delete key in this mode: there is nothing to delete from, and the strip only
  cost grid space. A globe appears under the grid only on systems that do not
  draw their own (`needsInputModeSwitchKey`). With nothing typed the grid shows the user's
  **recently copied cards**; on a fresh install, before anything has been copied,
  it shows a fixed **default search** (newest set, `order:released`).
- **Tapping the search bar switches to typing mode.** The grid gives way to the
  in-extension QWERTY (`KeyboardLayout`), with a **name-suggestion strip** from
  `/cards/autocomplete` between the bar and the keys. In this mode backspace
  edits the query, not the host text. The search bar is a custom-drawn view,
  never a `UITextField`: a text field inside an extension tries to summon a
  system keyboard that cannot appear.
- **Search key, or tapping a suggestion, returns to grid mode** with results.
  Tapping a suggestion runs an exact-name search (`!"Name"`, `unique=prints`)
  so the grid shows every printing of that card — that *is* the printing picker.
- **Tap a card → `normal` JPEG to the pasteboard → toast** "Copied — tap and
  hold to paste". The grid stays put; the card joins recents.
- **Hold a card → every printing of it**, newest first, in the same grid. That
  is the printing picker; tapping a suggested name does the same.
- `screenshots/` at the repo root is gitignored: keep local screenshots there,
  never in the repo.
- **No Full Access → no network.** `hasFullAccess == false` replaces the grid
  with a short "turn on Full Access in Settings" explainer. Nothing else works
  without it, so nothing else is shown.

### Query routing under this model

- Plain text drives **two** requests: `/cards/autocomplete` (150 ms debounce)
  for the suggestion strip, and `/cards/search` (300 ms debounce) for the grid,
  because Scryfall matches bare words against card names — `lightning` returns
  every card with that word in its name, with images. `classify(_:)` and
  `SearchPipeline` currently route plain text to autocomplete only; extending
  the pipeline to also emit `.cards` for plain text is a milestone 3 task.
- Input containing `:` `<` `>` `=` or `"` goes to `/cards/search` only; the
  strip is empty for syntax queries.

## Which machine is this? (read first)

Development happens on two machines and the rules differ. Detect it, do not assume
it — this file is checked out on both:

```sh
xcode-select -p
```

- **`/Library/Developer/CommandLineTools` — the work Mac.** Swift CLI only, no
  Xcode. **Do not create, open, or modify any Xcode project, workspace, or
  `.pbxproj` file, and do not touch code signing.** Work is confined to the
  `ScryboardKit/` Swift package: `swift build` and `swift test` from
  `ScryboardKit/`. (Swift Testing is not in the Command Line Tools; if the suite
  will not link there, pin swift-testing as a test-only dependency *locally* and
  do not commit it.) Get as far as possible here and put anything that genuinely
  needs Xcode on the open-items list below rather than improvising.
- **`/Applications/Xcode.app/…` — the Mac mini.** Everything is unblocked: app
  and extension targets, signing, simulator and device testing. Xcode 27.0 as of
  2026-09-21.

## State of play

Last updated 2026-09-21.

- **Done:** milestones 1–5 in code. Milestone 2 verified on an iPad; milestone 3
  verified in the simulator; milestones 4 and 5 (image grid, tap-to-copy) are
  built and awaiting a simulator/device check.
- **Green:** 99 tests across 13 suites, no warnings, Swift 6 language mode,
  `cd ScryboardKit && swift test`.
- **Next:** verify 4 and 5 on device (paste into WhatsApp and iMessage), then
  milestone 6.
- **iOS 26 facts learned the hard way:** a height constraint on the root view is
  ignored after the first layout, so the extension uses `allowsSelfSizing` with
  the height on its own content column. The system draws its own globe and
  dictation keys under third-party keyboards (`needsInputModeSwitchKey` is
  false), so ours are hidden when that is the case.
- **Where the logic already lives**, so the Xcode targets render and nothing more:

  | Need | Already in ScryboardKit |
  | --- | --- |
  | Search bar routing | `classify(_:)`, `SearchPipeline` (debounce + cancel) |
  | Keyboard | `KeyboardLayout` (three planes, relative widths), `KeyboardState.applying(_:)` |
  | Results grid | `ResultsPager` (prefetch, single-flight, dedupe, retry) |
  | Card images | `Card.frontImageURIs`, `imageURL(_:)`, `imageURL(_:face:)` |
  | Printing picker | `ScryfallClient.printings(of:)` |
  | Empty / error / offline | `SearchOutcome.empty` vs `.failure`, `TransportFailure` |

## Core decisions (settled — do not revisit without asking)

- **Pasteboard flow, not link insertion.** Tapping a card writes the image to `UIPasteboard.general`. We do not insert Scryfall URLs as text.
- **No server component.** The keyboard talks directly to the Scryfall API. Zero backend, zero hosting costs.
- **No local card database, no offline mode.** Scryfall's server evaluates all search syntax (including `otag:`), so there is nothing to sync or bundle. The user is in a messaging context and therefore online.
- **No gallery writes, ever.** Images live in the extension's cache directory (evictable) and the pasteboard only.
- **Free forever.** Scryfall's API terms prohibit paywalling their data, and the WotC Fan Content Policy prohibits charging. No IAP, no subscriptions, no required accounts. Voluntary donation links live in the GitHub README only, not in-app.
- **Public repo.** Never commit signing material (certificates, provisioning profiles, `.p8`/`.p12` files) or a `DEVELOPMENT_TEAM`; set the team locally in Xcode.
- **iOS first, Android later.** The Kotlin client will be a port of the proven Swift client, not a parallel first draft.
- **XcodeGen generates the project.** `ios/project.yml` is the source of truth;
  the `.xcodeproj` is gitignored and regenerated with `xcodegen generate` from
  `ios/`. Never hand-edit the generated project — change the YAML and regenerate.
  XcodeGen is a developer tool only; nothing from it ships.
- **Recents, then default search** for the empty grid (see UX model).
- **Image loading and the thumbnail cache live in a second package target,
  `ScryboardUI`**, which may import ImageIO and UIKit and is shared by both app
  targets. `ScryboardKit` stays Foundation-only for the Android port.

## Repository layout

```
scryboard/
├── CLAUDE.md
├── README.md              (public-facing; contains the attribution block)
├── LICENSE                (GPL-3.0)
├── .gitignore
├── ScryboardKit/          (SwiftPM package)
│   ├── Package.swift
│   ├── Sources/ScryboardKit/        (Foundation only — portable to Kotlin)
│   │   ├── HTTPTransport.swift      (protocol + URLSessionTransport)
│   │   ├── ScryfallClient.swift     (autocomplete, search, named, paging, printings)
│   │   ├── QueryClassifier.swift    (classify(_:))
│   │   ├── SearchPipeline.swift     (debounce, cancel, SearchOutcome stream)
│   │   ├── ResultsPager.swift       (grid paging: prefetch, dedupe, retry)
│   │   ├── Keyboard/                (KeyboardLayout, KeyboardState — pure data)
│   │   └── Models/                  (Card, CardFace, ImageURIs, Layout, SearchPage,
│   │                                 SearchOptions, ScryfallError)
│   ├── Sources/ScryboardUI/         (milestone 4: ImageIO downsampling, NSCache,
│   │                                 disk cache; UIKit allowed)
│   └── Tests/ScryboardKitTests/     (+ Fixtures/, checked-in Scryfall JSON)
├── ios/
│   ├── project.yml                  (XcodeGen source of truth)
│   ├── Scryboard.xcodeproj          (generated, gitignored)
│   ├── Scryboard/                   (container app target, SwiftUI)
│   └── ScryboardKeyboard/           (keyboard extension target, UIKit)
└── android/               (future; Kotlin port of ScryboardKit + IME)
```

Build from the command line without signing:

```sh
cd ios && xcodegen generate
xcodebuild -project Scryboard.xcodeproj -scheme Scryboard \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

## ScryboardKit design

### Scryfall API contract

Base: `https://api.scryfall.com`

- Every request sends a descriptive `User-Agent` (e.g. `Scryboard/1.0 (github.com/FedG-code/scryboard)`) and `Accept: application/json`. Scryfall rejects requests without proper headers. Centralize this in one request-building path.
- Rate limit: stay well under 10 requests/second. Debouncing and request cancellation are the enforcement mechanism.
- Endpoints:
  - `GET /cards/autocomplete?q=` — name suggestions for the suggestion strip
  - `GET /cards/search?q=` — full syntax search (server evaluates `otag:`, `is:`, `cmc<=`, colors, everything); paginated via `next_page`
  - `GET /cards/named?fuzzy=` — resolve a single name to a card
- Image URIs come from the card object's `image_uris`, or `card_faces[n].image_uris` for double-faced layouts. Model both; expose a convenience that returns the front face's URIs uniformly. Sizes used: `small` (146×204, grid thumbnails) and `normal` (488×680, pasteboard copy).
- Handle Scryfall's error object (HTTP 4xx with a JSON `details` field) as a typed error, distinct from transport failures. A 404 from `/cards/named` means "no such card," not a bug.

### Async design

- `async/await` throughout; cancellation via structured concurrency (a new query cancels the previous `Task`).
- The debounce/cancel behavior lives in the client layer, not the UI, so both platforms and both iOS targets inherit it.
- All types `Sendable`-clean; the extension calls this from the main actor under strict concurrency.

### Testing

- Unit tests run with `swift test`, no simulator, no network: inject the HTTP layer via `HTTPTransport` and use canned Scryfall JSON fixtures.
- The test suite is the specification the Kotlin port will be written against. Keep fixture JSON in the repo.

## iOS app design

Single Xcode project, two targets, both depending on the local `ScryboardKit` package:

1. **Scryboard** (container app, SwiftUI) — required by Apple. Minimal but non-empty for review: onboarding (enable keyboard, Full Access, paste-permission explainer), attribution screen, optionally a card browser reusing ScryboardKit.
2. **ScryboardKeyboard** (keyboard extension, `UIInputViewController`, UIKit) — the product.

Extension facts to design around:

- A globe key is required wherever the system does not draw one (`needsInputModeSwitchKey`). In grid mode it is a lone button under the grid; in typing mode it is part of `KeyboardLayout`. Delete exists only in typing mode, where it edits the query.
- `RequestsOpenAccess` = YES in the extension Info.plist (network access requires Full Access).
- Hard memory ceiling (~60–80 MB); iOS kills the extension silently when exceeded. Downsample thumbnails at decode time via `CGImageSourceCreateThumbnailAtIndex`; `NSCache` with a count limit; never retain the full-size JPEG beyond the pasteboard write; zero third-party dependencies.
- The extension sets its own height with a constraint on `inputView`. Grid mode may be taller than typing mode; animate the change.
- Recents persist in the extension's own container (`UserDefaults` for the card list, cache directory for thumbnails). An App Group is only needed if the container app should show them too — decide in milestone 6.
- iOS 16+: first paste into each receiving app triggers a one-time system permission prompt. Expected; mention in onboarding.
- Tap action: fetch `normal` JPEG → `UIPasteboard.general.setData(_, forPasteboardType: UTType.jpeg.identifier)` → toast → release.

## Legal / attribution requirements (non-negotiable)

- In-app about screen and App Store description include: "Card data and images provided by Scryfall. Scryboard is unofficial Fan Content permitted under the Wizards of the Coast Fan Content Policy. Not approved or endorsed by Scryfall or Wizards of the Coast. Magic: The Gathering is a trademark of Wizards of the Coast LLC."
- Never display Scryfall's logo or imply endorsement. Text attribution only.
- Never crop, watermark, or alter card images; never separate art from its attribution.
- App icon and branding are original. No Magic card back, no card art, no Scryfall visual identity.
- "Magic: The Gathering" may appear in the App Store description but not in the app's name field.

## Milestones

1. ~~**ScryboardKit package**~~ — done. Client, models, routing, pipeline, pager, keyboard state; 89 tests.
2. ~~**Project skeleton**~~ — done. `ios/project.yml`, both targets build for the
   simulator, extension has globe and delete. Still to verify on a device: the
   keyboard appears in Settings and can be selected.
3. ~~**Grid mode ↔ typing mode.**~~ — done. `SearchPipeline` now has `typed(_:)`
   for keystrokes (suggestions only) and `search(_:)` / `searchExact(name:)` for
   commits.
4. ~~**Results grid**~~ — done in code. `ScryboardUI` (`ImageDownsampler`,
   `ImageStore`) + `ResultsView`/`CardCell` in the extension; paging via
   `ResultsPager`; empty state = recents (`RecentCards`) or the most popular
   cards (`game:paper` by EDHREC rank).
5. **Tap-to-copy** — done in code (`ImageStore.imageData` → `UIPasteboard`,
   `ToastView`). Still to verify: paste into WhatsApp and iMessage on a device.
   ← the "it works" moment.
6. **Container app onboarding + attribution screen.**
7. **Polish** — double-faced flip control (model side done: `Card.hasDistinctFaceImages`,
   `imageURL(_:face:)`); error and offline states rendered (`SearchOutcome`,
   `TransportFailure` already distinguish them).
8. **android/** — Kotlin port of ScryboardKit against the milestone-1 test spec; IME with Commit Content API (true image insertion, no pasteboard).

## Open items

1. **Re-verify `SearchPipeline.liveSleeper`.** The live debounce is a stored
   `static let` rather than an inline `sleep:` default argument, because an
   `await` inside a default-argument expression called across a module boundary
   aborted the process on Swift 6.2.3 ("freed pointer was not the last
   allocation"). Suite passes on Swift 6.4; the workaround has not been reverted
   yet. `realClockDebounce` in the pipeline suite is the regression guard. Do not
   reintroduce `await` into a default argument without re-testing.

2. **Measure `URLSessionTransport.makeDefaultSession()` under the extension
   memory ceiling.** Ephemeral, 10s/20s timeouts, `waitsForConnectivity` off —
   chosen on reasoning rather than measurement. Revisit in milestone 4 alongside
   the image cache.

3. **UI tests (`ios/ScryboardUITests`) are a work in progress.**
   `EnableKeyboardTests` adds the keyboard through the simulator's Settings app
   (there is no command-line way to enable a third-party keyboard) but its Full
   Access step is not yet reliable; `KeyboardSmokeTests` has not passed yet.
   They are not part of `swift test`. Run by hand with
   `xcodebuild test -only-testing:ScryboardUITests/EnableKeyboardTests`.

4. **Bundle identifiers** are placeholders (`com.fedg.scryboard`,
   `com.fedg.scryboard.keyboard`) until an App ID is registered.

When an item is done, delete it from this list rather than marking it; the list is
meant to empty out.

## Conventions

- Swift, latest stable toolchain; strict concurrency. UIKit in the extension, SwiftUI in the container app.
- No third-party dependencies without explicit discussion (the memory ceiling is the reason).
- ScryboardKit stays Foundation-only; ImageIO/UIKit code belongs in ScryboardUI or the app targets.
- Commits keep the suite green (`swift test` from `ScryboardKit/`) and both targets building.
