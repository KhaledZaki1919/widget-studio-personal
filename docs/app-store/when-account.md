# When you buy the Apple Developer account

Everything to do, in order, once the Apple Developer Program membership is active ($99/year, enroll as an individual at https://developer.apple.com/programs/enroll/). Until then the app keeps running in **store mode** from Fast Store (ADR-014).

## 0. First thing to test: "My widget" picker (M6 item 10)

Do this on the first account-signed build (section 6), before anything else:

1. Delete the Fast Store copy of the app first (a different signature can't share the App Group).
2. Open the app, save two designs: one from a template (Customize → Save) and one from **Create from image**.
3. Home Screen: touch and hold → Edit → Add Widget → **Widget Studio** → pick the small **Widget Studio** widget → Add Widget.
4. The placed widget must say **"Choose a design"** — it must **not** show a design on its own.
5. Touch and hold the widget → **Edit Widget** → **Design**: the list starts with **My widgets** (both saved designs, including the AI-made one), then the templates by category.
6. Type in the search field (e.g. part of a design's name, or "ساعة"): the list filters in both languages.
7. Pick the AI-made design → the widget shows it. Change **Appearance** to Light, then Dark: the widget follows.
8. Delete that design in the app → the widget says the design was deleted and to pick another one.
9. Repeat 3–7 for the medium and large sizes (a small design also appears in larger sizes).

The listing logic is unit-tested (`WidgetPickerTests`: saved designs from SharedStore first, search, nothing chosen automatically); this checks the system side.

## 1. Account basics

- Note your **Team ID** (developer.apple.com → Account → Membership details).
- In App Store Connect → Users and Access, make sure you are Account Holder/Admin.

## 2. Identifiers (developer.apple.com → Certificates, Identifiers & Profiles)

1. **App Group:** Identifiers → `+` → App Groups → `group.com.khaled.widgetstudio`.
2. **App ID (app):** `com.khaled.widgetstudio`, capabilities **App Groups** (assign the group) and **HealthKit**.
3. **App ID (widget):** `com.khaled.widgetstudio.widgets`, capabilities **App Groups** (same group) and **HealthKit**.

The IDs match `ios/project.yml` (D9). If any is taken, change all three in `project.yml` and in this file, and keep `WSAppGroup`/`ALTAppGroups` in sync.

## 3. Certificate (from Windows, with OpenSSL in Git Bash)

```bash
openssl req -new -newkey rsa:2048 -nodes -keyout dist.key -out dist.csr \
  -subj "/emailAddress=khaled96960@gmail.com/CN=Khaled/C=EG"
```
1. Certificates → `+` → **Apple Distribution** → upload `dist.csr` → download `distribution.cer`.
2. Make a `.p12`:
   ```bash
   openssl x509 -inform DER -in distribution.cer -out dist.pem
   openssl pkcs12 -export -inkey dist.key -in dist.pem -out dist.p12 -name "Apple Distribution" -passout pass:YOUR_P12_PASSWORD
   ```
3. Keep `dist.key` and `dist.p12` safe and **never commit them** (the secret scan blocks private keys).

## 4. Provisioning profiles

Profiles → `+` → **App Store Connect** distribution:
- `WidgetStudio AppStore` for `com.khaled.widgetstudio`
- `WidgetStudio Widgets AppStore` for `com.khaled.widgetstudio.widgets`

Download both `.mobileprovision` files.

## 5. Repository secrets (GitHub → Settings → Secrets and variables → Actions)

| Secret | Value |
|---|---|
| `APPLE_TEAM_ID` | Team ID |
| `DIST_CERT_P12` | `base64 -w0 dist.p12` |
| `DIST_CERT_PASSWORD` | the `.p12` password |
| `PROFILE_APP` | `base64 -w0 WidgetStudio_AppStore.mobileprovision` |
| `PROFILE_WIDGET` | `base64 -w0 WidgetStudio_Widgets_AppStore.mobileprovision` |
| `KEYCHAIN_PASSWORD` | any random string (temporary CI keychain) |
| `ASC_KEY_ID` | App Store Connect API key ID (section 7) |
| `ASC_ISSUER_ID` | Issuer ID (section 7) |
| `ASC_KEY_P8` | `base64 -w0 AuthKey_XXXX.p8` |

## 6. Switch to developer mode and sign in CI

Ask Claude to do these in one change (they're small):

1. `ios/project.yml`: `WS_EXTRA_CONDITIONS: "WS_DEVELOPER"`, `DEVELOPMENT_TEAM: $(APPLE_TEAM_ID)` from the environment, `CODE_SIGN_STYLE: Manual`, `CODE_SIGN_IDENTITY: "Apple Distribution"`, and `PROVISIONING_PROFILE_SPECIFIER` per target (the profile names above).
2. A new manual workflow `release.yml` (macos-15):
   - decode `DIST_CERT_P12` into a temporary keychain (`security create-keychain`, `security import … -T /usr/bin/codesign`, `security set-key-partition-list`), and the two profiles into `~/Library/MobileDevice/Provisioning Profiles/`;
   - `xcodegen generate`, then `xcodebuild archive -scheme WidgetStudio -configuration Release -archivePath build/WidgetStudio.xcarchive CURRENT_PROJECT_VERSION=${{ github.run_number }}`;
   - `xcodebuild -exportArchive` with an `ExportOptions.plist` (`method` = `app-store-connect`, `signingStyle` = `manual`, `teamID`, `provisioningProfiles` for both bundle IDs);
   - write `ASC_KEY_P8` to `~/.appstoreconnect/private_keys/AuthKey_$ASC_KEY_ID.p8` and upload: `xcrun altool --upload-app -f build/export/WidgetStudio.ipa -t ios --apiKey $ASC_KEY_ID --apiIssuer $ASC_ISSUER_ID`;
   - delete the temporary keychain in an `always()` step. Never print secrets.
3. Keep `ios.yml` as is: it still compiles both modes and ships the unsigned store-mode IPA for Fast Store until you switch.
4. Decide what the App Store build contains: developer mode has the configurable **Widget Studio** widget (one per size, Edit Widget picks any design or template) and the check widget. The 28 fixed template widgets are store-mode only (ADR-013/014). Decided (ADR-021): ship developer mode, without the 28 fixed widgets; remove the check widget from it before submitting.

## 7. App Store Connect

1. **API key:** Users and Access → Integrations → App Store Connect API → `+` → name "CI", access **App Manager** → download the `.p8` (only once) → note Key ID and Issuer ID → secrets (section 5).
2. **App record:** Apps → `+` → New App → iOS, name **ستوديو الويدجت** (Arabic primary) / Widget Studio, primary language Arabic, bundle ID `com.khaled.widgetstudio`, SKU `widgetstudio`.
3. Add the English (U.S.) localization; fill both from `listing.md`; App Privacy from `privacy-label.md`; review notes from `review-notes.md`; screenshots from `screenshots/`.

## 8. TestFlight

1. Run **release.yml** → the build appears in App Store Connect → TestFlight after processing (10–30 min).
2. Export compliance: the app uses only Apple's HTTPS (`ITSAppUsesNonExemptEncryption` is already `false`).
3. Internal Testing → add yourself → install **TestFlight** on the iPhone → install the build.

## 9. What to test on the TestFlight build

1. **My widget picker** — section 0, first.
2. **Diagnostics** (long-press the version) → App Group: **Shared ✓**, signed team = your Team ID, HealthKit granted for app and widget.
3. **Settings reach the widget** (they couldn't on Fast Store, ADR-016): change the temperature unit, prayer method, step goal, clock format, and edit the dhikr list → widgets update within a minute (or after Edit Widget → Done).
4. **Live data in the widget:** weather, prayer times, steps and sleep, battery.
5. **Interactive buttons:** tasbeeh +1 / next / reset, stopwatch start/stop.
6. **Shortcut tiles:** setup screen, then the Shortcut runs; a misspelled name brings back setup.
7. **Saved photos** appear in widgets (App Group images).
8. **Arabic and English**, light and dark, small/medium/large.
9. Then submit for review from App Store Connect.

## WidgetKit push updates (ADR-030)

Developer mode builds with Xcode 27 (`WS_EXTRA_CONDITIONS="WS_XL27 WS_DEVELOPER"`) give the large configurable widget a push handler (`LargePushPickWidget`, kind `WidgetStudio.pick.push`, `WidgetPushTokens` in `DeveloperWidgets.swift`, iOS 26+, listed next to the plain large one). A server that holds the token can then make that widget reload at once, outside the daily reload budget. It can't work on the Fast Store install: the store re-signs without the push entitlement.

To turn it on with your own account:
1. In the Apple Developer portal, enable Push Notifications for the app ID and the widget extension's ID, and create an APNs key (.p8).
2. In `ios/project.yml`, add `aps-environment` (`development`, later `production`) to both targets' entitlements.
3. Build developer mode with Xcode 27 and sign with your account (not the unsigned IPA job).
4. Place the large configurable widget. Its token appears in Diagnostics → Widget reloads ("push") and in the app cache file `widgetPushToken`.
5. Send an APNs request to that token with `apns-push-type: widgets` and topic `<app bundle id>.push-type.widgets`, body `{"aps": {"content-changed": true}}`. The widget reloads within seconds.

Apple still rate-limits widget pushes per day; use them for changes the timeline can't predict (a price, a shared task), not for clocks.
