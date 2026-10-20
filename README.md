# UDock Touch

A menu bar app that makes a USB touchscreen work on a Mac, with trackpad-style gestures. It was built for the **UPERFECT UDock X 14 Pro** lapdock, but it should work with any touchscreen that reports as a standard HID multi-touch digitizer.

macOS has no built-in touchscreen support. UDock Touch reads the panel directly and turns touches into clicks, scrolling and gestures on the right display.

## Gestures

| Gesture | Result |
|---|---|
| Tap | Click (tap twice for a double-click) |
| Drag with one finger | Click and drag |
| Long press | Right-click |
| Tap with two fingers | Right-click |
| Drag with two fingers | Scroll, with momentum after a flick |
| Pinch | Zoom (native gesture, or ⌘+ / ⌘− in keyboard mode) |
| Twist two fingers | Rotate |
| Swipe left or right with three fingers | Switch Space or full-screen app |
| Swipe up with three fingers | Mission Control |
| Swipe down with three fingers | App Exposé |

Every gesture can be switched off in Settings, and its speed or sensitivity adjusted.

## Requirements

- macOS 13 or later
- Xcode, and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- A touchscreen connected by cable: full-function USB-C, or HDMI plus a USB data cable. The UDock's wireless mode doesn't carry touch to a Mac.

## Build and install

```bash
git clone <this repo>
cd udock-touch-app
scripts/install.sh
```

This builds a Release copy, installs it to `/Applications/UDock Touch.app` and starts it. On first launch, a setup window walks you through permissions and calibration.

### Signing (recommended)

macOS ties the Accessibility permission to the app's code signature. A fresh clone builds with ad-hoc signing, so macOS asks for permission again after every rebuild. To avoid that, sign with your own certificate:

```bash
cp Config/Local.xcconfig.example Config/Local.xcconfig
```

Then set your bundle ID prefix and team ID in `Config/Local.xcconfig`. The file is git-ignored. Any Apple ID signed in to Xcode can create an "Apple Development" certificate; you don't need a paid account.

### Development

```bash
xcodegen generate                                    # creates UDockTouch.xcodeproj
xcodebuild -project UDockTouch.xcodeproj -scheme UDockTouch build test
```

The `.xcodeproj` is generated, so edit `project.yml` rather than the project in Xcode.

## Permissions

- **Accessibility** (required): lets the app click, scroll and send gestures.
- **Input Monitoring** (recommended): some macOS versions need it to read the touch panel.

If permissions get stuck during development, reset them with `tccutil reset Accessibility <bundle-id>`.

## Settings

- **Display:** which display the touchscreen belongs to. It's remembered by the display's identity, so it's matched again on reconnect.
- **Orientation:** swap and flip the axes by hand, or detect them automatically by tapping two corners.
- **Calibration:** tap four targets so touches land exactly under your finger.
- **Gestures:** per-gesture switches, scroll speed and direction, momentum, pinch mode and sensitivity, long-press delay.
- **Device:** exclusive mode, for panels that also act as a mouse and click twice per tap. It may also switch off the lapdock's own keyboard and trackpad, so only use it if you need it.
- **Show a ripple where you touch:** optional visual feedback.

## Checking it works

- **Touch Test** (menu bar → Touch Test…): a full-screen check on the touch display. Tap the targets to measure accuracy in points, drag into every corner and along every edge to confirm the whole screen is reachable, and draw with several fingers to check tracking.
- **Diagnostics** (menu bar → Diagnostics…):
  - **Touches:** live finger positions, recognised gestures, and buttons that test swipe, pinch and rotate output.
  - **Traces:** record labelled gestures and replay them through the recogniser.
  - **Log:** turn on debug logging to record the panel's report layout, raw reports, touch frames and gestures to `~/Library/Logs/UDockTouch/touch.log`.
  - **Devices:** every HID device, with touchscreens marked ★.

### Gesture traces as tests

Traces recorded in Diagnostics are saved to `~/Library/Application Support/UDockTouch/Traces`. `scripts/import-traces.sh` copies them into `Tests/Traces`, where the test suite replays each one and checks it still produces the gesture it was labelled with.

## Troubleshooting

| Problem | Fix |
|---|---|
| Touches land on the wrong display | Pick the right one under Target Display in the menu |
| Touch moves the wrong way | Settings → Orientation → Detect Automatically |
| Taps land slightly off | Settings → Orientation → Calibrate, then check with Touch Test |
| Every tap clicks twice | Settings → Device → Exclusive mode |
| Nothing happens when touching | Check the menu shows "Touch is on" and that Accessibility is granted; then look at Diagnostics → Touches |
| Pinch does nothing | Settings → Gestures → Mode → Keyboard |

## Project layout

```
App/          menu bar app, setup window, calibration and touch test overlays
Settings/     settings window and storage
Diagnostics/  diagnostics window, traces
TouchCore/    framework with no UI: HID reading, mapping, gesture recogniser, event output
Tests/        unit tests and recorded traces
Config/       signing settings
```

## How it works, and caveats

Clicks, drags, scrolling and key presses use public `CGEvent` APIs. Pinch and rotate use undocumented gesture event fields. Mission Control and App Exposé use the private `CoreDockSendNotification` call, looked up at runtime. These work on macOS 27 but could change in a future macOS release.

The research by the [Mac Mouse Fix](https://github.com/noah-nuebling/mac-mouse-fix) project into synthetic gesture events was a helpful reference. No code from it is included.

## Licence

[MIT](LICENSE)
