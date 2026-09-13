# Changelog

## Unreleased

### Added
- `LanternCore` Swift package (`Packages/LanternCore`), linked into the Lantern app target.
- **Theory**: `PitchClass`, `Note`, `TuningReference` (adjustable A4), `Cents`, `Tuning` with
  standard / Drop D / DADGAD / E♭ standard and nearest-string selection, `ChordSymbol` parsing and
  transposition, and `CapoTransposition` for the shapes-you-play vs key-you-hear pair.
- **Pitch**: `YINDetector` (vDSP squared difference, cumulative mean normalized difference,
  absolute threshold with local-minimum descent, parabolic interpolation, octave guard, RMS gate),
  `TuningLockMachine` (the far/close/inTune hysteresis that drives the lamp), and `PitchTracker`
  (onset gating, median-of-5 then EMA, auto or explicit string targeting).
- 37 tests covering all of the above. YIN is checked against synthesized sines and harmonic-rich
  synthetic plucks at every open string at 0, ±5 and ±20 cents: worst case **0.068 cents**, mean
  **0.014 cents**, against a ±1 cent target.

### Changed
- App, unit-test and UI-test targets moved from Swift 5 to Swift 6 language mode, per handoff §2.4.
