# Prop — iPhone Duo guitar stand — engineering handoff

You are picking up a greenfield iOS app on a Mac with Xcode installed. The developer (Nathan) is an experienced solo dev; work autonomously, ask only when a decision materially changes scope. Read this whole file before writing code.

## 1. What we're building

**Prop** (working name, free, no accounts) is a guitar practice tool built around the iPhone Duo's fold poses. It ships as a normal iPhone app on iOS 27.0 and gains fold-native layouts on iOS 27.1.

The idea to explore first is the **tent-pose tuner**: the Duo stands like a StandBy alarm clock (hinge at the top, landscape, long edges on the table). The near half of the inner display shows the tuner; the far half, which faces the wall, is driven as a solid color lamp: red when way off, amber when close, green when in tune. You read the wall, not the needle.

Six poses, one app:

| Pose | What's shown |
|---|---|
| Tented (StandBy-style) | Near half: tuner (note, cents, needle, string dots). Far half: solid color lamp. |
| Tented, metronome | Near half: BPM + beat bars. Far half pulses on the downbeat. |
| Half-folded, laptop-style on a stand/knee | Top pane: chord chart / tab, auto-scrolling with tempo. Bottom pane: metronome, capo/transpose, bar-range looper. |
| Fully open | Two-pane songbook: setlists sidebar left, chart right. |
| Fully open, Split View | Prop half-width beside a lesson video; tempo may follow the video's playback rate (v2). |
| Fully open + Apple Pencil | Ink layer over the chart, anchored to bars so it survives transpose/capo. |

Feature map:
- **Tuner** — every pose. Tented: full screen + lamp. Half-fold: a green dot in the corner that expands when a lone plucked string is detected. Open: sidebar tool.
- **Metronome** — every pose. Tented is visual-first.
- **Charts** — chords / tab / free-form chart views. Import: ChordPro, pasted tab text, PDF, photo (v2).
- **Capo & transpose** — one control, two numbers: shapes you play, key you hear.
- **Looper** — bar-range loop with slowdown (½×, ¾×). Tented shows a pass counter.
- **Setlists** — local; shareable as a link that renders as plain text for non-users (v1.1).
- **Pencil ink** — PencilKit layer over the chart, bar-anchored.

Reference mockups: `prop-duo-mockups.html` (same folder as this file). Open it in a browser; the palette, type, and layouts there are the visual target.

## 2. Toolchain (do this first)

1. **Xcode 27 RC** is required — the App Store build is 26.x and will not have the iOS 27 SDK. Confirm with `xcodebuild -version`. If it's 26.x, download Xcode 27 RC from developer.apple.com/download (or xcodereleases.com), install alongside as `/Applications/Xcode-27.app`, then `sudo xcode-select -s /Applications/Xcode-27.app`.
2. **Xcode 27.1 beta** (Duo simulator via DeviceHub, iOS 27.1 SDK, `ArrangementView`, reserved-region APIs) had **not shipped as of Sept 13**; Apple says "later this month." Check developer.apple.com/news/releases each session. Until it lands, build everything against 27.0 and keep fold-specific code behind `#if canImport` / availability checks so it drops in cleanly.
3. Apple's "Get Ready for iPhone Duo" hub has six Tech Talks; the two to read before touching layout are *Prepare your app for iPhone Duo* and *Strike a pose with adaptive layouts*. Fetch and summarize them into `docs/apple-duo-notes.md` before writing UI.
4. Project: SwiftUI, Swift 6 strict concurrency, iOS 27.0 deployment target, single target + a `PropCore` Swift package for audio/pitch/music-theory so it's testable without UI.

## 3. Architecture

```
Prop/
  App/                 – entry, scene setup, pose routing
  Features/
    Tuner/             – TunerView (portrait / landscape / tented), TunerModel
    Metronome/         – MetronomeView, MetronomeEngine (AVAudioEngine, sample-accurate)
    Chart/             – ChartDocument, ChordProParser, ChartView, TabView, AutoScroll
    Looper/            – LoopRange, playback-rate control
    Setlists/          – SwiftData models, share link
    Ink/               – PencilKit overlay, bar anchoring
  Layout/
    PoseLayout.swift   – decides which layout to show from size classes + fold state
    Arrangement/       – 27.1-only: ArrangementView wrappers, reserved regions
  Packages/PropCore/
    Pitch/             – YIN detector, smoothing, lock state machine
    Theory/            – Note, cents math, transposition, capo
    Audio/             – input tap, ring buffer
```

Rules from Apple's talks that must hold everywhere:
- **Never branch on orientation.** Use `horizontalSizeClass` / `verticalSizeClass`. The inner display ignores supported interface orientations and reports regular×regular.
- **Never use `UIScreen.main`.** Two displays. Get the screen from `window?.windowScene?.screen`.
- Support Split View from day one (half-width + asymmetric safe areas is where layouts break). Do not mark the app as requiring full screen.
- Use `.ignoresSafeArea()` + concentric corners for edge-to-edge only once on the 27.1 SDK.

Pose detection (27.0): infer from size classes + window size. (27.1): add fold state / reserved `.division` region from the new APIs; when the division region has nonzero size, the device is partially folded → use `ArrangementView(.split)` with chart primary, controls secondary. **Open question to verify the moment 27.1 docs exist:** whether a third-party app can draw to both halves of the inner display in the tent pose, i.e. whether the "far half as lamp" is possible or whether tent pose is system-StandBy-only. If it is not possible, fall back to: tented = outer-display tuner, and the lamp becomes a large color fill on the inner display when the phone is laid flat/open on a table. Flag this to Nathan immediately either way.

## 4. Tuner spec (the part that must be excellent)

Target: ±1 cent displayed, stable enough that the lamp color doesn't flicker.

- Input: `AVAudioEngine` input node tap, mono, 44.1 kHz (or hardware rate), 4096-sample windows, 1024 hop. Request `.measurement` audio session mode to reduce input processing.
- Detector: **YIN** (de Cheveigné & Kawahara) with cumulative mean normalized difference, threshold 0.1–0.15, parabolic interpolation on the dip. Implement in `PropCore/Pitch/YIN.swift` using `vDSP` for the difference function. Range 60–1200 Hz. Add an octave-error guard preferring the lower candidate when a dip at ½ frequency is within ~0.05 of the chosen one (low E at 82 Hz is the classic failure).
- Gating: ignore frames below an RMS floor; ignore the first ~100 ms after an onset (attack transient).
- Smoothing: median of last 5 valid frames, then EMA. Display latency should feel ≤ 90 ms.
- Lock state machine (drives the lamp): `far` (>|15|¢, red), `close` (≤15¢, amber), `inTune` (≤±3¢ for N=6 consecutive frames, green). Leaving `inTune` requires >±5¢ for ~400 ms (hysteresis). Colors: red `#E5573A`, amber `#F2B441`, green `#4BE378`.
- Modes: auto (nearest string of standard tuning), or a target string chosen from the E A D G B e row. Reference A4 = 440 Hz, adjustable. Include common alt tunings (Drop D, DADGAD, Eb standard) — cheap and often requested.
- Tests: unit-test YIN against synthesized sines and a harmonic-rich synthetic pluck at each open-string frequency, ±0, ±5, ±20 cents; assert detected cents within ±1. Add a fixture folder for real recordings later.
- Manual verification: play tones from a signal generator through a speaker; compare against a clip-on tuner on a real guitar.

## 5. Metronome & looper

- Schedule clicks sample-accurately with `AVAudioPlayerNode` buffers (do not use `Timer`). Expose a beat publisher for UI (bar/beat index) that the chart auto-scroll and the lamp pulse subscribe to.
- Time signatures 4/4, 3/4, 6/8 for v1; tempo 30–260; tap tempo.
- Looper: loop a bar range; slowdown affects metronome tempo (there's no audio track in v1, so "slowdown" = tempo scaling + pass counting). Pass counter shown tented.

## 6. Charts

- Document model: sections → bars → chord cells (with optional lyric/tab lines). Parse ChordPro (`{title:}`, `{key:}`, `{capo:}`, `[G]` inline chords) and a lenient plain-text tab/chord-sheet importer.
- Transpose/capo math in `PropCore/Theory`: display "shapes you play" and "key you hear" separately.
- Auto-scroll: highlight the current bar from the metronome's beat publisher; scroll to keep it in the top third of the top pane.
- Sample content: create 3 original placeholder songs (do **not** use real copyrighted songs); the mockup uses titles like *Slow Train Out of Monessen*, *Rust Belt Waltz*.

## 7. Visual design

Match `prop-duo-mockups.html`: near-black UI (`#0B0B0D`), cream text, Fraunces-style light serif for the big note/BPM numerals (use a bundled open-license serif or New York on-device), SF for everything else. Big, readable from 6 feet away in the tented poses. Minimal chrome. No onboarding, no account, no paywall.

## 8. Build order

1. Toolchain check, project skeleton, `PropCore` package with Theory + YIN + tests. **Get the tuner right first** — it's the product.
2. Tuner UI for compact (outer/portrait) and a landscape "tented" layout, with the lamp implemented as a full-color view we can point at whatever half the API allows.
3. Metronome engine + UI.
4. Chart model, ChordPro parser, chart view, auto-scroll.
5. Half-fold layout (27.0: stacked layout keyed on size class; 27.1: `ArrangementView`).
6. Open songbook (NavigationSplitView), setlists (SwiftData).
7. Looper, capo/transpose UI.
8. Pencil ink.
9. When 27.1 beta ships: run every screen through all Duo poses in DeviceHub, Split View included; resolve the tent-pose question in §3.

Commit small; keep a `CHANGELOG.md` and a `docs/decisions.md` with anything you chose that Nathan should know about.

## 9. Things to ask Nathan about (don't block on them)

- App name (Prop is a placeholder — check App Store availability).
- Whether to include bass tuning in v1 (cheap: extend range and string set).
- Bundle ID / team; App Store Connect access for TestFlight.
- Whether he wants the share-link setlist feature in 1.0 or 1.1 (it's the only thing needing a server).
