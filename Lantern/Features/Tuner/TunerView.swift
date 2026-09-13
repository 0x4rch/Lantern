import LanternCore
import SwiftUI

struct TunerView: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = TunerModel()

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()

            // Compact height is the landscape-ish case, which is where the tented layout lives.
            // Keyed on size class rather than orientation, per handoff section 3.
            if verticalSizeClass == .compact {
                TentedLayout(model: model)
            } else {
                UprightLayout(model: model)
            }

            if let failure = model.failure {
                FailureNotice(message: failure) {
                    Task { await model.start() }
                }
            }
        }
        .statusBarHidden(verticalSizeClass == .compact)
        .persistentSystemOverlays(.hidden)
        .task { await model.start() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: Task { await model.start() }
            case .background, .inactive: model.stop()
            @unknown default: break
            }
        }
    }
}

// MARK: - Layouts

/// Portrait and anything else with room to stack: readout above, string row below.
private struct UprightLayout: View {
    let model: TunerModel

    var body: some View {
        VStack(spacing: 0) {
            TuningHeader(model: model)
                .padding(.horizontal, 24)
                .padding(.top, 8)

            Spacer(minLength: 0)

            NoteReadout(reading: model.reading, size: 132)

            CentsDial(reading: model.reading)
                .frame(height: 88)
                .padding(.horizontal, 28)
                .padding(.top, 12)

            Spacer(minLength: 0)

            StringRow(model: model)
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
        }
    }
}

/// The tented pose: readout on the near half, lamp on the far half. Until the 27.1 APIs land and
/// we know whether the far half can be addressed separately, the lamp is simply the other half of
/// this view — which is also what makes it readable across a room on a normal iPhone.
private struct TentedLayout: View {
    let model: TunerModel

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                NoteReadout(reading: model.reading, size: 104)
                CentsDial(reading: model.reading)
                    .frame(height: 64)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                Spacer(minLength: 0)
                StringRow(model: model)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
            }
            .frame(maxWidth: .infinity)

            Lamp(state: model.reading?.state)
                .frame(maxWidth: .infinity)
        }
        .ignoresSafeArea(edges: .bottom)
    }
}

// MARK: - Pieces

/// The far half of the display, driven as a solid colour you read off the wall.
private struct Lamp: View {
    let state: TuningLockState?

    var body: some View {
        Palette.lamp(state)
            .opacity(state == nil ? 0.12 : 1)
            .animation(.easeOut(duration: 0.18), value: state)
            .overlay {
                if state == nil {
                    Text("Play a string")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Palette.inkFaint)
                }
            }
    }
}

private struct NoteReadout: View {
    let reading: TunerReading?
    let size: CGFloat

    var body: some View {
        VStack(spacing: 2) {
            Text(reading?.string?.label ?? "–")
                .font(.readout(size))
                .foregroundStyle(reading == nil ? Palette.inkFaint : Palette.ink)
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.15), value: reading?.string?.index)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            if let reading {
                Text(centsLabel(reading.cents))
                    .font(.system(size: size * 0.16, weight: .medium).monospacedDigit())
                    .foregroundStyle(Palette.lamp(reading.state))
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.12), value: Int(reading.cents.rounded()))

                Text(String(format: "%.1f Hz", reading.smoothedFrequency))
                    .font(.system(size: size * 0.10, weight: .regular).monospacedDigit())
                    .foregroundStyle(Palette.inkFaint)
            } else {
                Text("Listening")
                    .font(.system(size: size * 0.13, weight: .medium))
                    .foregroundStyle(Palette.inkFaint)
            }
        }
    }

    private func centsLabel(_ cents: Double) -> String {
        let rounded = Int(cents.rounded())
        if rounded == 0 { return "in tune" }
        return rounded > 0 ? "+\(rounded)¢" : "\(rounded)¢"
    }
}

/// Cents scale. Ticks every ten cents across ±50, with the needle riding the smoothed reading.
private struct CentsDial: View {
    let reading: TunerReading?

    private let span: Double = 50

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let centre = width / 2
            let clamped = min(max(reading?.cents ?? 0, -span), span)
            let needleX = centre + (clamped / span) * centre

            ZStack(alignment: .topLeading) {
                ticks(width: width, height: height)

                Capsule()
                    .fill(Palette.lamp(reading?.state))
                    .frame(width: 4, height: height * 0.72)
                    .position(x: needleX, y: height * 0.36)
                    .opacity(reading == nil ? 0 : 1)
                    .animation(.interactiveSpring(duration: 0.16), value: needleX)
                    .animation(.easeOut(duration: 0.18), value: reading?.state)
            }
        }
    }

    private func ticks(width: CGFloat, height: CGFloat) -> some View {
        let marks = stride(from: -50, through: 50, by: 10).map(Double.init)
        return ZStack(alignment: .topLeading) {
            ForEach(marks, id: \.self) { mark in
                let isCentre = mark == 0
                let x = width / 2 + CGFloat(mark / span) * (width / 2)
                Capsule()
                    .fill(isCentre ? Palette.inkDim : Palette.inkFaint.opacity(0.5))
                    .frame(width: isCentre ? 2 : 1, height: isCentre ? height * 0.62 : height * 0.34)
                    .position(x: x, y: isCentre ? height * 0.31 : height * 0.17)
            }

            Text("♭")
                .font(.system(size: 15))
                .foregroundStyle(Palette.inkFaint)
                .position(x: 10, y: height * 0.86)
            Text("♯")
                .font(.system(size: 15))
                .foregroundStyle(Palette.inkFaint)
                .position(x: width - 10, y: height * 0.86)
        }
    }
}

/// The E A D G B e row. Tapping one pins the tuner to that string; tapping it again goes back to
/// picking automatically.
private struct StringRow: View {
    @Bindable var model: TunerModel

    var body: some View {
        HStack(spacing: 8) {
            ForEach(model.tuning.strings) { string in
                let isTarget = model.reading?.string?.index == string.index
                let isPinned = model.target == .string(string.index)

                Button {
                    model.target = isPinned ? .auto : .string(string.index)
                } label: {
                    Text(string.label)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(isTarget ? Palette.background : Palette.inkDim)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(isTarget ? Palette.lamp(model.reading?.state) : Palette.panel)
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Palette.ink.opacity(isPinned ? 0.8 : 0), lineWidth: 1.5)
                        }
                }
                .buttonStyle(.plain)
                .animation(.easeOut(duration: 0.15), value: isTarget)
            }
        }
    }
}

private struct TuningHeader: View {
    @Bindable var model: TunerModel

    var body: some View {
        HStack {
            Menu {
                Picker("Tuning", selection: $model.tuning) {
                    ForEach(Tuning.all) { tuning in
                        Text(tuning.name).tag(tuning)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(model.tuning.name)
                    Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold))
                }
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Palette.inkDim)
            }

            Spacer()

            if model.target != .auto {
                Button("Auto") { model.target = .auto }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Palette.inkDim)
            }

            Text("A\(Int(model.concertA))")
                .font(.system(size: 15, weight: .medium).monospacedDigit())
                .foregroundStyle(Palette.inkFaint)
                .padding(.leading, 12)
        }
    }
}

private struct FailureNotice: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack {
            VStack(spacing: 12) {
                Text(message)
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center)

                Button("Try again", action: retry)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.background)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(Palette.ink))
            }
            .padding(18)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.panel)
            }
            // Anchored to the top: the string row owns the bottom in both layouts, and in the
            // tented layout the lamp owns the right half.
            .frame(maxWidth: 460)
            .padding(.horizontal, 24)
            .padding(.top, 56)

            Spacer()
        }
    }
}

#Preview {
    TunerView()
}
