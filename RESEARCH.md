# NeuraWave — Neuroscience Research Notes

Why the presets, programs, and defaults are what they are. Sources at the bottom.
NeuraWave is a focus/relaxation aid, not a medical device — see the disclaimer.

## 1. What the evidence actually says (2026 state of the literature)

### Binaural beats — real but modest
- **Garcia-Argibay et al. (2019), "Efficacy of binaural auditory beats in
  cognition, anxiety, and pain perception: a meta-analysis"** — 22 studies,
  35 effect sizes. Overall medium, significant effect: **g = 0.45**.
  Key moderators:
  - Exposure **before** the task, or before+during, beats during-only.
  - **Longer exposure is better** (time under exposure significantly
    predicted effectiveness).
  - Masking with pink/white noise does **not** improve outcomes (so our noise
    layer is optional comfort, not efficacy).
  - Direction and magnitude depend on the **frequency used**.
- **Orozco Perez et al. (2020), eNeuro** — binaural beats do entrain the
  cortex at the beat frequency (auditory steady-state response, ASSR) and
  produce cross-frequency connectivity, but entrainment is **weaker than a
  monaural control**, and no mood modulation was found. So: neural
  entrainment is real, but claims beyond "modest aid" are not supported.

### Gamma (40 Hz) — strongest via amplitude-modulated sound, not binaural
- **Matulyte et al. (2024), "Gamma-Band Auditory Steady-State Response and
  Attention: A Systemic Review"** — 49 studies. Gamma-band ASSR (40 Hz) is a
  robust, well-replicated phenomenon; attention modulates it in most studies
  (with mixed results across methods and **large inter-individual
  variability**).
- Nearly the entire gamma ASSR literature uses **click trains / amplitude-
  modulated tones** — which is exactly what our **Isochronic** style is.
- Binaural beats have a perceptual upper limit around **~35–40 Hz** (Oster,
  "On the Frequency Limits of Binaural Beats") — a 40 Hz *binaural* beat sits
  at the edge of perception. **Design consequence: the Gamma step is most
  defensible in Isochronic mode**; the UI should steer users that way.

### Isochronic tones — plausible, thinner evidence
- A 2026 scoping review on amplitude-modulated audio in brainwave
  entrainment exists ("Amplitude Modulated Audio Signals in Brainwave
  Entrainment", Taylor & Francis) and school-based studies (Jakarta) report
  improved learning concentration, but the literature base is smaller than
  for binaural beats. Treat as "works with speakers, evidence lighter".

### Band roles (endogenous oscillations — established; exogenous induction — contested)
- **Delta (0.5–4 Hz)**: deep sleep / restorative states. Keep manual-only.
- **Theta (4–8 Hz)**: meditation, drowsiness, memory encoding. Rest only —
  **drowsiness risk** if used in a study program.
- **Alpha (8–13 Hz)**: relaxed wakefulness; alpha acts as an **inhibitory
  gate over task-irrelevant processing** (Klimesch 2012, TiCS "Alpha-band
  oscillations, attention, and controlled access to stored information").
  Good for settling in before demanding work and for cool-downs.
- **Beta (13–30 Hz)**: active concentration and alertness — the workhorse
  for study and warm-up phases.
- **Gamma (30–100 Hz)**: high-level processing, attention, binding; the 40 Hz
  ASSR is the best-evidenced entrainment target.

## 2. How this maps to the app

| Design choice | Neuroscience basis |
| --- | --- |
| Programs start with an Alpha settle-in phase | Exposure *before* the demanding task beats during-only (Garcia-Argibay); alpha gates distractors (Klimesch) |
| Study Flow: Alpha 10 min → Beta 30 min | Settle then sustained active concentration; longer exposure favored |
| Coding Sprint: Beta 8 min → Gamma 30 min → Alpha 5 min cool-down | Warm-up, peak attention at the best-evidenced target, then de-arousal so you don't finish wired |
| Mental Rest: Alpha 6 min → Theta 20 min → Alpha 4 min | Gentle descent into rest, then a short alpha "return" so you're not groggy afterwards |
| Gamma step favors Isochronic style | 40 Hz ASSR literature is AM/click-based; binaural 40 Hz is at the perceptual edge |
| Theta never appears in study programs | Drowsiness risk — counterproductive for reading/coding |
| Delta stays a manual preset | Sleep induction is a different use case; not a "program" |
| Default timer = off; programs carry their own duration | Users shouldn't be rushed; sessions of 30–45 min align with exposure-length findings |
| Pink-noise layer optional | Meta-regression: masking doesn't change efficacy |
| Honest copy: "effects are modest and vary by person" | g ≈ 0.45 with heterogeneity; entrainment weak vs monaural control; large inter-individual variability |

## 3. Safety
- Avoid theta/delta audio when operating machinery or driving (drowsiness).
- Auditory steady-state stimulation is contraindicated for people with
  photosensitive/reflex epilepsy or a history of seizures triggered by
  rhythmic stimuli — rare, but the standard caution applies.
- Not medical advice; not a treatment for sleep or attention disorders.

## 4. Sources
1. Garcia-Argibay, Santed & Reales (2019). Efficacy of binaural auditory
   beats in cognition, anxiety, and pain perception: a meta-analysis.
   Psychological Research, 83(2), 357–372. doi:10.1007/s00426-018-1066-8
2. Orozco Perez et al. (2020). Binaural Beats through the Auditory Pathway:
   From Brainstem to Connectivity Patterns. eNeuro 7(2), ENEURO.0232-19.2020.
3. Matulyte et al. (2024). Gamma-Band Auditory Steady-State Response and
   Attention: A Systemic Review. (49 studies; PMC11430480)
4. Klimesch (2012). α-band oscillations, attention, and controlled access to
   stored information. Trends in Cognitive Sciences 16(12), 606–617.
5. Oster (1973). Auditory beats in the brain. Scientific American 229(4);
   and On the Frequency Limits of Binaural Beats.
6. Amplitude Modulated Audio Signals in Brainwave Entrainment: Effects on
   Psychophysiological Functions — A Scoping Review (2026).
