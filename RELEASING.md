# Releasing NeuraWave

1. Make sure `main` is green on CI and `CHANGELOG.md` describes the release.
2. Set the version in `packaging/Info.plist`: `CFBundleShortVersionString`
   (e.g. `1.5.0`) and bump `CFBundleVersion` (build number).
3. Change the version's heading in `CHANGELOG.md` from "(not yet released)" to the date.
4. Run the full battery silently:
   `AUTOTEST_EXTRA_ARGS="--autotest-volume 0" bash scripts/run-tests.sh`
5. Build the DMG with `bash scripts/make-dmg.sh`, which writes `dist/NeuraWave-<version>.dmg`.
   It refuses to overwrite an existing DMG.
6. Tag and publish:
   `git tag v<version> && git push origin v<version>`, then
   `gh release create v<version> dist/NeuraWave-<version>.dmg --title "NeuraWave <version>" --notes-file <notes>`.

The README's download button and version badge point at the latest release, so
they need no edits.
