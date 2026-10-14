# Screen-Time Pixel Pet (iOS) — Project Brief

Context file for continuing development with Claude Code. Read this before making architectural decisions.

## Concept

An animated pixel-art pet that lives on the iPhone's always-visible system surfaces (the Dynamic Island, Lock Screen, and widgets) and reacts to screen time. The pet's state changes as the day's usage climbs, for example from happy to sleepy to sad, and it can nudge the user with notifications or shields when they hit their thresholds.

**Inspiration:** VS Code pet extensions such as vscode-pets. iOS has no free-floating overlay equivalent, so the design has to work within Apple's sanctioned surfaces.

**Prior art:**
- *Pixel Pals* (Christian Selig) puts a pixel pet in the Dynamic Island and in widgets, but it has no screen-time integration.
- *one sec* shows a usage timer in the Dynamic Island, but it has no pet.
- Smaller clones such as "Pixel Pets" and "Island Widgets" exist, but none combines a polished pet with real screen-time reactivity. That combination is the niche.

## Hard platform constraints (don't fight these)

- **No system-wide overlays on iOS.** There is no equivalent of Android's `SYSTEM_ALERT_WINDOW`, so a sprite can't walk across other apps. The PiP-video hack exists but is clunky and risks App Store rejection, so it is out of scope.
- **Live Activities have no free render loop.** Updates go through ActivityKit and are subject to system update budgets, so smooth 60 fps animation in the Island isn't possible. Design the pet around discrete state changes and frame swaps, not continuous animation.
- **Tapping a Live Activity opens the app.** Interaction in place is limited. Long-press opens the expanded view, which can include buttons through App Intents.
- **Screen Time data is sandboxed.**
  - The main app cannot read raw per-app usage minutes.
  - A `DeviceActivityMonitor` extension receives threshold callbacks such as `eventDidReachThreshold` and `intervalDidStart/End`. These callbacks are the main signal the app has to work with.
  - `DeviceActivityReport` can render usage charts, but only inside a privacy-isolated extension view. Its data can't be exported back to the app.
- **Shields are static.** A `ShieldConfiguration` extension can set an icon, title, subtitle, colors, and buttons. It can't show animation.
- **Extensions run in separate processes with tight memory limits.** They communicate through a shared App Group container, either `UserDefaults(suiteName:)` or files.

## Architecture

Targets (all share one App Group, e.g. `group.<bundle-prefix>.screenpet`):

| Target | Framework | Role |
|---|---|---|
| Main app | SwiftUI, FamilyControls | Onboarding, `AuthorizationCenter.requestAuthorization(for: .individual)`, app/category selection via `FamilyActivityPicker`, threshold config, pet care UI, starts the Live Activity |
| DeviceActivityMonitor ext | DeviceActivity, ManagedSettings | Receives threshold events, writes pet state to the App Group, updates the Live Activity / posts local notification, optionally applies shields |
| Widget ext | WidgetKit, ActivityKit | Live Activity UI (Dynamic Island compact/minimal/expanded + Lock Screen) and home-screen widgets (interactive on iOS 17+) |
| ShieldConfiguration ext (optional) | ManagedSettingsUI | Custom shield showing a static image of the pet and a message |
| DeviceActivityReport ext (optional) | DeviceActivity | In-app usage chart |

**Data flow:**

```
DeviceActivityMonitor (threshold hit)
  → write PetState to App Group
  → update Live Activity content state / post notification
  → Widget ext re-renders pet sprite for new state
Main app (foreground) reads PetState, lets user feed/play → updates state
```

**Pet state model (first draft):** `mood` (enum), `energy`, `lastFed`, and `todayThresholdsHit`. Keep it small and `Codable` so it fits in the Live Activity `ContentState`.

## Device and OS requirements

- **iOS 16+** is required for individual (self) Screen Time authorization and for Live Activities (16.1). iOS 16 runs on iPhone 8/X and newer.
- **iOS 17+** is required for interactive widgets. That means iPhone XS/XR and newer.
- **iPhone 14 Pro or later** (all iPhone 15 models and newer) is required for the Dynamic Island. Older devices show the Live Activity on the Lock Screen and in banners only.
- **Developer's test device:** an older iPhone (model and iOS version TBD; fill in). It is fine for the Screen Time pipeline. Test the Dynamic Island visuals in the Simulator later.
- **Screen Time APIs must be tested on a real device.** They are unreliable or nonfunctional in the Simulator.

## Accounts and entitlements

- The paid Apple Developer Program ($99/yr) is effectively required for CI signing, TestFlight, and likely for the Family Controls capability. Verify against Apple's current capability table.
- **The Family Controls entitlement** is available for development builds. App Store distribution requires a separate request to Apple, which can take a while, so request it early.
- Each target needs its own App ID and provisioning profile with the App Group capability, and with Family Controls where relevant.

## Development environment (no Mac)

The primary workstation is Ubuntu. iOS builds require Xcode, which only runs on macOS, so the workflow is:

1. **Write code on Linux.** Swift can be edited anywhere, but SwiftUI, ActivityKit, and FamilyControls won't compile on Linux, so compile errors only show up on CI.
2. **Generate the Xcode project declaratively.** Use **XcodeGen** (`project.yml`) or Tuist so the multi-target project is defined in a readable text file and generated on CI. Do not hand-edit `.xcodeproj` on Linux.
3. **Build and sign on GitHub Actions macOS runners.**
   - Use fastlane (`match` for certificates/profiles stored encrypted in a private repo or as secrets, and `gym` to build).
   - Every target, including each extension, needs a matching profile.
   - Watch the macOS minute multiplier on private repos and check current GitHub pricing.
4. **Install to device:**
   - Option A is `ideviceinstaller` from libimobiledevice over USB. This requires a development profile that includes the device UDID.
   - Option B is TestFlight, uploaded from CI with fastlane `pilot`.
5. **Debug through logs.** Use `Logger`/`os_log` in every target with a consistent subsystem, and stream logs on Linux with `idevicesyslog | grep <subsystem>`. This is the main debugging tool, so log every DeviceActivity callback and every state write.
6. **Iterate on art outside the app.** Prototype sprite animations in a quick web canvas or Aseprite, then import the finished frame sets. This avoids a full CI round-trip for each visual tweak.

Fallback if CI iteration becomes too slow: buy a used M1 Mac mini (~$300–450).

## Suggested repo layout

```
project.yml                 # XcodeGen spec
App/                        # main app target
MonitorExtension/           # DeviceActivityMonitor
WidgetExtension/            # Live Activity + widgets
ShieldExtension/            # optional
Shared/                     # PetState, App Group keys, Logger, sprite helpers
Assets/Sprites/             # pixel art frames (nearest-neighbor scaling!)
fastlane/                   # Fastfile, Matchfile
.github/workflows/ios.yml
```

## Milestones

1. **CI skeleton.** XcodeGen project with a single app target that builds and signs on GitHub Actions and installs on the device. Prove the pipeline works first.
2. **Screen Time plumbing.**
   - Request authorization, use `FamilyActivityPicker`, and schedule a `DeviceActivity` with one threshold event.
   - Confirm that the monitor extension fires by watching `idevicesyslog`.
3. **Shared state.** Wire up the App Group and `PetState` so the monitor extension can write it and the main app can read it.
4. **Live Activity.**
   - Show a static pet sprite, then swap sprites per mood.
   - Check the Lock Screen on the real device and the Dynamic Island in the Simulator.
5. **Reactions.** Have threshold hits change the pet's mood and post a local notification with the pet's image.
6. **Polish.**
   - Add the pet care loop (feeding and playing), interactive widgets (iOS 17), and an optional shield and usage report.
   - Request the Family Controls distribution entitlement.

## Open questions

- Which pet behaviors map to which usage signals? Possibilities include a per-category threshold, total daily usage, or a pickup/session count. Note that pickup counts may not be available through public APIs, so this needs verification.
- What should the Live Activity lifetime strategy be? Live Activities expire (roughly 8 hours active, up to 12 on the Lock Screen), so the app needs a plan for restarting them, for example from the monitor extension at `intervalDidStart` if that is permitted. This needs verification.
- What sprite size and frame count fit the compact Dynamic Island region?
- Is the scope personal use only or the App Store? That decides how soon the entitlement request matters.
