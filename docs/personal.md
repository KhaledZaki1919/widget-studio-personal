# Widget Studio P — personal build

The owner's own build of Widget Studio, installed **next to** the official app with Fast Store
(store mode, same install method as the official IPA).

| | Official | Personal |
|---|---|---|
| Repo | `KhaledZaki1919/widget-studio` (remote `upstream`, **never push**) | `KhaledZaki1919/widget-studio-personal` (remote `origin`) |
| App bundle ID | `com.khaled.widgetstudio` | `com.khaled.widgetstudio.personal` |
| Widget extension | `com.khaled.widgetstudio.widgets` | `com.khaled.widgetstudio.personal.widgets` |
| App Group | `group.com.khaled.widgetstudio` | `group.com.khaled.widgetstudio.personal` |
| Home-screen name | Widget Studio / ستوديو الويدجت | Widget Studio P / ستوديو الويدجت P |
| IPA artifact | `WidgetStudio-ipa` | `WidgetStudioP-ipa` (`WidgetStudioP.ipa`) |

## Pulling official updates
See the block at the top of `CLAUDE.md` (`git fetch upstream && git merge upstream/main`).

## Where personal code lives
Everything personal is in its own files, so upstream merges rarely conflict:

| Path | What |
|---|---|
| `ios/personal.yml` | XcodeGen overlay: `include: project.yml`, then bundle IDs, name, App Group, `WSRelayURL`. CI runs `xcodegen generate --spec personal.yml` |
| `ios/WidgetKitCore/Sources/WidgetKitCore/Personal/` | `RelayCrypto` (6-character code, key derivation per purpose, AES-GCM, errors), `RelayPayload` (info / design items), `RelayClient`, `WidgetSlots` (widget side: `SlotID`, `SlotState`, `SlotSync`), `HomeWidgets` (app side: `HomeWidgetSender`, `KnownWidget`, `WidgetRelayStatus`) |
| `ios/WidgetKitCore/Tests/WidgetKitCoreTests/Personal/` | Unit tests (in-memory relay, no network) |
| `ios/WidgetStudioWidgets/Personal/` | `PersonalWidgets` bundle, `SlotWidgets` (Slot 1–5, Slot (choose), providers, code card), `Personal.xcstrings` |
| `ios/WidgetStudio/Personal/` | `Theme/M3Theme.swift` (Material 3 theme), `SendToWidget` (sheet, editor section, My widgets and import buttons), `HomeScreenView` (My home screen, per-widget detail, Diagnostics section, design picker), `Personal.xcstrings` |
| `relay/` | Cloudflare Worker (`src/relay.js`), `wrangler.toml`, `node --test` tests |
| `.github/workflows/relay.yml` | Relay tests on change; deploy on manual run |

Strings live in a separate table, `Personal.xcstrings` (`Text(personal: "key")`), with keys `send.*`,
`home.*` (app) and `widget.slot.*` (widget), so the official catalogs and `check-strings.py` stay
untouched.

**Hook lines in official files** (keep them when merging):
- `ios/WidgetStudioWidgets/WidgetStudioWidgetsBundle.swift`: `PersonalWidgets().body` instead of `MyWidgets().body`.
- `ios/WidgetStudio/App/WidgetStudioApp.swift`: `.personalTheme()` on `RootView()`.
- `ios/WidgetStudio/App/RootView.swift`: `"homescreen"` next to `"mywidgets"` in the URL switch (a slot's code card opens My widgets).
- `ios/WidgetStudio/Features/Settings/SettingsView.swift`: `HomeScreenSettingsSection()` after the AI section.
- `ios/WidgetStudio/Features/Editor/EditorView.swift`: `SendToWidgetSection(...)` after the Regenerate section (covers AI results too).
- `ios/WidgetStudio/Features/MyWidgets/MyWidgetsView.swift`: `sendingHome` state, its `.sheet` (`SendToWidgetSheet`), a leading swipe and a context-menu `SendToWidgetButton`, and `HomeScreenListRow()` after the import section.
- `ios/WidgetStudio/Features/AI/BulkImportView.swift`: `SendToWidgetInlineButton(design:)` in each imported row.
- `ios/WidgetStudio/Features/Diagnostics/DiagnosticsView.swift`: `HomeWidgetsDiagnosticsSection()` after the widget section.
- `ios/WidgetStudio/Resources/InfoPlist.xcstrings`: display name "Widget Studio P".
- `.github/workflows/ios.yml`: `--spec personal.yml` (4×, incl. the Xcode 27 job), `WidgetStudioP.ipa`, artifact `WidgetStudioP-ipa`.
- `CLAUDE.md`: the personal block at the top. The Pages workflow is disabled in the personal repo (GitHub setting, no file change).
- **The Material 3 redesign** (2026-11-18) also touched official screens directly: system colors, button styles,
  fonts and radii became `M3.*` / `M3Type.*` / `M3Shape.*` / `.m3*` (one theme, `Personal/Theme`). On a merge
  conflict in a screen, take the official change and re-apply the same role substitutions (`.secondary` →
  `M3.onSurfaceVariant`, `.borderedProminent` → `.m3Filled`, `.bordered` → `.m3Outlined`, `.footnote` →
  `M3Type.bodySmall`, a `List`/`Form` gets `.m3List()`, …).

## Material 3 theme
`Personal/Theme/M3Theme.swift`; read the `material-design-3-ui` skill before changing it.
- **Color roles** (light / dark): `primary` = the Mono red (#E2231A; #FF5449 with dark content in dark mode,
  so both keep ≥ 4.5:1), neutral `secondaryContainer` (selected chips, tonal buttons, segmented
  selection), surface containers lowest → highest, `onSurface` / `onSurfaceVariant`, `outline(Variant)`,
  `inverse*` (snackbar), `error*`, and `success` / `warning`, always with an icon or text.
- **Type:** M3 roles mapped to iOS text styles (`displaySmall` = large title … `labelSmall` = caption 2), so
  Dynamic Type works; `M3Type.dots` (Doto) only for codes and counts.
- **Spacing** 4 / 8 / 12 / 16 / 24 / 32, targets 48. **Shape** 4 / 8 / 12 / 16 / 28.
- **Components:** `.m3Filled(Wide)`, `.m3Tonal(Wide)`, `.m3Outlined(Wide)`, `.m3Text`, `.m3Destructive`
  (state layer when pressed, disabled = onSurface 12 % / 38 %); `.m3Filter(selected:)` and `.m3Assist` chips
  (check mark when selected); `.m3Card(.filled | .outlined | .elevated)` only for real units;
  `.m3Field(label, supporting:, error:)`; `M3EmptyState`, `M3Status`, `M3SectionTitle`; `.m3List()`,
  `.m3Screen()`, `.m3Sheet()`.
- **iOS stays iOS:** tab bar, navigation stacks, swipe back, sheets, alerts, confirmation dialogs and system
  pickers keep their behavior; `M3Appearance` only gives the nav bar, tab bar, segmented control, switch,
  page dots and refresh control the roles' colors and type. Widgets and the spec renderer are untouched.

## Feature — one code per widget
**Identity.** WidgetKit gives a placed widget no instance ID, so identity = widget kind + size.
- **Fixed slots (the path that works on Fast Store):** five `StaticConfiguration` widgets, "Slot 1" … "Slot 5"
  (`WidgetStudio.slot.<n>`), each in small, medium, large and (Xcode 27 builds) 4 × 6. Every slot × size is its
  own widget with its own code: 5 per size, 20 in all. Two copies of the same slot in the same size share a code.
- **Slot (choose)** (`WidgetStudio.slot.pick`): an `AppIntentConfiguration` whose Edit Widget picks slot A … E.
  This is the experiment the owner asked for (Void Widgets' Edit Widget works on the same Fast Store install),
  against ADR-013's finding that every AppIntent-configured widget stayed gray there. If it renders, it adds 5
  slots per size; if it stays gray, use Slots 1–5. Either way the rest works the same.
- No arrows, no lock, no design cycling, no pairing.

**Flow.**
```
Widget (getTimeline) ──PUT info(size, slot)──▶ Worker+KV ◀──GET info── App: type code / pick known widget
App ──encrypt design──PUT design──▶ Worker+KV ◀──GET design (ETag)── Widget ──decrypt, cache──▶ draw
```
- An unassigned slot shows its 6-character code ("ABC-DEF", Doto). Its timeline announces it: an encrypted
  `info` item (size, slot name) under the code, re-sent weekly so it never expires.
- **Send to widget** (My widgets swipe / context menu, editor incl. AI results, each imported design): pick a
  widget the app already knows, or type a code. The app downloads the code's `info` item (a typo or a widget
  that never loaded → "No widget shows this code"; also gives the size), refuses designs bigger than the widget
  (never shrunk), encrypts design + photo (≤ 4 MiB) and uploads it, then reloads that slot's widget kind.
- The widget's timeline downloads the design (ETag; 304 when unchanged), decrypts, caches design + photo in its
  container (offline use), and draws it with the official `MyWidgetView`: same renderer, live bindings, states,
  artwork, tickers and tap actions (counters, timers, tasks, media) computed inside the widget. It checks the
  relay at least hourly (every 15 min while unassigned) and after every app reload.
- **Reassign:** send another design to the same code. **Remove** (My home screen): deletes the design on the
  relay and forgets the widget; on its next timeline the widget shows its code again (the code is free).
- **My home screen** (row at the top of My widgets; also Settings): every code the app sent to, with size, slot,
  current design, last update and delivery state (on the widget after N s / waiting / missing / error), pull to
  refresh; detail: Send another design (picks from My widgets, sizes that fit), Remove, delivery diagnostics.
- **Diagnostics** (and each widget's detail): per code the app's last send, the relay's last upload, the last
  widget download and the delay between them, the item size, and the relay host. The widget log (debug check
  widget) has `slot <n>.<size> …` lines; `ReloadLog` records every slot timeline and every send.
- With an App Group (not on Fast Store), the app also lists unassigned slots it can see directly ("On this phone").

## Relay and encryption
- **Keys.** `PBKDF2-SHA256(code, 150 000 rounds, salt "WidgetStudioP/relay/v2")` → root; `HKDF(root, "id/<purpose>")` =
  storage ID (64 hex), `HKDF(root, "key/<purpose>")` = AES-256-GCM key; purposes `info`, `design`. The relay sees
  only IDs and ciphertext; an ID reveals neither the code nor the key. A 6-character code (31⁶ ≈ 887 M) is short
  for typing; the stretching and the Worker's per-ID and per-IP rate limits keep online guessing impractical.
- **Worker limits:** 4 MiB per item (413), 60 requests/min per ID and 10 uploads/min per IP (rate-limit bindings;
  429), items expire 30 days after the last access (renewed at most once a day to stay inside the free KV write
  quota). KV only; no R2, no paid features. The relay's status endpoint gives upload time, size and last download.
- The tile Shortcut callbacks use the `widgetstudio://` scheme, which both apps register; with both
  installed iOS may open either app for a tile's callback. Widget taps always open their own app.

## Cloudflare
- Account: the one `wrangler` is logged in to on the owner's PC. Worker `widget-studio-relay`,
  KV namespace `RELAY` (`62c6e298bb124726940845f8fc2e497c`),
  URL **https://widget-studio-relay.att-gad.workers.dev** (compiled in as `WSRelayURL`).
- Deploy from the PC: `cd relay && npx wrangler@4 deploy` (log in once with `npx wrangler@4 login`).
- Deploy from GitHub: add repo secrets `CLOUDFLARE_API_TOKEN` (Cloudflare dashboard → My Profile →
  API Tokens → Create Token → template **Edit Cloudflare Workers**; also give it *Account → Workers
  KV Storage → Edit*) and `CLOUDFLARE_ACCOUNT_ID`, then run the **Relay** workflow manually.
- Never commit tokens; `scripts/secret-scan.sh` runs before every push.
- Changing the relay URL means a new IPA: the widget can only learn it from its own Info.plist.
