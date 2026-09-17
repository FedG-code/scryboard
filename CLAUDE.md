# Scryboard

An iOS custom keyboard for searching Magic: The Gathering cards and sending their images in any messaging app, without saving anything to the photo gallery. Android planned later.

**UX model:** the Tenor GIF keyboard. Search bar at the top of the keyboard, results as a scrollable grid of card thumbnails, tap a card → full image is copied to the clipboard → user long-presses and pastes into the chat. A brief "Copied — tap and hold to paste" toast confirms the copy.

## Core decisions (settled — do not revisit without asking)

- **Pasteboard flow, not link insertion.** Tapping a card writes the image to `UIPasteboard.general`. We do not insert Scryfall URLs as text.
- **No server component.** The keyboard talks directly to the Scryfall API. Zero backend, zero hosting costs.
- **No local card database, no offline mode.** Scryfall's server evaluates all search syntax (including `otag:`), so there is nothing to sync or bundle. The user is in a messaging context and therefore online.
- **No gallery writes, ever.** Images live in the extension's cache directory (evictable) and the pasteboard only.
- **Free forever.** Scryfall's API terms prohibit paywalling their data, and the WotC Fan Content Policy prohibits charging. No IAP, no subscriptions, no required accounts. Voluntary donation links live in the GitHub README only, not in-app.
- **Public repo.** Never commit signing material (certificates, provisioning profiles, `.p8`/`.p12` files).

## Architecture

Single Xcode project, two targets:

1. **Scryboard** (container app) — required by Apple to ship an extension. Minimal but non-empty for App Store review: setup instructions (how to enable the keyboard and Full Access), attribution screen, and optionally a simple card browser reusing the search client.
2. **ScryboardKeyboard** (keyboard extension, `UIInputViewController`) — the actual product.

Shared code (Scryfall client, image cache) goes in a local Swift package or shared framework target so both targets use it.

### Keyboard extension design

- **Search field:** keyboard extensions cannot summon the system keyboard for their own text fields. Render a minimal custom QWERTY in-extension for typing queries. This is the fiddliest UI component — build it early.
- **Input routing:** plain text queries → `/cards/autocomplete` (fast name suggestions as you type). Queries containing Scryfall syntax operators (`:`, `<`, `>`, `=`, quotes) → debounced `/cards/search`. Debounce ~300 ms, cancel in-flight requests on new input.
- **Results grid:** `UICollectionView` of card thumbnails using Scryfall's `small` image size (146×204, ~15–25 KB each).
- **Tap action:** fetch the `normal` size JPEG (488×680, ~50–150 KB), write to pasteboard as JPEG data, show toast, release the data. For double-faced cards, image URIs are under `card_faces[]` instead of top level — show the front face, with a flip affordance if cheap to add.
- **Globe key and delete key** are required for keyboard extensions; include them in the layout.

### Memory constraints (critical)

Keyboard extensions have a hard memory ceiling (~60–80 MB historically) and iOS kills them silently when exceeded — the keyboard just vanishes, which users read as a crash.

- Downsample thumbnails to cell size at decode time via `CGImageSourceCreateThumbnailAtIndex`. Never `UIImage(data:)` on full-resolution images for grid cells.
- `NSCache` with a count limit for decoded thumbnails.
- Never retain the full-size JPEG beyond the pasteboard write.
- Keep dependencies at or near zero. `URLSession` + Foundation JSON decoding is sufficient; no third-party networking or image libraries.
- Prefer UIKit for the extension. SwiftUI is acceptable if memory is monitored, but UIKit is the safer default here.

### Scryfall API contract

Base: `https://api.scryfall.com`

- Every request sends a descriptive `User-Agent` (e.g. `Scryboard/1.0 (github.com/USERNAME/scryboard)`) and `Accept: application/json`. Scryfall rejects requests without proper headers.
- Rate limit: stay well under 10 requests/second. Debouncing and request cancellation handle this in practice.
- Endpoints used:
  - `GET /cards/autocomplete?q=` — name suggestions for plain-text input
  - `GET /cards/search?q=` — full syntax search (server evaluates `otag:`, `is:`, `cmc<=`, colors, everything); paginated via `next_page`
  - `GET /cards/named?fuzzy=` — resolve a single name to a card
- Image URIs come from the card object's `image_uris` (or `card_faces[n].image_uris` for double-faced layouts). Sizes used: `small` for grid, `normal` for the pasteboard copy.
- Cache API responses and images aggressively (`URLCache` + cache directory); card data rarely changes.

### iOS platform facts to design around

- Network access requires `RequestsOpenAccess` (Full Access) = YES in the extension's Info.plist. The user must enable it in Settings; the container app's onboarding must explain this clearly, including the scary system prompt.
- iOS 16+: the first paste into each receiving app triggers a system permission prompt ("Allow X to paste from Scryboard?"). Once per app, remembered afterward. Expected behavior — Tenor has it too. Mention it in onboarding.
- Testing: free Apple ID provisioning works on a personal device (7-day expiry); paid developer account for TestFlight distribution.

## Legal / attribution requirements (non-negotiable)

- In-app about screen and App Store description include: "Card data and images provided by Scryfall. Scryboard is unofficial Fan Content permitted under the Wizards of the Coast Fan Content Policy. Not approved or endorsed by Scryfall or Wizards of the Coast. Magic: The Gathering is a trademark of Wizards of the Coast LLC."
- Never display Scryfall's logo or imply endorsement. Text attribution only.
- Never crop, watermark, or alter card images; never separate art from its attribution.
- App icon and branding are original. No Magic card back, no card art, no Scryfall visual identity.
- "Magic: The Gathering" may appear in the App Store description but not in the app's name field.

## Milestones

1. **Skeleton:** container app + extension targets build and the keyboard appears in Settings and can be selected. Globe/delete keys work.
2. **Search client:** shared Scryfall client with autocomplete/search split, proper headers, debounce, cancellation. Unit-testable without UI.
3. **In-keyboard QWERTY + search field** wired to the client.
4. **Results grid** with downsampled thumbnails and memory-safe scrolling.
5. **Tap-to-copy** with toast; verify paste into WhatsApp and iMessage end-to-end on device.
6. **Container app onboarding** (enable keyboard, Full Access, paste permission explainer) + attribution screen.
7. **Polish:** double-faced cards, printing selection (Commander players care which art), error/empty/offline states.

Milestone 5 is the "it works" moment — prioritize the path to it.

## Conventions

- Swift, latest stable toolchain. UIKit in the extension.
- No third-party dependencies without explicit discussion.
- Commits keep the extension buildable; the memory ceiling makes "big bang" refactors risky to verify.
