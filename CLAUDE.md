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
  in-extension QWERTY (`KeyboardLayout`). The letters plane carries a **syntax
  row** above the letters, `: < > = " ! - ( ) /`, like the iPad number row, so
  a normal query never leaves the plane. The space bar is unlabelled and the
  commit key is a return symbol, as on the system keyboard. In this mode
  backspace edits the query, not the host text. The search bar is a
  custom-drawn view, never a `UITextField`: a text field inside an extension
  tries to summon a system keyboard that cannot appear. It has a real caret:
  tapping the text puts it in the nearest gap between letters and dragging
  slides it, so typing and backspace happen there, not only at the end
  (`QueryBuffer` in the Kit holds text and caret; added 2026-09-22).
- **No suggestion strip.** The name-suggestion strip from `/cards/autocomplete`
  was removed on 2026-09-22 (the developer disliked it and it cost grid room).
  Keystrokes send nothing; only the return key does. `SearchPipeline.typed(_:)`
  stays in the Kit for the Android port and the container app.
- **The return key returns to grid mode** with results from `/cards/search`.
- **The last search survives keyboard rebuilds, scroll position included.**
  The host tears the extension down on every dismissal, and pasting dismisses
  it, so `SavedSearch` keeps the committed query (or held card name) and the
  index of the top visible card in `UserDefaults` for ten minutes after the
  last activity, and `SavedResults` writes every page the pager loaded to one
  file in the caches directory (`ResultsPager.snapshot`). On launch the grid
  comes back from that file at the same card with no request and keeps paging
  from where it stopped; if the file was purged the query is run again. The
  clear button in the pill removes both. Positions are indices, not offsets,
  so a change of card size does not lose the place.
- **Tap a card → `normal` JPEG to the pasteboard → toast** "Copied". Just that
  word: the longer "tap and hold to paste" read as an instruction for the
  keyboard itself and confused. The grid stays put; the card joins recents.
  A **copy format** setting in the container app (`CopyFormat`, added
  2026-09-23) can swap the image for the card's Scryfall page (`scryfall_uri`,
  written as both URL and text) or plain text: the card name, or from the
  printings view the decklist line `Name (SET) number` (`Card.decklistLine`
  in the Kit, tested). Image is the default; the toast then says "Link
  copied" / "Name copied".
- **Hold a card → every printing of it**, newest first, in the same grid. That
  is the printing picker; tapping a suggested name does the same.
- `screenshots/` at the repo root is gitignored: keep local screenshots there,
  never in the repo. `docs/prototypes/` holds HTML mock-ups of UI options that
  were compared before a decision; thumbnails there hotlink Scryfall, never
  embed images.
- **No Full Access → no network.** `hasFullAccess == false` replaces the grid
  with a short "turn on Full Access in Settings" explainer. Nothing else works
  without it, so nothing else is shown.

### Query routing under this model

- The keyboard sends one request, `/cards/search`, when the return key is
  pressed. Scryfall matches bare words against card names, so `lightning`
  returns every card with that word in its name; no translation is needed.
- `classify(_:)` and `SearchPipeline.typed(_:)` still route plain text to
  `/cards/autocomplete`; nothing in the extension calls them any more.

## Machine and devices

Development is on the Mac mini only (Xcode 27.0 as of 2026-09-21); the
earlier Command-Line-Tools-only work Mac is retired, so there is no machine
check to run. Everything is unblocked: app and extension targets, signing,
simulator, archives and TestFlight uploads.

- **The developer's iPhone cannot connect to the Mac mini** (its USB port is
  broken). It gets builds through TestFlight only. Anything that needs a cable
  — Instruments, device logs, Xcode debugging — happens on the **iPad Pro**,
  which does connect. Keep the iPad in mind for the memory pass.

## State of play

Last updated 2026-09-23, polish pass.

- **Done:** milestones 1–5, verified end to end on the developer's iPhone via
  TestFlight on 2026-09-22: search, grid, tap-to-copy, and paste into a real
  chat all work. The "it works" moment has happened.
- **TestFlight:** build 1.0 (1) uploaded 2026-09-21 and available; an internal
  group exists with the developer in it, installing on their iPhone on
  2026-09-22. See "Distribution".
- **Green:** 116 tests across 15 suites, no warnings, Swift 6 language mode,
  `cd ScryboardKit && swift test`.
- **Polish list from the first phone session (agreed 2026-09-22).** Work it in
  this order; details were settled with the developer, do not re-ask:
  1. ~~Key labels sat at the top of every key until pressed~~ — fixed: keys
     are a hand-laid-out `UIControl`, not a configuration `UIButton`. Awaiting
     confirmation on the phone.
  2. ~~Caret sat too far right of the last letter~~ — fixed: custom stack
     spacing after the label. Awaiting confirmation on the phone.
  3. ~~Search reset to recents after every copy/paste or dismissal~~ — done via
     `SavedSearch`, ten-minute lifetime. Since 2026-09-22 the loaded pages
     and scroll position are restored from disk too (see the UX model).
  4. ~~Suggestion strip out, syntax row in~~ — done (letters plane only; no
     tokens like `t:` for now). Rows shrank a little to fit; revisit if it
     feels cramped.
  5. ~~Smaller key glyphs, unlabelled space bar, return symbol for search~~ —
     done, awaiting confirmation.
  6. ~~Way back out of the printings view~~ — done 2026-09-22 with option B, a
     floating "Back" capsule bottom-right over the grid, shown only while
     printings fill it. The pill keeps the query the user typed; Back re-runs
     it (or shows the empty state if nothing was typed). One level of history.
     `SavedSearch` stores query and printings name together, so a restored
     keyboard comes back in the printings view with Back still available. The
     developer is gathering feedback; options A (header row above the grid)
     and C (chevron in the pill) live in `docs/prototypes/printings-back.html`
     with a tab switcher, open it in a browser to compare.
  7. ~~Sort order setting in the container app~~ — done 2026-09-22. All
     fifteen Scryfall orders plus direction, default EDHREC rank / automatic,
     in `Preferences` (ScryboardUI) stored in the App Group
     `group.com.fedg.scryboard` via `PreferencesStore`. Typed searches only;
     the empty grid keeps `game:paper` by EDHREC. A query containing `order:`
     (or `direction:`/`dir:`) sends no `order=`/`dir=` parameter; see
     `specifiesOrder(_:)` in the Kit and its tests. The extension re-reads
     preferences on every appearance. Awaiting a phone check.
  8. ~~Card size setting: small / medium / large~~ — done 2026-09-22, both
     routes: a segmented control in the app and a pinch on the grid (one step
     per pinch, saved to the same preference). Keyboard height unchanged;
     target cell widths 88 / 118 / 172 pt give 4 / 3 / 2 columns on a phone.
     Every size loads the `normal` scan (decided 2026-09-22 after a long
     scroll through `t:creature` on large cells ran clean), decoded at cell
     size, so memory per thumbnail is bounded by the cell, not the scan; the
     thumbnail cache's 24 MB cost limit bounds the total. **Still to
     measure** in Instruments on the iPad: the extension's resting memory
     plus a fast scroll through a big result set, before external testing.
  9. Landscape checked on the phone 2026-09-22: fine. Dark mode: fine.
  11. ~~Grid returned to the top after a dismissal or after Back from
     printings~~ — done 2026-09-22. Rebuilds restore pages and position from
     `SavedResults`; Back restores the grid the controller kept in memory
     (`gridBeforePrintings`, one level) and the pipeline's `drop()` cancels
     the printings request without reporting idle. Awaiting a phone check.
  10. ~~No way to move the caret to fix a typo mid-query~~ — done 2026-09-22.
     `QueryBuffer` (Kit, tested) keeps text plus caret offset; the pill draws
     the caret at the measured position, moves it on tap or drag, and scrolls
     a long query to keep it in view. Awaiting a phone check.
  12. ~~Container app raised the keyboard on open, hiding the settings, and
     nothing dismissed it~~ — moot since 2026-09-23: the text field itself
     was removed (see Core decisions).
  13. ~~Copy format setting: image / Scryfall link / text~~ — done 2026-09-23
     (see the UX model). The printings-view text format is a proposal,
     `Name (SET) number`, awaiting the developer's verdict; it is one
     property in the Kit to change. `Preferences` now decodes missing keys
     to their defaults, so adding a field never resets saved settings.
- **Being designed (2026-09-23): a query builder in place of recents.** The
  developer finds the recents empty state worthless and wants the keyboard
  to open on a builder for Scryfall syntax aimed at beginners: pick a filter
  (colour identity, colour, type, mana value, rarity, format, power,
  toughness, keyword, card text), then an operator in words ("fits within",
  "at least"), then a value, with a plain-language sentence and the raw
  syntax shown before Add appends the clause to the pill. Add never sends a
  request; Search does. Settled so far: one step at a time (crumbs, no
  numbering, operator step hidden when the filter has only one), no clause
  tokens under the pill, plain W U B R G letters with no colour tint,
  numbers 0–9 only, no `is:` filters, and "card text" hands off to the
  QWERTY with `o:""` in the pill and the caret between the quotes. Colour
  and identity never emit a bare colon because on Scryfall `c:` means `>=`
  and `id:` means `<=` (checked against the API). Also agreed: move `:` to
  the centre of the syntax row, wider. Typing mode returns to the builder
  with a sliders key on the QWERTY's bottom row between `123` and the globe,
  drawn like every other function key (chosen 2026-09-23 over a pill icon
  and a swipe); the space bar gives up the width. Mock-up in
  `docs/prototypes/query-builder.html`.
  Recents will be removed when this ships; the pill's clear button returns
  to the builder. Plan: a tested `QueryClause` type in ScryboardKit, a
  builder view in the extension.
- **Next, after the polish list:**
  1. Milestone 6: container app onboarding (enable keyboard, Full Access and
     why the system warning is scary, the one-time paste permission) and the
     attribution screen. The bones exist in `ios/Scryboard/ContentView.swift`.
     Decided 2026-09-22: the container app will **not** show recents, so
     recents stay in the extension's own defaults and the App Group carries
     settings only.
  2. Milestone 7 polish: double-faced **flip in the grid** (decided
     2026-09-22; copying sends the face currently shown), designed
     empty/offline/error states, sharper thumbnails on iPad (small scan is
     stretched there), Instruments memory pass against the extension ceiling
     on the iPad over cable.
  3. App icon: the developer is having one made externally (2026-09-22); the
     flat placeholder made in code stays until it arrives. Then the store
     listing.
- **iOS 26 facts learned the hard way:** a height constraint on the root view is
  ignored after the first layout, so the extension uses `allowsSelfSizing` with
  the height on its own content column. The system draws its own globe and
  dictation keys under third-party keyboards (`needsInputModeSwitchKey` is
  false), so ours are hidden when that is the case.
- **Simulator tips:** press ⌘⇧K in the simulator to toggle the software keyboard
  (a connected hardware keyboard hides every software keyboard, ours included).
  Third-party keyboards cannot be enabled from the command line; add Scryboard
  in the simulator's Settings app after each reinstall. iOS 26 hosts the
  simulator in a process called DeviceHub, not Simulator.app.
- **Working style that suits the developer:** they are new to Xcode and test on
  a real device or the simulator themselves. Give short, numbered GUI steps.
  Do not spend long stretches on automation detours (the UI-test harness cost
  twenty minutes with nothing visible); ask them to try it and report instead.
  Never `rm` with globs in shared folders; write to fresh per-run directories.
- **Where the logic already lives**, so the Xcode targets render and nothing more:

  | Need | Already in ScryboardKit / ScryboardUI |
  | --- | --- |
  | Search bar routing | `SearchPipeline.search(_:)`, `.searchExact(name:)` (`.typed(_:)` is unused by the extension) |
  | Keyboard | `KeyboardLayout` (three planes, relative widths), `KeyboardState.applying(_:)`, `QueryBuffer` (text + caret) |
  | Results grid | `ResultsPager` (prefetch, single-flight, dedupe, retry, `snapshot` for restore) |
  | Card images | `Card.frontImageURIs`, `imageURL(_:)`, `imageURL(_:face:)`; `ImageStore`, `ImageDownsampler` |
  | Printing picker | `searchExact(name:)` fills the grid with every printing |
  | Empty / error / offline | `SearchOutcome.empty` vs `.failure`, `TransportFailure` |

## Core decisions (settled — do not revisit without asking)

- **Pasteboard flow, not link insertion.** Tapping a card writes the image to `UIPasteboard.general`. We do not insert Scryfall URLs as text.
  Re-verified 2026-09-23 against the iOS 26 SDK (Xcode 27) after testers
  asked for one-tap paste: `UITextDocumentProxy` can only `insertText`,
  `deleteBackward`, move the caret and set marked text. There is no image or
  attachment insertion for keyboard extensions, which is why GIPHY, Tenor and
  Gboard all copy to the clipboard too. The only true image insertion API is
  `MSConversation.insertAttachment` in an iMessage app extension, Messages
  only. Android's `InputConnection.commitContent` is the real thing.
  **Drag and drop works, though:** tested on the iPad 2026-09-23, a card
  dragged out of the grid lands in the host as the `normal` JPEG (the
  Scryfall page URL rides along for targets that take links). The grid is a
  `UIDragInteraction` of its own (the collection view's drag delegate never
  reports how a drop ended), enabled on iPhone too. On the Image setting the
  drag carries the JPEG plus the clean page link (`Card.pageURL`, no
  `utm_source`) so a field that takes no images gets the link; the receiver
  chooses, and WhatsApp takes the link in its text box and the image in the
  chat. Link and Text settings drag one thing. An accepted drop joins
  recents; a refused one shows nothing. Hold for printings is 0.7 s, fires
  while the finger is down, cancels the drag lift (which comes at about
  0.5 s) by toggling the interaction off for a run-loop turn, and is
  disabled in the printings view. Moving before 0.7 s drags. Phone check of
  the lift cancel pending.
- **The container app has no "try it" text field.** One existed for a few
  hours on 2026-09-23 (a `UITextView` that took image pastes); the developer
  removed it because people try the keyboard in a real chat anyway, and a
  field in the settings screen taught nothing. Do not bring it back.
- **No server component.** The keyboard talks directly to the Scryfall API. Zero backend, zero hosting costs.
- **No local card database, no offline mode.** Scryfall's server evaluates all search syntax (including `otag:`), so there is nothing to sync or bundle. The user is in a messaging context and therefore online.
- **No gallery writes, ever.** Images live in the extension's cache directory (evictable) and the pasteboard only.
- **Free forever.** Scryfall's API terms prohibit paywalling their data, and the WotC Fan Content Policy prohibits charging. No IAP, no subscriptions, no required accounts. Voluntary donation links live in the GitHub README only, not in-app.
- **Public repo, Apache-2.0** (switched from GPL-3.0 on 2026-09-22 so outside
  contributions carry a built-in patent and contribution grant and nothing
  conflicts with App Store terms). Never commit signing material (certificates, provisioning profiles, `.p8`/`.p12` files) or a `DEVELOPMENT_TEAM`; set the team locally in Xcode.
- **iOS first, Android later.** The Kotlin client will be a port of the proven Swift client, not a parallel first draft.
- **XcodeGen generates the project.** `ios/project.yml` is the source of truth;
  the `.xcodeproj` is gitignored and regenerated with `xcodegen generate` from
  `ios/`. Never hand-edit the generated project — change the YAML and regenerate.
  XcodeGen is a developer tool only; nothing from it ships.
- **Recents, then default search** for the empty grid (see UX model).
- **Image loading and the thumbnail cache live in a second package target,
  `ScryboardUI`**, which may import ImageIO and UIKit and is shared by both app
  targets. `ScryboardKit` stays Foundation-only for the Android port.
- **Settings cross over through an App Group**, `group.com.fedg.scryboard`,
  declared in `ios/project.yml` for both targets. XcodeGen writes the
  `.entitlements` files, which are gitignored like the project; automatic
  signing registered the group from the command line on 2026-09-22 with no
  portal work. `Preferences` and `PreferencesStore` in ScryboardUI are the
  only readers and writers; recents and the saved search stay in the
  extension's own defaults.

## Repository layout

```
scryboard/
├── CLAUDE.md
├── README.md              (public-facing; contains the attribution block)
├── LICENSE                (Apache-2.0; NOTICE alongside it)
├── .gitignore
├── ScryboardKit/          (SwiftPM package)
│   ├── Package.swift
│   ├── Sources/ScryboardKit/        (Foundation only — portable to Kotlin)
│   │   ├── HTTPTransport.swift      (protocol + URLSessionTransport)
│   │   ├── ScryfallClient.swift     (autocomplete, search, named, paging, printings)
│   │   ├── QueryClassifier.swift    (classify(_:))
│   │   ├── SearchPipeline.swift     (debounce, cancel, SearchOutcome stream)
│   │   ├── ResultsPager.swift       (grid paging: prefetch, dedupe, retry)
│   │   ├── Keyboard/                (KeyboardLayout, KeyboardState, QueryBuffer — pure data)
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

## Distribution (TestFlight)

First upload went out 2026-09-21 as 1.0 (1); the polish-pass build followed on 2026-09-22 (Apple assigns the build number). The paid team ID lives only in
`ios/Local.xcconfig` (gitignored); if `-exportArchive` ever asks for a team,
add a `teamID` key to a *local copy* of `ExportOptions.plist`, never to the
committed one. The App Store Connect record for `com.fedg.scryboard` exists.
Uploads run from the command line with Xcode's signed-in Apple ID; no API key
is involved yet. Nothing here publishes: builds land in TestFlight only, and the
App Store release is a separate, manual submission.

```sh
cd ios
xcodebuild archive -project Scryboard.xcodeproj -scheme Scryboard -configuration Release \
  -destination 'generic/platform=iOS' -archivePath /tmp/Scryboard.xcarchive -allowProvisioningUpdates
xcodebuild -exportArchive -archivePath /tmp/Scryboard.xcarchive -exportOptionsPlist ExportOptions.plist \
  -exportPath /tmp/export -allowProvisioningUpdates
```

Apple's "build processed" email is unreliable; check the TestFlight tab in App
Store Connect instead. **Friends test as internal testers**: on 2026-09-22 the
developer invited them to the App Store Connect team with the Developer role
so they skip Beta App Review. Each must accept the team email, then be ticked
into the internal group under TestFlight › Testers, and sign in to TestFlight
with the same Apple ID. Builds then reach them automatically on every upload.
External testing (public link) would need Beta App Review: contact details are
the developer's own, the description is what testers see, review notes should
say the keyboard needs Full Access only to reach the Scryfall API and collects
nothing. Not needed while testers fit in the internal group (limit 100).

`ios/ExportOptions.plist` uses `method: app-store-connect`, `destination: upload`
and `manageAppVersionAndBuildNumber: true`, so build numbers are bumped by
Apple's tooling and never need editing. Validation facts learned: a build needs
an app icon (placeholder in `Assets.xcassets`), privacy manifests in both
targets (UserDefaults, reason CA92.1), and `UISupportedInterfaceOrientations`
written into the explicit Info.plist — `INFOPLIST_KEY_*` build settings are
ignored when the plist is a file.

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
- Recents and the saved search persist in the extension's own container (`UserDefaults` for the card list and the search record, cache directory for thumbnails and the saved results file). The App Group carries settings only; the container app does not show recents (decided 2026-09-22).
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
5. ~~**Tap-to-copy**~~ — done and verified on an iPhone on 2026-09-22.
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
   chosen on reasoning rather than measurement. Measure on the iPad over cable
   together with the large-card thumbnail pass (polish item 8).

3. **A TestFlight tester stuck on "No Builds Available" (2026-09-22).** Two
   of the four internal testers show a red "No Builds Available" in Group 1
   while the developer and one friend installed 1.0 (2) fine, so the build and
   the group are not the problem. One of the stuck testers had first hit
   "Unable to install Scryboard" on his phone, tapped Stop Testing in
   TestFlight, and his old invite link then stopped working. Ruled out so
   far: he is an accepted team member (not pending), his Apple ID is in the
   right country, iOS 26.6. Removing and re-adding him to the group changes
   nothing and sends no email, because App Store Connect sends the invite
   only to testers it considers eligible. Both stuck rows show dashes in the
   device columns where the working testers show a phone model, so the
   working theory is that TestFlight has no device linked to those Apple IDs
   (Stop Testing drops the link; the other tester has never opened
   TestFlight). Untried, in order: (1) on his phone delete any leftover
   Scryboard icon, open TestFlight signed in as the invited Apple ID, pull to
   refresh — internal testers see their apps without an invite; (2) delete
   and reinstall TestFlight, sign in again; (3) a fresh internal group with
   automatic distribution containing only him. If all three fail, the next
   suspects are Pricing and Availability territories for the app record and
   the tester's app access under Users and Access. The "Unable to install"
   error itself is usually a half-installed leftover copy, a signing clash
   with a non-TestFlight install, or a bad download; delete, restart, retry.

When an item is done, delete it from this list rather than marking it; the list is
meant to empty out.

## Conventions

- Swift, latest stable toolchain; strict concurrency. UIKit in the extension, SwiftUI in the container app.
- No third-party dependencies without explicit discussion (the memory ceiling is the reason).
- ScryboardKit stays Foundation-only; ImageIO/UIKit code belongs in ScryboardUI or the app targets.
- Commits keep the suite green (`swift test` from `ScryboardKit/`) and both targets building.
