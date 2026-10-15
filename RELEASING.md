# Releasing NeuraWave

1. Make sure `main` is green on CI and `CHANGELOG.md` describes the release.
2. Set the version in `packaging/Info.plist`: `CFBundleShortVersionString`
   (e.g. `1.5.0`) and bump `CFBundleVersion` (build number).
3. In `CHANGELOG.md`, change `## 1.5.0 (not yet released)` to plain `## 1.5.0`,
   like the earlier versions. If an open feature PR (for example the Isochronic
   change) should ship, merge it before this step so its entry lands in the
   right section. The open drafts (#3 Isochronic depth, #5 perceptual
   volume) merge cleanly with each other and with this one, and all tests pass
   with all three combined.
4. Run the full battery silently. It takes about 35 minutes, including a
   30-minute endurance run. It briefly opens the window and takes a screenshot,
   so macOS may ask for Screen Recording permission. It exits non-zero if any
   scenario fails.
   `AUTOTEST_EXTRA_ARGS="--autotest-volume 0" bash scripts/run-tests.sh`
5. Build the DMG with `bash scripts/make-dmg.sh`, which writes `dist/NeuraWave-<version>.dmg`.
   It builds a universal app (Apple silicon and Intel) and verifies the code signature.
   It refuses to overwrite an existing DMG (`FORCE=1` to override).
6. Tag and publish:
   `git tag v<version> && git push origin v<version>`, then
   `gh release create v<version> dist/NeuraWave-<version>.dmg --title "NeuraWave <version>" --notes-file <notes>`.

The README's download button and version badge point at the latest release, so
they need no edits.

## Check by hand before tagging

These can't be covered by automated tests:

- **Login launch:** turn on Launch at Login, log out and back in. The app
  should start in the menu bar with no window.
- **AirPods:** connect or disconnect AirPods mid-session. Playback should
  carry on.
- **Login item location:** run the new build once from the mounted DMG, then
  from /Applications. System Settings › General › Login Items should list
  the /Applications copy.
