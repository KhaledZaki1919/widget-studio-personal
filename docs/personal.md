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
| `ios/WidgetKitCore/Sources/WidgetKitCore/Personal/` | `RelayCrypto` (code, key derivation, AES-GCM), `RelayPayload`, `RelayClient`, `RelaySender` (app), `Switcher` (widget state, `RelayedStore`, `SwitcherCatalog`, `RelaySync`) |
| `ios/WidgetKitCore/Tests/WidgetKitCoreTests/Personal/` | Unit tests (in-memory relay, no network) |
| `ios/WidgetStudioWidgets/Personal/` | `PersonalWidgets` bundle, `SwitcherWidget` (provider, views, pairing card), `SwitcherIntents` (◀ ▶ 🔒), `Personal.xcstrings` |
| `ios/WidgetStudio/Personal/` | `PairWidgetView` (Settings → Pair widget + diagnostics), `UseOnHomeScreen` (sheet, editor section, My widgets button), `Personal.xcstrings` |
| `relay/` | Cloudflare Worker (`src/relay.js`), `wrangler.toml`, `node --test` tests |
| `.github/workflows/relay.yml` | Relay tests on change; deploy on manual run |

Strings live in a separate table, `Personal.xcstrings` (`Text(personal: "key")`), with keys under
the existing prefixes (`settings.pair.*`, `mywidgets.home.*`, `widget.switcher.*`), so the official
catalogs and `check-strings.py` stay untouched.

**Hook lines in official files** (keep them when merging):
- `ios/WidgetStudioWidgets/WidgetStudioWidgetsBundle.swift`: `PersonalWidgets().body` instead of `MyWidgets().body`.
- `ios/WidgetStudio/Features/Settings/SettingsView.swift`: `PairWidgetSection()` after the AI section.
- `ios/WidgetStudio/Features/Editor/EditorView.swift`: `UseOnHomeScreenSection(...)` after the Regenerate section.
- `ios/WidgetStudio/Features/MyWidgets/MyWidgetsView.swift`: `sendingHome` state, its `.sheet`, a leading swipe and a context-menu `UseOnHomeScreenButton`.
- `ios/WidgetStudio/Resources/InfoPlist.xcstrings`: display name "Widget Studio P".
- `.github/workflows/ios.yml`: `--spec personal.yml` (3×), `WidgetStudioP.ipa`, artifact `WidgetStudioP-ipa`.
- `CLAUDE.md`: the personal block at the top. The Pages workflow is disabled in the personal repo (GitHub setting, no file change).

## Feature 1 — switch designs on the widget
Widget **"Widget Studio"** in small, medium and large (`WidgetStudio.switcher.<size>`), a
`StaticConfiguration` like every widget that renders on Fast Store (ADR-013).
- ◀ ▶ (bottom corner) are `Button(intent:)` AppIntents that run in the widget extension, exactly like
  the tasbeeh buttons. State (`SwitcherState`: current key, locked) is a JSON file in the
  extension's own container (`DataCache`, `personal.switcher.<size>`). No App Group needed.
- The cycle: the pairing card (until paired), designs relayed to that size (newest first, the
  last 5 are cached), then every template that fits the size (`TemplateLibrary.fitting`).
- 🔒 hides the arrows and keeps the design; the faint 🔒 that stays shows them again.
- A tap sets `quietUntil` (20 s) so the reload WidgetKit does after it skips the network.
- Limitation: widgets of the same size share one state (StaticConfiguration has no per-instance identity).

## Feature 2 — relay through Cloudflare
```
App ──(encrypt)──PUT /v1/items/<id>──▶ Worker + KV ◀──GET (ETag)── Widget ──(decrypt, cache)──▶ draw
```
- **Pairing.** The unpaired widget shows an 8-character code (alphabet without 0/O/1/I/L, kept in
  its container). Settings → Pair widget: the user types it once; the app stores it in the
  Keychain and uploads an encrypted `pair` item. The widget sees it, stops showing the card.
- **Keys.** `PBKDF2-SHA256(code, 100 000 rounds)` → master; `HKDF(master, "id/<slot>")` = storage ID
  (64 hex), `HKDF(master, "key/<slot>")` = AES-256-GCM key. Slots: `pair`, `small`, `medium`, `large`.
  The relay sees only IDs and ciphertext; the ID doesn't reveal the key or the code.
- **Use on home screen** (My widgets: context menu / swipe right; editor incl. the AI result):
  pick a size (the design's size or larger) → `RelayPayload` (design JSON + photo, JPEG or PNG for
  halftone/mono, shrunk until the item is under 1 MiB) → encrypt → upload →
  `WidgetCenter.reloadTimelines(ofKind:)`. The widget's timeline downloads (ETag; 304 when
  unchanged), decrypts, caches it in its container (offline use) and makes it the current design.
  The widget also checks hourly (every 15 min while unpaired).
- **Worker limits:** 1 MiB per item (413), 60 requests/min per ID and 10 uploads/min per IP
  (rate-limit bindings; 429), items expire 30 days after the last access (renewed at most once a
  day to stay inside the free KV write quota). KV only; no R2, no paid features.
- **Diagnostics** (Settings → Pair widget): relay host, paired on, last upload (time, size, design,
  bytes), last error, "widget saw the pairing", and per size ↑ uploaded / ↓ last widget download.
  The widget log (debug check widget) has `switcher …` lines.
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
