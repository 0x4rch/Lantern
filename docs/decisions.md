# Decisions

Things chosen along the way that Nathan should know about. Newest at the top.

## 2026-09-13 — Build order step 1: LanternCore (Theory + YIN)

### Naming: `Lantern`, not `Prop`

`PROP_HANDOFF.md` calls the app **Prop** and the package **PropCore**. The repo, the Xcode
project, the scheme, and `CLAUDE.md` all say **Lantern** / **LanternCore**, so the code follows the
repo. If Prop is the name you're settling on, the rename is a separate, mechanical pass — say the
word. (§9 of the handoff still lists the App Store name as an open question.)

### The octave guard does not use the literal rule from §4

§4 asks for: *"prefer the lower candidate when a dip at ½ frequency is within ~0.05 of the chosen
one."*

Taken literally that rule misfires on any clean tone. A sine is just as periodic at 2τ as at τ, so
its normalized difference at the lower octave is always within 0.05 of the chosen one — the guard
would fire every time and report every pure tone an octave low. A pure 440 Hz test tone comes back
as 220 Hz.

What `YINDetector.applyOctaveGuard` does instead: the lower octave has to win on **two** counts —
better by a ratio (`octaveGuardRatio`, 0.6) **and** better by an absolute margin
(`octaveGuardMinimumGain`, 0.005). The absolute margin is what keeps the guard away from dips that
are already essentially perfect, where the comparison is just numerical noise. A genuine octave
error — a weak fundamental with the second harmonic carrying the note — leaves a dip in the
0.005–0.12 band, well clear of the margin, so it still gets caught.

Both behaviours are covered by tests: `octaveGuardRecoversTheFundamental` (a near-missing
fundamental on the low E still reads 82 Hz) and `octaveGuardDoesNotDragCleanTonesDown` (110/220/
440/880 Hz sines stay put). If you want the literal rule back, those two tests are where it shows.

### The difference function is computed directly, not via autocorrelation

The fast way to write YIN's step 1 is `d(τ) = p(0) + p(τ) − 2r(τ)` with `r` from an FFT. That form
subtracts two nearly equal energies exactly where `d(τ)` approaches zero, and in `Float` the
cancellation eats the precision that the cent-level accuracy depends on.

`computeDifference` instead does `vDSP_vsub` + `vDSP_svesq` per lag — the differences are formed
before squaring, so there's nothing to cancel. It's about 5M float ops per frame, roughly 4% of one
core at the 43 fps the 1024-sample hop implies. If that ever matters, the fix is the autocorrelation
form in `Double`, not in `Float`.

### Choices the spec left open

- **Unvoiced frames.** When no dip clears the absolute threshold, YIN falls back to the global
  minimum. That's accepted only below `maxAperiodicity` (0.5); above it `detect` returns nil rather
  than guessing. The spec sets an RMS floor but doesn't say what to do with loud, unpitched input.
- **Smoothing space.** The median and EMA in `PitchTracker` run on cents-from-A4, not hertz, so the
  smoothing behaves the same at 82 Hz and 330 Hz. Smoothing in hertz would make the low strings
  sluggish and the high ones twitchy.
- **Clock.** `TuningLockMachine.update` takes an explicit `frameDuration` rather than reading a
  wall clock, which is what lets the 400 ms hysteresis be tested deterministically.
- **Effective range.** Lags are integers, so the real range is a little wider than the requested
  60–1200 Hz (about 60–1225 Hz at 44.1 kHz). Detection isn't clamped back to the nominal range.

### Colours live in the UI layer, not Core

`TuningLockState` is `far` / `close` / `inTune`. The hex values from §4 (`#E5573A`, `#F2B441`,
`#4BE378`) belong with the lamp view in step 2 — Core stays free of UI types so it keeps testing on
the host.

### Alternate tunings shipped

Standard, Drop D, DADGAD, E♭ standard, as §4 asks. **Bass is not in** — it's listed in §9 as a
question for you. It's genuinely cheap (extend the range down to ~30 Hz and add a four-string set),
but the YIN frame size has to grow for the low B at 31 Hz, so it isn't quite free.

### Package supports macOS as well as iOS

`Package.swift` declares `.iOS("27.0")` **and** `.macOS("26.0")`. The macOS platform is only so
`swift test` runs natively on the host — the whole suite finishes in about a quarter of a second,
which is worth a lot when tuning a pitch detector. Nothing in Core imports UIKit; keep it that way.

### The app target moved to Swift 6 language mode

The Xcode template left `SWIFT_VERSION = 5.0` on all three targets, and §2.4 calls for Swift 6
strict concurrency. Changed now, while the only app code is the template, so there's no migration to
do later. Builds clean.
