# iPhone display customization

This customization is built into an IPA; physical-device testing is still required.

- iPhone launches in landscape. The app delegate allows portrait and both landscape orientations after launch. On iOS 16+, the actual interface orientation is saved before interruption and requested once on return, preserving portrait or either landscape direction. Cold launch still starts in landscape. System rotation lock and OS geometry restrictions still apply.
- Auto resolution uses the connected iPhone screen's native landscape pixels, independent of Display Zoom and initial view layout. iPhone 17 requests 2622 × 1206. Rotating the phone changes local layout, without repeatedly rotating the PC desktop.
- The first launch of this customization selects Auto resolution and resets saved zoom on iPhone. Subsequent manual choices are retained.
- “Avoid Camera / Home Indicator” defaults to on for iPhone. Video and controls respect the safe area. Turn it off for edge-to-edge presentation. Aspect-fit rendering is retained, so the full PC image is visible; differing aspect ratios produce black margins.
- iPad retains its launch orientations and window-based resolution behavior.

## Build and install

Use macOS with Xcode (upstream CI uses Xcode 26.2), the iOS SDK, and Git. From this folder run:

```sh
bash build-iphone.sh
```

The script downloads the upstream ParsecSDK submodule and creates `build/OpenParsec-iPhone.ipa`, unsigned for Sideloadly. Keep the same Apple account and bundle identifier when installing over the existing app. The original upstream GitHub Actions build workflow is also present, but no repository was published and no remote build was triggered.

Without a Mac, run the manual **Build iPhone display customization** workflow
(`iphone-custom-build.yml`) on your own GitHub fork. Download its
`OpenParsec-iPhone` artifact after all build and IPA verification steps succeed.
The custom workflow uploads an artifact only; it does not publish a release.

On Windows, Xcode/iOS compilation is unavailable. Editing an existing IPA's Info.plist alone cannot add these runtime changes.

## Device acceptance checks

### Windows keyboard accessory (build 20261025.1)

Esc is pinned at the left of the accessory bar and remains visible when its
other keys are scrolled. The row uses Ctrl, Alt, Shift, Win and Tab labels in
place of Mac symbols. Win still sends the existing LGUI key code (227); Esc
sends the existing escape key code (41). Modifier buttons stay held until
tapped again, and the existing keyboard-dismiss/background release handling
is retained. F1–F12, Del and arrows remain available by horizontal scrolling.
The system iOS letter keyboard is unchanged.

After installation, verify Esc closes a Windows menu/game menu, Win opens
Start, Ctrl+C/Ctrl+V and Alt+Tab work, and modifiers release when the keyboard
is hidden. Scroll the row to its end and rotate the phone with the keyboard
open; Esc should remain reachable, including when the pan handle is shown.

### Persistent right-side keys (build 20261025.2)

Esc, S and Space are available on the right edge of the stream independently
of the iOS keyboard and the Hide Buttons setting. Each 68 × 48 point button
sends key-down on contact and key-up on release/cancel/drag-out, so keys can
also be held. S uses HID code 22 without synthesizing Shift. Buttons release
when removed, disabled or the app resigns active, and reset their visual state
after the existing global input release. Reconnection/error/host-blocked states
disable the controls.

On the phone, test all three with the keyboard hidden, hold/release S and Space,
slide off a pressed button, use multiple buttons, rotate, background/resume,
and disconnect/reconnect while holding a key. Confirm a button press does not
move the remote mouse. These physical-device checks are still required.

### Display

1. With rotation lock off, terminate the app, hold the phone upright, launch, and verify landscape.
2. Rotate to portrait, landscape left and landscape right. In each orientation, switch to a different app/home screen, rotate the phone while away, and return; the UI should restore the orientation used before leaving. After return, rotate normally to verify rotation remains free. Also test Control Center, lock/unlock and a complete app restart (which should start landscape).
3. Under Settings → Video, verify Auto resolution reports 2622 × 1206 on iPhone 17; connect and inspect the actual stream resolution in the overlay.
4. The PC must support the requested resolution. Parsec can choose a nearby mode or reject the request if it does not. No display driver, custom PC resolution, or host setting was changed by this patch.
5. Verify the entire desktop is visible in both orientations, menus avoid the camera/home indicator, and touch coordinates match the cursor. Test edge protection both on and off.
6. Test keyboard, pinch zoom, reconnect, and iPad orientation/multitasking for regressions.

### Quick controls and foreground recovery (build 20261025.4)

- The sliders icon at the top right opens button editing. Drag each Esc/S/Space
  button, select it in the segmented picker, and adjust its size (44–88 points)
  and opacity (25–100%). Changes save immediately in UserDefaults; portrait and
  landscape have separate layouts. Reset affects only the current orientation.
  Editing sends no key presses and releases existing input. Normal controls
  retain native press/hold/release, cancellation, accessibility, and multi-touch.
- The adjacent button switches between responsive and quality presets. Responsive
  caps the longest edge at 1600 pixels, preserves device aspect with even encoder
  dimensions, and requests 8 Mbps. Quality requests native device resolution and
  25 Mbps. Both request constant frame rate. Existing frame-rate and codec choices
  stay as selected. Presets persist through reconnects; manual stream changes
  clear the preset label. These are requests, not measured latency guarantees.
- Light local haptics on key-down and preset switches default on and can be
  disabled in the editor. They acknowledge the local touch, not host delivery.
- Returning from background replenishes the reconnect retry budget and checks
  stream status through the existing single polling owner. No SDK reconnect calls
  run while inactive or paused. Temporary failures use the existing bounded
  three-attempt retry/backoff and visible reconnect overlay; permanent auth or
  permission errors keep their normal error handling. The auto-reconnect setting
  is respected. A healthy resumed session is not forcibly disconnected.

Device acceptance: move/resize/fade each key in both orientations, restart and
reconnect to check persistence, open/close the keyboard, and confirm transparent
gaps still control the remote cursor. Hold S+Space together, leave the app while
holding, and check no stuck input. Turn haptics off/on. Toggle both stream presets
and inspect actual resolution/bitrate after host negotiation and reconnect. Test
home/app switching, lock/unlock, brief network loss, longer Wi-Fi loss, unavailable
host, cancellation, auto-reconnect disabled, and PiP. The host must support the
requested display modes and be reachable; iOS cannot recover a session while
the app is terminated or the PC is offline.

An Xcode build and physical-device checks are separate acceptance steps.
