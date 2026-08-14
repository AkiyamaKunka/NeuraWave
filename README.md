# NeuraWave

A small native macOS app that plays brainwave audio to help with focus, relaxation, and sleep.

## Presets

| Preset | Band | Beat | Best for |
| --- | --- | --- | --- |
| Deep Sleep | Delta | 2.5 Hz | Deep, restorative sleep |
| Meditation | Theta | 6 Hz | Calm and inner awareness |
| Relax | Alpha | 10 Hz | Unwinding and stress relief |
| Deep Focus | Beta | 18 Hz | Alert problem solving and coding |
| Peak Concentration | Gamma | 40 Hz | High-level concentration |

## Programs

Timed preset sequences that auto-advance (click-free crossfade). Step design
follows the evidence in [RESEARCH.md](RESEARCH.md).

| Program | Sequence | Total |
| --- | --- | --- |
| Study Flow | Alpha settle (10 min) → Beta focus (30 min) | 40 min |
| Coding Sprint | Beta warm-up (8 min) → Gamma peak (30 min) → Alpha cool-down (5 min) | 43 min |
| Mental Rest | Alpha (6 min) → Theta (20 min) → Alpha return (4 min) | 30 min |

Notes: the Gamma step is best in **Isochronic** mode (40 Hz auditory
steady-state research uses amplitude-modulated tones; a 40 Hz binaural beat
sits at the edge of perception). Theta only appears in Mental Rest because it
can cause drowsiness. The default timer is now **off** for manual presets —
programs carry their own duration.

## Features

- Binaural tones (headphones recommended) and isochronic tones (work with speakers)
- Optional pink-noise layer to mask distracting background sounds
- Volume control and a session timer (no timer, 15, 30, 45, 60, or 90 minutes)
- Click-free switching: presets and tone styles crossfade through silence instead of cutting
- Smooth fade-in and fade-out, and the Mac stays awake during a session
- Keeps playing when the window closes, with a menu bar item for start/stop and quit
- Starts at login (menu bar only after the window is closed; no sound until you press Start) — toggle via the menu bar's "Launch at Login"
- Quits only from the menu bar's Quit or Cmd+Q — closing or minimizing the window never stops it
- Remembers your last preset, tone style, volume, noise, timer, and program between launches

## Building

```bash
swift scripts/make-icon.swift packaging/icon.iconset
iconutil -c icns packaging/icon.iconset -o packaging/AppIcon.icns
bash scripts/package-app.sh release
```

The finished app is written to `build/NeuraWave.app`. Copy it to `/Applications` if you like.

## Testing

The app has a hidden self-test mode that exercises every preset, tone style,
noise setting, volume change, timer, and stop/restart path:

```bash
# 8-second smoke test, switching configuration every 3 seconds
build/NeuraWave.app/Contents/MacOS/NeuraWave --autotest --autotest-seconds 8 --autotest-cycle 3

# 30-minute endurance run
build/NeuraWave.app/Contents/MacOS/NeuraWave --autotest --autotest-seconds 1800 --autotest-cycle 30
```

It logs configuration switches plus audio-engine diagnostics (frames rendered,
NaN count, clip count, crossfade-switch count) and prints `AUTOTEST_COMPLETE`
when finished. The full battery with pass/fail reporting — quick scenarios,
the program-advance scenario, and the 30-minute endurance run, which the
script waits for — is `bash scripts/run-tests.sh`.

Note: NeuraWave is for relaxation and focus. It is not medical advice and is not a treatment for sleep disorders.

## License

MIT — see [LICENSE](LICENSE).
