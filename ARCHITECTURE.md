# How NeuraWave works

A short tour for anyone changing the code. File-by-file details are in the
README's code map.

## The pieces

```
 Window (SwiftUI)        Menu bar        AirPods / Control Center
 ContentView +           MenuBarController     NowPlayingController
 WindowSections                │                       │
        │                      │                       │
        └──────────────► SessionController ◄───────────┘
                         (main actor; the one session)
                          │        │         │
                SessionClock   SettingsStore   NowPlayingPublishing
                (timing)       (saved choices)  (Control Center state)
                          │
                          ▼  AudioOutput
                     AudioEngine (main actor)
                     AVAudioEngine lifecycle, pause release,
                     device-change rebuilds, keep-awake
                          │
                          ▼  lock-protected handoff
                     RealtimeState.render (audio thread)
                     Voice · GainFader · LevelSmoother · NoiseGenerator
```

- **SessionController** decides what plays: presets, programs, timers,
  pause/resume and Now Playing. It talks to sound only through the
  `AudioOutput` protocol, and to time only through an injected `now`, so
  its logic is unit tested with fakes (`SessionControllerTests`).
- **SessionClock** is a pure value type for pause-aware elapsed and remaining
  time. Paused time never counts, so a paused timer can't expire.
- **AudioEngine** owns AVAudioEngine:
  - It builds the output node, crossfades switches and releases the chain
    about 2.4 s after stop or pause.
  - It rebuilds after output-device changes (coalesced, and only when the
    format actually changed).
- **RealtimeState** is the only code on the audio thread.

## The audio thread rule

The render callback must never block for long, never allocate, and never lose
a request. Ownership is split:

- **The main thread writes** `pendingTone`, `running`, `volume` and
  `noiseEnabled`, under a short unfair lock.
- **The render thread** owns the voice, fader, level smoother and noise
  generator.
- **Each render call:**
  1. **Take:** under the lock, it takes the pending request (setting it to nil) and copies the main-thread values.
  2. **Render:** with the lock released, it renders the buffer.
  3. **Write back:** under the lock, it writes back only its own state. A request that arrived meanwhile is newer and wins; the older one is counted as *coalesced*.
- **Invariant:** every request is either applied or coalesced, never
  silently lost. The self-tests check it at the end of every run
  (`SWITCH_CHECK`), and `RealtimeStateTests` checks it with a real
  concurrent render loop.
- **resetGain:** this is the one exception, writing render-owned state from
  the main thread. It is only called while no node is attached, so no
  render can be running.

## Sound generation

- **Oscillators:** phasors (one complex multiply per sample), renormalized
  every buffer. They stay within 1e-6 of an exact sine over 10 minutes.
- **Binaural:** left at the carrier, right at carrier + beat.
- **Isochronic:** one carrier on both ears, pulsed at the beat rate.
- **Fades (`GainFader`):**
  - 2 s for start, stop, pause and resume.
  - A live switch dips to silence in 60 ms, swaps the tone while silent
    (phases restart inaudibly), then recovers in 150 ms. No node rebuild, no
    click.
- **Levels (`LevelSmoother`):** volume and noise glide over about 25 ms, so
  the slider never zippers.
- **Endings:** sleep timers and programs ease the volume out over their
  last 30 s.

## UI cost

- **Audio wakeups:** the output asks for 2048-frame buffers (~43 ms) instead
  of the default ~11 ms. Steady tones don't need low latency, and the fades
  are longer than the buffer anyway.
- **Waveform:** Core Animation shape layers slide in a repeating animation
  run by the system. The app does no per-frame work, and hidden windows cost
  nothing.
- **Countdown:** it publishes only when its value changes.
- **Now Playing:** it is pushed on state changes only, since macOS advances
  elapsed time itself.

## Testing

| Layer | How |
| --- | --- |
| Logic, timing, render math | `swift test`: no audio hardware, deterministic clocks |
| The real app end to end | `--autotest` self-tests (`scripts/quick-tests.sh`, `scripts/run-tests.sh`) |
| Concurrency | CI builds with Swift 6 strict concurrency, warnings as errors |

Self-tests run windowless, stay out of Now Playing and never touch saved
settings. `quick-tests.sh` fails if they do. Add `--autotest-volume 0` for
silence.
