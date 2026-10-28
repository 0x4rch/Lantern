# Lantern

A guitar tuner for iPhone, started as a practice app built around the iPhone Duo's fold poses.
The idea was a tent-pose tuner: stand the phone up like an alarm clock and let half the inner
display light the wall red, amber or green, so you read the colour instead of the needle.

**It's shelved.** The tuner works. The tent-pose lamp turned out not to fit the hardware: the Duo
folds inward, so in a tent both inner halves face the table, and a third-party app can't draw on
the outer screen. The `duo-probe` branch has the experiment that found that out.

The code is here because the pitch detection is worth more read than sitting in a private repo.

## What's in it

- **`Packages/LanternCore`**: a Swift package with no UI dependencies.
  - `Pitch/YINDetector.swift`: YIN (de Cheveigné & Kawahara, 2002) on `vDSP`, with parabolic
    interpolation and an octave guard for the low-E error.
  - `Pitch/PitchTracker.swift`: onset gating, then median-of-5 and an EMA, done in cents rather
    than hertz.
  - `Pitch/TuningLockMachine.swift`: the far / close / in-tune hysteresis that keeps the lamp from
    flickering.
  - `Theory/`: notes, cents, tunings (standard, Drop D, DADGAD, E♭), chord symbols, capo and
    transpose.
  - `Audio/TunerEngine.swift`: `AVAudioEngine` input tap in `.measurement` mode, analysis off the
    audio thread.
- **`Lantern/`**: the SwiftUI app. A tuner with an upright layout and a landscape "tented" layout,
  picked by size class.
- **`docs/decisions.md`**: why things are the way they are, including where the code departs from
  the spec and why.
- **`PROP_HANDOFF.md`** and **`prop-duo-mockups.html`**: the original brief and mockups. The app
  was called Prop in the brief.

## Accuracy

The 37 tests synthesise sines and harmonic-rich plucks at every open string, dead on and at ±5
and ±20 cents. Against a ±1 cent target, the worst reading is 0.068 cents off and the mean is
0.014. That's synthetic signal; it has never been checked against a real guitar beside a clip-on
tuner.

## Running it

```bash
swift test --package-path Packages/LanternCore     # macOS, about a quarter of a second
xcodebuild -scheme Lantern -destination 'platform=iOS Simulator,name=iPhone 18 Pro' build
```

The app targets iOS 27 and needs Xcode 27. The `duo-probe` branch needs the iOS 27.1 SDK and the
iPhone Duo simulator. Set your own team and bundle ID before running it on a device.

## License

MIT. See [LICENSE](LICENSE).
