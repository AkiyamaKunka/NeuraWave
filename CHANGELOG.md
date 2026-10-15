# Changelog

## 1.5.0 (not yet released)

### Fixed
- **Dropped changes:** preset, style and volume changes were sometimes lost (about 30% under load) because the audio thread overwrote them mid-render. A focus program could stay on the wrong band.
- **Output device changes:** switching devices (for example connecting AirPods) left the app saying "Playing" in silence. The output now rebuilds, or stops with an error.
- **Wrong preset during a program:** changing the tone style or skipping with AirPods mid-program jumped to the wrong preset.
- **Paused sessions:** a paused session kept the Mac awake and kept the output running. Pausing now freezes timers and programs.
- **Launch at Login:**
  - turning it off didn't stick;
  - a login launch popped up the window;
  - when macOS needs approval, the toggle now opens System Settings;
  - updating doesn't switch it back on if you had turned it off.
- **Menu bar and AirPods start:** these replayed stale settings or an old program. They now play exactly what the window's Start would.
- **Resume:**
  - a failed resume is now reported;
  - resuming mid-fade no longer clicks;
  - quitting no longer cuts the tone off with a click.
- **Show Window:** after closing the window, "Show Window" could fail to bring it back.
- **Waveform CPU:** the waveform redrew 30 times a second through SwiftUI, even in a hidden window. It is now a Core Animation layer animated by the system: app CPU while playing is under 1% with the window hidden (was about 9%) or visible (was about 7.5%).
- **Download link:** the README's Download button returned a 404.

### Added
- Pause/Resume button in the window, plus keyboard shortcuts: Space to start or pause, ⌘. to stop.
- Menu bar Presets submenu, a Stop item, and a tooltip showing what is playing.
- App icon as Now Playing artwork; Now Playing play state reported correctly.
- Volume and noise changes glide instead of stepping.
- Picking a timer mid-session applies immediately.
- Sleep timers and programs ease out over their last 30 seconds instead of stopping with a 2-second fade.
- New `scripts/make-dmg.sh`: builds a drag-to-Applications DMG (refuses to overwrite an existing one).

### Changed
- **Audio rendering:** about 17× cheaper (phasor oscillators instead of per-sample `sin()`); render cost is about 0.03% of real time. A larger output buffer (2048 frames, or the device's maximum, e.g. 960 on AirPods) means far fewer audio wakeups.
- **Code structure:** split into small, documented types:
  - `SessionClock`, `SettingsStore`;
  - `Voice`, `GainFader`, `LevelSmoother`, `NoiseGenerator`;
  - `LoginItem`, `MainWindow`;
  - window sections;
  - the self-test harness.
- **Tests:**
  - unit tests cover the render path, session logic, settings, timing and menus, all without audio hardware;
  - CI adds a Swift 6 strict-concurrency check;
  - CI runs every self-test scenario in parallel (`scripts/quick-tests.sh`).
- **Default volume is softer:** 0.385 instead of 0.55, if you never moved the volume slider.
- **Packaging:** release builds are universal (Apple silicon and Intel), and a broken code signature now fails the build instead of shipping.
- **Self-tests:** they run without a window, Dock or menu bar icon and stay out of Now Playing. They never touch saved settings, and `--autotest-volume 0` makes them silent.

## 1.4.0
- AirPods and Now Playing controls (pause/resume, preset skip).

## 1.3.0
- SMR preset, 16 Hz focus, gamma-isochronic tip, DMG packaging.

## 1.2.0
- Focus programs, launch at login, menu bar persistence, CI.
