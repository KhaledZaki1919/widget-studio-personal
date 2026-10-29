# CLAUDE.md — Widget Studio

> **This is the owner's PERSONAL build, "Widget Studio P"** (`com.khaled.widgetstudio.personal`, App Group `group.com.khaled.widgetstudio.personal`), repo `KhaledZaki1919/widget-studio-personal`. Everything personal is described in `docs/personal.md`; read it first. Rules that override the official ones below:
> - `origin` = github.com/KhaledZaki1919/widget-studio-personal (push here). `upstream` = the official github.com/KhaledZaki1919/widget-studio. **NEVER push to upstream** (its push URL is set to `DISABLED-never-push-to-upstream`; keep it that way).
> - Personal code lives only in its own files: `ios/personal.yml`, `ios/**/Personal/`, `relay/`, `docs/personal.md`, `.github/workflows/relay.yml`. Official files get only small hook lines (listed in `docs/personal.md`), so upstream merges stay easy. Never move or reformat official code.
> - CI generates the project with `xcodegen generate --spec personal.yml` (includes `project.yml` unchanged).
> - Store mode, installed with Fast Store, like the official app.
>
> **Pulling official updates:**
> ```
> git fetch upstream
> git merge upstream/main          # never rebase: main is pushed
> ```
> On conflicts (`git status` lists them): keep **both** sides where the official change and a personal hook line touch the same spot (official code + our one-line hook), keep this personal block at the top of CLAUDE.md, and keep the personal values in `ios/WidgetStudio/Resources/InfoPlist.xcstrings` ("Widget Studio P") and in `.github/workflows/ios.yml` (`--spec personal.yml`, `WidgetStudioP.ipa`). If upstream adds a widget bundle line to `WidgetStudioWidgetsBundle.swift`, keep `PersonalWidgets().body` instead of `MyWidgets().body` (it contains it) and stay within 10 lines. Then `git add <files> && git commit`, push to origin (CI: compile + unit tests) and fix what breaks.

Home-screen widget builder for iOS 17+ (native Swift / SwiftUI). Arabic default (RTL) + English. Every widget is a **spec JSON + optional user image**, drawn by one renderer shared by the app preview and the widget. Templates are bundled; an optional AI flow uses the user's own key (BYOK). No backend, no accounts, no analytics. App Store later.

**Install method (owner, every build since M0):** every IPA is installed with **Fast Store**, a paid signing store that re-signs the app and the widget extension with its own certificate and profile. No Sideloadly. The store decides bundle IDs, team, profile and entitlements (the App Group was not granted in the M0 or M2 tests), so never assume the compiled values at runtime (ADR-004) and check Diagnostics → Signing when a capability fails.

The product brief is `widget-app-brief.md` (template catalog: `TEMPLATES.md`, visual reference: `docs/reference/widgets-reference.jpg`). Read them before changing behavior. Decisions live in `docs/decisions.md`.

## Working rules
- **Commit after every finished step** and push (`origin` = github.com/KhaledZaki1919/widget-studio, branch `main`). Small commits; end messages with the `Co-Authored-By: Claude …` line.
- Work in the milestones of the brief §10 (M0…M7). Stop at the end of each milestone and tell the owner the IPA is ready and how to test it; the next milestone starts in a new conversation.
- Record decisions as short ADRs in `docs/decisions.md`. Keep this file current.
- Git identity for this repo: `Khaled <khaled96960@gmail.com>` (repo-local config).
- Run `bash scripts/secret-scan.sh` before every push (the repo is public). `git config core.hooksPath .githooks` installs it as a pre-push hook.

## Repository map
| Path | What |
|---|---|
| `ios/project.yml` | XcodeGen spec (app + widget extension + tests). Never hand-edit the generated `.xcodeproj` |
| `ios/WidgetStudio/` | App target: `App/` (entry, root), `Features/<Area>/` (Library: tab, detail with Customize, previews; Editor: editor + field controls; MyWidgets: saved designs, `DesignsModel`; Settings: `LiveDataModel` (real data for previews), settings, dhikr list, Shortcut guide; AI: Settings → AI, Create from image flow, error messages (ADR-018); Qibla: live compass; Tiles: `TilesModel`, tile setup screens (ADR-017); Diagnostics with TestSpecs and data sources, opened only by long-pressing the version; Onboarding: introduction and `LogoMark`), `Resources/` |
| `ios/WidgetStudioWidgets/` | Widget extension: `SpecWidget.swift` (one `StaticConfiguration` widget per template, `TemplateWidget<ID>`, picked by swiping the widget gallery; error text instead of gray; step log — ADR-013), `ProbeWidget` (check widget; large shows the step log). **No AppIntentConfiguration**: it never renders on the owner's Fast Store install (ADR-013). A new template needs a `TemplateIDs` entry and a line in its category bundle |
| `ios/WidgetStudioTests/` | App-hosted unit tests: font availability, RTL invariants, every spec through the widget view, snapshots (`Snapshots/<id>.<lang>.png`) |
| `ios/WidgetStudioUITests/` | Simulator UI smoke tests |
| `ios/Fonts/` | Doto (static instances), IBM Plex Sans Arabic, Patrick Hand, DM Serif Display, Bebas Neue and the Arabic fallbacks Aref Ruqaa, Amiri, Lalezar, all OFL; bundled in app and widget, declared in `UIAppFonts` (ADR-010, ADR-019) |
| `ios/WidgetKitCore/` | Swift package shared by app + extension: `Environment/` (App Group resolver, profile, code signature reader), `Probe/` (incl. `WidgetLog`), `Data/` (live data: `OpenMeteo`, `PrayerCalculator` (adhan-swift), `HealthSummary`/`HealthReader`, `CounterState`/`StopwatchState`, `DataCache`, `AppSettings`, `LiveData`, `SourceStatus`, `PlaceNames` — ADR-016; `ClockFormat`, `QiblaCompass`, `TileSetup` — ADR-017), `AI/` (BYOK client ported from Lakhas: providers, `StructuredAI`, `AIDeadline`, `AIService`, Keychain key store, settings + consent; `AI/Widget/`: prompt builder, AI schema, parser, `WidgetGenerator`, `AIImage` — ADR-018; review round, `SpecSnapshot` renders — ADR-019), `Prompts/` (`generate_v2.md` in use, `review_v1.md`; v1 kept), `Designs/` (`SavedDesign`, `SharedStore` = the only storage for designs and photos, `DesignEditing` rules, `ImageProcessing`), `Spec/` (models incl. `calendarMonth`/`list`/`progressBar` in `CalendarListProgress.swift`, bindings, validator, icon whitelist, test spec loader), `Render/` (SpecView, layer views, binding resolver, fonts, timelines), `Resources/` (Templates: the Mono library, TestSpecs, Spec schema); `TemplateLibrary` loads templates. **Unit tests live here** |
| `ios/Config/` | Entitlements (written by XcodeGen from `project.yml`) |
| `ios/scripts/` | `build-ipa.sh`, `check-strings.py`, `pick-simulator.py` |
| `scripts/secret-scan.sh` | Secret scan, run before push and in CI |
| `docs/ai-eval/` | AI eval set: drawn widgets + `cases.json`; workflow **AI eval** (`.github/workflows/ai-eval.yml`, manual, secret `GEMINI_API_KEY`) uploads side-by-side renders (ADR-019). Never commit crops of the reference image |
| `docs/` | `decisions.md` (ADRs), `reference/` (gitignored image), `app-store/` (listing, privacy label, review notes, screenshots, `when-account.md` — ADR-020) |
| `site/` | Privacy policy and support pages (ar/en), deployed to GitHub Pages by `pages.yml` (ADR-020) |

## Environment
- Development machine is **Windows**; there is no Mac. iOS builds and tests run **only in GitHub Actions** (`.github/workflows/ios.yml`, `macos-15`).
- Node.js is at `C:\Program Files\nodejs` (no Python locally; CI has `python3`).
- GitHub CLI is at `C:\Program Files\GitHub CLI\gh.exe`.

## Commands
iOS (CI only; locally you can only edit), from `ios/`:
```
xcodegen generate                         # WidgetStudio.xcodeproj
swift test --package-path WidgetKitCore
python3 scripts/check-strings.py          # fails on missing ar/en translations or unknown keys
swiftlint lint
```
**CI** (`ios.yml`), on push to `main`, PRs and manual runs:
1. **every push:** secret scan + localization check + compile-only build (all errors, full `xcodebuild.log` artifact), and `WidgetKitCore` unit tests (`swift test`);
2. **only when the head commit message contains `[full]` or `[ipa]`** (or a manual run): app tests on the Simulator (renders, RTL invariants, snapshots, every template through the widget view) + UI smoke tests; every render goes to the `snapshots` artifact;
3. **only with `[ipa]`** (or a manual run), after everything above is green: unsigned IPA → artifact `WidgetStudio-ipa` (30 days). `build-ipa.sh` fails if the app or the widget lacks the App Group entitlement or a font declared in `UIAppFonts`.

Docs-only commits (`**.md`, `docs/**`) skip CI. SwiftLint is a separate, non-blocking job. Superseded runs are cancelled.

**Build modes (ADR-014):** one Swift condition, `WS_DEVELOPER`, set through the build setting `WS_EXTRA_CONDITIONS` (`project.yml`, empty by default).
- **Store mode** (default, what CI ships): the 28 fixed template widgets + one "My widget" per size reading `SharedStore`. Works on the owner's Fast Store install without an App Group or AppIntents.
- **Developer mode** (with the owner's own Apple account, later): the configurable widget (Edit Widget picks any saved design or template, Appearance, search). CI only *compiles* it (job "Compile", step "Build developer mode"); it never ships an IPA from CI.
- **Switching to developer mode later:**
  1. In `ios/project.yml`, set `WS_EXTRA_CONDITIONS: "WS_DEVELOPER"` (or pass `WS_EXTRA_CONDITIONS=WS_DEVELOPER` to `xcodebuild`).
  2. Set `DEVELOPMENT_TEAM` and `CODE_SIGN_STYLE: Automatic` for the account, and register the App Group `group.com.khaled.widgetstudio` for the app and the widget extension.
  3. Build and sign with Xcode or a signing CI job (not the unsigned IPA job).
  4. Check Diagnostics → App Group says Shared ✓ before testing My widget.

**Build rule (owner, since M2):**
- Do **not** build an IPA after each fix. Commit each fix and push; that runs compile + unit tests only. Fix all errors per commit.
- Use `[full]` on a commit when the change needs the Simulator tests (rendering, UI); it never builds an IPA.
- Build the IPA **once**, with `[ipa]` in the commit message, only after **all** requested fixes are done and every test is green. Then tell the owner the IPA is ready; they test everything in one go.

**After each push:**
1. Poll the run in the **foreground**, at most ~5 minutes per call, with a bounded loop of short calls: `for i in $(seq 1 9); do s=$(gh run view <id> --json status --jq .status); [ "$s" = completed ] && break; sleep 20; done`. Do **not** use `gh run watch`: Git Bash's `timeout` can't stop the Windows `gh.exe`, so it overran three times. Never start a background watcher (low-memory PC).
2. Fetch logs in a **separate call**, never chained after a watch: `gh run view <id> --log-failed` (or `--job <id> --log`).
3. On failure, fix **all** errors in one commit, push, and watch again until green.

## Conventions
**Swift / iOS**
- Swift 5 language mode, minimal concurrency checking (ADR-006), iOS 17+, SwiftUI. No third-party UI libraries or AI SDKs.
- Never hand-edit `.pbxproj`; change `project.yml`. Generated `Info.plist`s and the `.xcodeproj` are gitignored.
- No force unwraps or force casts.
- **No duplicate file names** within a Swift module.
- **Strings:** every user-facing string comes from a String Catalog (`Localizable.xcstrings` per target, `InfoPlist.xcstrings`) with both `ar` and `en`. Keys are `area.name` (`diag.title`); prefixes are listed in `ios/scripts/check-strings.py`, so add new areas there. Values that aren't UI text use `Text(verbatim:)`.
- **Accessibility identifiers** start with `ax.` (`ax.diag.run`).
- **Layout:** leading/trailing only; test RTL and LTR.
- **RTL in specs (ADR-010):** never flip anything like an image and never set `layoutDirection` on a `List`/UIKit-backed view to preview Arabic. Inside `SpecView` only `mirror: true` layers change: position, alignment, item order. Glyphs, digits and clocks keep their shape.
- **Fonts (ADR-010):** reference bundled fonts by PostScript name only (`FontRegistry`); every font file goes in `ios/Fonts` and both `UIAppFonts` lists. No runtime registration, no CoreText variation fonts.
- **Templates (ADR-011):** one JSON per template in `Resources/Templates/<id>.json`, colors as tokens (`@bg`, `@fg`, `@accent`…), every visible text `{en, ar}`, and `catalogOrder` in `TemplateLibrary` updated. Spec extensions (`when`, `rotation`, `highlightColor`, `icon` fields, new bindings) are listed in ADR-011.
- **Snapshots:** an intended visual change means re-recording references from the `snapshots` artifact (`ios/WidgetStudioTests/Snapshots/README.md`); look at the renders before committing them.
- **Sideloading (ADR-004):** never hardcode the bundle ID, team prefix or App Group at runtime. Use `AppGroupResolver.resolve()`. The widget extension never calls the network for AI and never reads the Keychain.
- **Release (ADR-020):** no visible Diagnostics entry and no check widget in release builds; no `print`; the widget step log is debug-only; keep `PrivacyInfo.xcprivacy` (app and widget) in sync with any new data flow or required-reason API, and the privacy page in `site/` with it. App Store screenshots: run the manual **Screenshots** workflow.
- **Data on the device only:** saved designs and photos go only through `SharedStore` (App Group if resolved, else the app container; ADR-015); other shared files through `FileProtection.write`. Secrets only in the Keychain.
- **Widget memory (~30 MB):** downscale images to the widget's pixel size before saving them to the App Group.
- **Live data (ADR-016):** the widget extension gets its own data (`WidgetStudioWidgets/WidgetData.swift`); never pass data from the app except through the store container (only shared with an App Group). Missing data shows a `DataGap` message, never sample numbers; only gallery previews, snapshot tests and the M1 test designs use `DataSnapshot.sample`.
- **AI (D4, D6, ADR-018):** AI returns a JSON spec, never code; every reply is validated in AI mode with one retry. Default models and provider specifics are in ADR-018; check provider docs before changing model IDs. Tests never use real keys or network (fixtures in `Tests/WidgetKitCoreTests/Fixtures/AI`, `-uiTestingStubAI` for UI tests). The widget extension never calls AI.
- **AI quality (ADR-019):** change the prompt or schema only with the AI eval: run the **AI eval** workflow (at most a few runs; free Gemini keys allow ~20 requests a day per model, so prefer `gemini-3.5-flash-lite` and wait a few minutes after 503s), download the `ai-eval` artifact and look at the side-by-side images. Gemini starts in JSON mode (its `responseSchema` hung in the eval); new layer types need validator, exported schema, AI schema, prompt and a test spec.
