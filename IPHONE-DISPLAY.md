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

1. With rotation lock off, terminate the app, hold the phone upright, launch, and verify landscape.
2. Rotate to portrait, landscape left and landscape right. Background/resume in portrait; it should remain portrait.
3. Under Settings → Video, verify Auto resolution reports 2622 × 1206 on iPhone 17; connect and inspect the actual stream resolution in the overlay.
4. The PC must support the requested resolution. Parsec can choose a nearby mode or reject the request if it does not. No display driver, custom PC resolution, or host setting was changed by this patch.
5. Verify the entire desktop is visible in both orientations, menus avoid the camera/home indicator, and touch coordinates match the cursor. Test edge protection both on and off.
6. Test keyboard, pinch zoom, reconnect, and iPad orientation/multitasking for regressions.

An Xcode build and all physical-device checks remain required before calling this change verified.
