# iPhone display customization

This is a source modification, not an installed or device-tested IPA.

- iPhone launches in landscape. The app delegate allows portrait and both landscape orientations after launch; iOS 16+ also receives one initial landscape geometry request. Returning from the background does not repeat that request. System rotation lock and OS geometry restrictions still apply.
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
2. Rotate to portrait, landscape left and landscape right. Background/resume in portrait; it should remain portrait.
3. Under Settings → Video, verify Auto resolution reports 2622 × 1206 on iPhone 17; connect and inspect the actual stream resolution in the overlay.
4. The PC must support the requested resolution. Parsec can choose a nearby mode or reject the request if it does not. No display driver, custom PC resolution, or host setting was changed by this patch.
5. Verify the entire desktop is visible in both orientations, menus avoid the camera/home indicator, and touch coordinates match the cursor. Test edge protection both on and off.
6. Test keyboard, pinch zoom, reconnect, and iPad orientation/multitasking for regressions.

An Xcode build and all physical-device checks remain required before calling this change verified.
