<div align="center">

# 🌊 NeuraWave

**Brainwave audio for focus, rest and sleep** — a tiny native macOS app with
science-tuned binaural & isochronic tones, auto-advancing focus programs, and a
menu bar soul.

<img src="docs/screenshot.png" width="600" alt="NeuraWave window" />

[![CI](https://github.com/AkiyamaKunka/NeuraWave/actions/workflows/ci.yml/badge.svg)](https://github.com/AkiyamaKunka/NeuraWave/actions)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![macOS 14+](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey)]()
[![v1.3.0](https://img.shields.io/badge/release-v1.3.0-orange)](https://github.com/AkiyamaKunka/NeuraWave/releases)

<a href="https://github.com/AkiyamaKunka/NeuraWave/releases/latest/download/NeuraWave-1.3.0.dmg">
  <img src="https://img.shields.io/badge/Download-NeuraWave%201.3.0%20for%20macOS-2ea043?style=for-the-badge&logo=apple&logoColor=white" alt="Download for macOS" />
</a>

</div>

---

## Why NeuraWave

- 🎯 **Frequencies tuned to evidence, not hype.** Deep Focus runs at 16 Hz — the
  beta rate Lane et al. (1998) actually tested for vigilance. Calm Focus sits at
  14 Hz SMR. 40 Hz gamma honestly recommends Isochronic mode. Every choice is
  sourced in [RESEARCH.md](RESEARCH.md).
- 🧭 **Focus programs that plan your session.** Study Flow settles you with Alpha,
  then ramps into Beta. Coding Sprint warms up, peaks at Gamma, then cools down.
  Mental Rest descends into Theta and brings you back — all with click-free
  crossfade transitions.
- 🌙 **Lives in the menu bar.** Close the window and it keeps playing. Starts at
  login silently — no sound until you press Start. Quits only when you quit it.
- 🎧 **AirPods & Now Playing.** Single-press pauses/resumes with a click-free
  fade, double-press skips presets, and live progress appears in Control Center.
- 🔒 **Zero noise.** No accounts, no analytics, no network calls. Free, open
  source, MIT.

## 🎛 Presets

| Preset | Band | Beat | Best for |
| --- | --- | --- | --- |
| Deep Sleep | Delta | 2.5 Hz | Deep, restorative sleep |
| Meditation | Theta | 6 Hz | Calm and inner awareness |
| Relax | Alpha | 10 Hz | Unwinding and stress relief |
| Calm Focus | SMR | 14 Hz | Steady attention, low strain |
| Deep Focus | Beta | 16 Hz | Active concentration and coding |
| Peak Concentration | Gamma | 40 Hz | Peak processing (best in Isochronic) |

## 🧭 Focus programs

| Program | Sequence | Total |
| --- | --- | --- |
| Study Flow | Alpha settle (10 min) → Beta focus (30 min) | 40 min |
| Coding Sprint | Beta warm-up (8 min) → Gamma peak (30 min) → Alpha cool-down (5 min) | 43 min |
| Mental Rest | Alpha (6 min) → Theta (20 min) → Alpha return (4 min) | 30 min |

## 📦 Install

1. Download **NeuraWave-1.3.0.dmg** from [Releases](https://github.com/AkiyamaKunka/NeuraWave/releases/latest).
2. Open the DMG and drag NeuraWave into **Applications**.
3. First launch: **right-click → Open** (ad-hoc signed; Gatekeeper asks once, then it launches normally).

> Signed & notarized builds (no right-click step) need an Apple Developer
> account — the CI pipeline is ready for it.

## 🔬 The science

Binaural beats show a medium effect in meta-analysis (Garcia-Argibay et al.,
2019, g ≈ 0.45) with real but weak cortical entrainment (Orozco Perez et al.,
2020), and results vary by person. NeuraWave is honest about that — the full
frequency rationale lives in [RESEARCH.md](RESEARCH.md).

## 🔨 Build from source

```bash
swift build                          # debug build
bash scripts/package-app.sh release  # assembles build/NeuraWave.app
```

## 🧪 Testing

A hidden self-test mode exercises every preset, tone style, noise setting,
volume change, timer, and stop/restart path:

```bash
# 8-second smoke test
build/NeuraWave.app/Contents/MacOS/NeuraWave --autotest --autotest-seconds 8 --autotest-cycle 2

# Full battery incl. a 30-minute endurance run, with pass/fail reporting
bash scripts/run-tests.sh
```

CI on GitHub Actions runs the smoke, stop/restart, and program-advance
scenarios on a clean macOS runner for every push.

## 🛟 Safety

- Avoid theta/delta audio when driving or operating machinery (drowsiness).
- Not for people with seizure disorders triggered by rhythmic stimuli.
- For relaxation and focus only — not medical advice, not a treatment for
  sleep or attention disorders.

## 📄 License

[MIT](LICENSE) © 2026 AkiyamaKunka
