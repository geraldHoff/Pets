# Screen-Time Pixel Pet (iOS) — Project Brief

Context file for continuing development with Claude Code. Read this before making architectural decisions.

## Concept

An animated pixel-art pet that reacts to screen time. The pet's state changes as the day's usage climbs, for example from happy to sleepy to sad, and it nudges the user through **rich notifications** that show the animated pet. Widgets and (optionally) a Live Activity show the pet's current state between notifications.

**Strategy: notifications first.** Notifications are the one surface that the Screen Time extension can drive directly, they work on every iOS version this app targets (so they're fully testable on an older iPhone), and they can show real animation in their expanded view. The Dynamic Island / Live Activity is a later, optional extra, because it can't be updated or restarted from the Screen Time extension (see constraints).

**Inspiration:** VS Code pet extensions such as vscode-pets. iOS has no free-floating overlay equivalent, so the design has to work within Apple's sanctioned surfaces.

**Prior art:**
- *Pixel Pals* (Christian Selig) puts a pixel pet in the Dynamic Island and in widgets, but it has no screen-time integration.
- *one sec* shows a usage timer in the Dynamic Island, but it has no pet.
- Smaller clones such as "Pixel Pets" and "Island Widgets" exist, but none combines a polished pet with real screen-time reactivity. That combination is the niche.

## Hard platform constraints (don't fight these)

- **No system-wide overlays on iOS.** There is no equivalent of Android's `SYSTEM_ALERT_WINDOW`, so a sprite can't walk across other apps. The PiP-video hack exists but is clunky and risks App Store rejection, so it is out of scope.
- **Screen Time data is sandboxed.**
  - The main app cannot read raw per-app usage minutes.
  - A `DeviceActivityMonitor` extension receives threshold callbacks such as `eventDidReachThreshold` and `intervalDidStart/End`. These callbacks are the main signal the app has to work with.
  - The callbacks are known to be unreliable on some iOS versions (thresholds firing early, twice, or not at all). The state logic must tolerate duplicates and missed events. `PetState` already ignores repeated callbacks for the same threshold name.
  - `DeviceActivityReport` can render usage charts, but only inside a privacy-isolated extension view. Its data can't be exported back to the app.
  - Pickup/session counts are not exposed by public APIs.
- **What the DeviceActivityMonitor extension can and can't do:**
  - Can: write to the App Group, post local notifications (`UNUserNotificationCenter`), apply/remove shields, and very likely ask WidgetKit to reload timelines (subject to the widget reload budget). Verify the last one in milestone 2.
  - Can't (in practice): start or update a Live Activity. ActivityKit only lets the **app** start a Live Activity while in the foreground, and updates come from the app or from ActivityKit push notifications sent by a server. Developers report `Activity.activities` is empty inside the monitor extension.
- **Live Activities expire and can't be restarted in the background.** They end after ~8 hours active and stay on the Lock Screen for up to 4 more hours (12 total). Restarting requires either the user opening the app or **push-to-start** (iOS 17.2+), which needs your own server and APNs. "A pet always in the Dynamic Island" is therefore not achievable without a backend or daily app opens.
- **Live Activities have no free render loop.** Updates are subject to system budgets and the `ContentState` payload is limited to ~4 KB. Send only the mood enum and bundle the sprites in the widget extension; never send image data.
- **Tapping a Live Activity or widget opens the app.** Interaction in place is limited to buttons backed by App Intents (iOS 17+).
- **Notifications (the primary surface):**
  - The collapsed banner and the Lock Screen / Notification Center list are **static**: app icon, title, body, and an optional attachment thumbnail. No animation there.
  - The **expanded view** (long-press or pull down on the notification) is where animation is possible:
    - **Animated GIF attachment** (`UNNotificationAttachment`): plays in the expanded view; the collapsed thumbnail is a still frame. Images, GIFs included, are limited to 10 MB. The system moves the attachment file into its own store, so copy the file to a temporary location before attaching it.
    - **Notification Content Extension** (`UNNotificationContentExtension`): a fully custom view controller (can host SwiftUI) shown in the expanded view. It can run a frame animation (e.g. render `PetCore` sprites with `TimelineView` + `Canvas`), and with `UNNotificationExtensionUserInteractionEnabled` (iOS 12+) it can have in-place buttons such as Feed / Play. It's matched to notifications through `UNNotificationExtensionCategory` = the content's `categoryIdentifier`, so it works for notifications posted by the monitor extension too.
  - **Notification actions** (`UNNotificationAction`) can handle Feed/Play without bringing the app to the foreground.
  - All of this works on iOS 10+, so the older test iPhone can exercise everything.
  - Users can silence, summarize, or Focus-filter notifications. Notify only on mood changes (the `PetReactions` rule) so the pet doesn't become spam. Don't use `.timeSensitive` interruption level unless it is genuinely urgent; App Review scrutinises it.
- **Shields are static.** A `ShieldConfiguration` extension can set an icon, title, subtitle, colors, and buttons. It can't show animation.
- **Extensions run in separate processes with tight memory limits** (the monitor extension is reported at around 6 MB). They communicate through a shared App Group container, either `UserDefaults(suiteName:)` or files. The app and extensions can write at the same time, so keep writes small and re-read state before applying an event (`PetStore.apply` does load → apply → save).

## Architecture

Targets (all share one App Group, e.g. `group.<bundle-prefix>.screenpet`, and all link the `PetCore` package):

| Target | Framework | Role |
|---|---|---|
| `PetCore` (Swift package) | Foundation only | Pet state, reducer, mood rules, notification copy, sprite data, App Group persistence. Builds and tests on Linux. |
| Main app | SwiftUI, FamilyControls, UserNotifications | Onboarding, `AuthorizationCenter.requestAuthorization(for: .individual)`, notification permission, app/category selection via `FamilyActivityPicker`, threshold config, pet care UI, handles notification actions |
| DeviceActivityMonitor ext | DeviceActivity, ManagedSettings, UserNotifications | Receives threshold events, applies them to `PetState` in the App Group, posts the pet notification, reloads widgets, optionally applies shields |
| Notification Content ext | UserNotificationsUI, SwiftUI | Animated pet in the expanded notification, with Feed / Play buttons |
| Widget ext | WidgetKit (+ ActivityKit later) | Home/Lock Screen widgets showing the current mood (interactive on iOS 17+). Live Activity UI later, optional. |
| ShieldConfiguration ext (optional) | ManagedSettingsUI | Custom shield showing a static image of the pet and a message |
| DeviceActivityReport ext (optional) | DeviceActivity | In-app usage chart |

**Data flow:**

```
DeviceActivityMonitor (threshold hit / interval start)
  → PetStore(appGroup:).apply(event)          // PetCore, returns (old, new)
  → PetReactions.notification(old → new)      // nil if the mood didn't change
      → post local notification (category = "pet-mood", GIF attachment)
          → Notification Content ext animates the pet, Feed/Play buttons
  → WidgetCenter reload (verify this works from the extension)
Main app / notification actions → PetStore.apply(.fed / .played)
Live Activity (optional): started by the app in the foreground; reflects state only when the app updates it
```

**Pet state model (implemented in `PetCore`):** `energy` (0–100), `lastFed`, `lastPlayed`, and `thresholdsHitToday` (a set of event names, so duplicate callbacks are no-ops). `mood` is derived from energy bands rather than stored, so it can never disagree with energy. Events: `thresholdReached(eventName:)`, `newDay`, `fed`, `played`. Feeding and playing have cooldowns so care can't instantly cancel out screen time. Tunables live in `PetRules`. The encoded state is well under the 4 KB Live Activity limit (there's a test for that).

## Device and OS requirements

- **iOS 16+** is required for individual (self) Screen Time authorization and for Live Activities (16.1). iOS 16 runs on iPhone 8/X and newer.
- **iOS 17+** is required for interactive widgets and Live Activity buttons. That means iPhone XS/XR and newer. Push-to-start Live Activities need iOS 17.2+.
- **Dynamic Island:** iPhone 14 Pro/Pro Max, iPhone 15 and later **except the "e" models** (the iPhone 16e has a notch, no Dynamic Island). Older devices show Live Activities on the Lock Screen and in banners only.
- **Rich notifications** (GIF attachments, content extensions, interactive content extensions) work on every device that runs iOS 16, so the notifications-first plan is fully testable on the older test iPhone.
- **Developer's test device:** an older iPhone (model and iOS version TBD; fill in).
- **Screen Time APIs must be tested on a real device.** They are unreliable or nonfunctional in the Simulator.

## Accounts and entitlements

- The paid Apple Developer Program ($99/yr) is effectively required for CI signing, TestFlight, App Groups across extensions, and the Family Controls capability. Verify against Apple's current capability table. **Simulator builds need no signing or account at all**, which is what CI uses today.
- **The Family Controls entitlement** is available for development builds. App Store distribution requires a separate request to Apple, made **for each bundle ID that uses it** (the main app *and* each extension that needs it, e.g. the monitor and shield extensions). It can take a while, so request it early.
- Each target needs its own App ID and provisioning profile with the App Group capability, and with Family Controls where relevant.

## Development environment (no Mac)

The primary workstation is Ubuntu. iOS builds require Xcode, which only runs on macOS, so the workflow is:

1. **Put all logic in `PetCore` and test it on Linux.** SwiftUI, ActivityKit, FamilyControls and UserNotifications won't compile on Linux, so keep anything testable (state, rules, notification copy, sprite data) in `PetCore`, which uses Foundation only. Run its tests without installing Swift:
   ```sh
   docker run --rm -v "$PWD/PetCore":/src -w /src swift:6.1 swift test --scratch-path /tmp/build
   ```
   Or install a Swift toolchain with [swiftly](https://www.swift.org/install/linux/) and run `swift test --package-path PetCore`. Only UI and framework glue should need a CI round-trip.
2. **Generate the Xcode project declaratively** with **XcodeGen** (`project.yml`). CI runs `xcodegen generate`; the `.xcodeproj` is gitignored. Never hand-edit `.xcodeproj`.
3. **CI (`.github/workflows/ci.yml`), free because the repo is public:**
   - `petcore-linux`: `swift test` in a `swift:6.1` container.
   - `ios-simulator` (macOS runner): tests `PetCore` on macOS, generates the project, builds for the Simulator with signing disabled, then `scripts/ci-simulator-screenshots.sh` launches the app once per mood (`-screenshotMood <mood>` launch argument) and saves a PNG and a 4-second MP4 of each. Download them from the run's **Artifacts** section (`simulator-screenshots`).
   - It also uploads `ScreenPet-simulator-app` (a zipped simulator `.app`). Upload that to **Appetize.io** (free tier, limited minutes) to click around the app in a browser-based Simulator, including Dynamic Island models.
4. **Signed device builds (later):** add fastlane (`match` for certificates/profiles stored encrypted, `gym` to build) to CI once the paid account exists. Every target, including each extension, needs a matching profile. Keep signing secrets in GitHub Actions secrets; never commit them, especially now that the repo is public.
5. **Install to device:**
   - Option A is `ideviceinstaller` from libimobiledevice over USB. This requires a development profile that includes the device UDID, and **Developer Mode** enabled on the iPhone (Settings → Privacy & Security, iOS 16+). Without Xcode the toggle may not appear until a dev-signed app has been installed; `idevicedevmodectl` from libimobiledevice can reveal it.
   - Option B is TestFlight, uploaded from CI with fastlane `pilot`. It doesn't need Developer Mode and is the easiest way to test on a friend's Dynamic Island iPhone.
6. **Debug through logs.** Use `Logger` in every target with a consistent subsystem, and stream logs on Linux with `idevicesyslog | grep <subsystem>`. Interpolated values are redacted as `<private>` in device logs unless marked, e.g. `logger.info("mood \(state.mood.rawValue, privacy: .public)")`. Log every DeviceActivity callback, every state write, and every notification posted.
7. **Iterate on art outside the app.** Placeholder sprites are text grids in `PetCore/Sources/PetCore/Sprites.swift`, and the tests check frame sizes and palette usage. Prototype real animations in Aseprite or a quick web canvas, then convert the finished frames. Animated GIFs for notification attachments could also be generated from the same frame data so the art has one source of truth.
8. **Other simulator options if CI screenshots aren't enough:** rent a cloud Mac for a day (MacinCloud, Scaleway, AWS EC2 Mac; Apple's licence imposes a 24-hour minimum lease), or use Xcode Cloud (25 compute hours/month included with the paid program). Running macOS in a VM on Linux violates Apple's licence and is not recommended.

Fallback if CI iteration becomes too slow: buy a used M1 Mac mini (~$300–450).

## Repo layout

```
project.yml                 # XcodeGen spec
PetCore/                    # Swift package: logic + sprite data, Linux-testable
  Sources/PetCore/          #   PetState, PetReactions, PetStore, Sprites
  Tests/PetCoreTests/
App/                        # main app target (SwiftUI)
scripts/                    # ci-simulator-screenshots.sh
.github/workflows/ci.yml
# to come:
MonitorExtension/           # DeviceActivityMonitor
NotificationContentExtension/
WidgetExtension/            # widgets (+ Live Activity later)
ShieldExtension/            # optional
fastlane/                   # Fastfile, Matchfile (once signing is set up)
```

## Milestones

1. **CI skeleton.** ✅ `PetCore` with tests on Linux; XcodeGen app target that builds for the Simulator on GitHub Actions and produces per-mood screenshots/videos. **Next:** add signing (paid account + fastlane match) and install on the device.
2. **Screen Time plumbing.**
   - Request authorization, use `FamilyActivityPicker`, and schedule a daily `DeviceActivity` with a few threshold events (e.g. 30 min, 1 h, 2 h, 3 h).
   - Confirm the monitor extension fires by watching `idevicesyslog`.
   - **Verify early** what the extension can do: post a local notification, reload widgets, and (expected to fail) touch a Live Activity. The results decide the surfaces.
3. **Shared state.** App Group entitlement on all targets; switch the app from `PetStore(defaults: .standard)` to `PetStore(appGroup:)`; the monitor extension applies `thresholdReached` / `newDay` events.
4. **Notifications.**
   - Post `PetReactions` notifications from the monitor extension with a GIF attachment of the current mood.
   - Add the Notification Content Extension that animates the pet with `PetCore` sprites, plus Feed / Play actions.
   - All testable on the older iPhone.
5. **Widgets.** Home and Lock Screen widgets showing the current mood; interactive Feed / Play on iOS 17+.
6. **Polish.**
   - Pet care loop tuning (`PetRules`), real art, optional shield and usage report.
   - Optional Live Activity started from the app; check the Lock Screen on the device and the Dynamic Island via Appetize, CI screenshots, or TestFlight on a friend's phone.
   - Request the Family Controls distribution entitlement for every bundle ID that needs it.

## Open questions

- Which pet behaviors map to which usage signals? Per-category thresholds, total daily usage, or both? (Pickup counts aren't available.)
- What thresholds and `PetRules` numbers feel fair rather than punishing? Should care be able to fully undo a bad day?
- Is a Live Activity worth it given it needs daily app opens (or a push server) to stay up?
- Could communication-notification styling (`INSendMessageIntent`) show the pet's face as the notification's avatar in the collapsed banner? It's designed for messaging apps, so it carries App Review risk.
- What sprite size and frame count work in the expanded notification and in widgets?
- Is the scope personal use only or the App Store? That decides how soon the entitlement request matters.
