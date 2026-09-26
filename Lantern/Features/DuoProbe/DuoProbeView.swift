//
//  DuoProbeView.swift
//  Lantern
//
//  Throwaway probe for the iPhone Duo (duo-probe branch only). It answers two questions the
//  27.1 SDK headers can't:
//    1. Lamp: in the tent pose, does iOS keep both halves of the inner panel lit for a
//       foreground app, so the far half can be painted as a lamp?
//    2. Alarm: does a third-party AlarmKit alarm get the system's tented glow and outer-screen
//       snooze that Apple's Clock app shows in the promo?
//

import AlarmKit
import CoreMotion
import OSLog
import SwiftUI

private let log = Logger(subsystem: "com.noinfodev.Lantern", category: "DuoProbe")

@available(iOS 27.1, *)
struct DuoProbeView: View {
    @State private var hinge: DeviceHinge?
    @State private var motion = ProbeMotion()
    @State private var lit: LitHalf = .far
    @State private var colorIndex = 2
    @State private var alarmStatus = "not scheduled"

    private let lampColors: [(name: String, color: Color)] = [
        ("red", Palette.far), ("amber", Palette.close), ("green", Palette.inTune), ("white", .white),
    ]

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let division = proxy.reservedRegions(kind: .division, options: .includeInactive)
            let crease = division.first { $0.isActive } ?? division.first
            let halves = Halves(size: size, crease: crease?.frame)

            ZStack(alignment: .topLeading) {
                Palette.background

                if lit.includesNear {
                    lampColors[colorIndex].color.frame(width: halves.near.width, height: halves.near.height)
                        .offset(x: halves.near.minX, y: halves.near.minY)
                }
                if lit.includesFar {
                    lampColors[colorIndex].color.frame(width: halves.far.width, height: halves.far.height)
                        .offset(x: halves.far.minX, y: halves.far.minY)
                }

                readout(size: size, division: division, halves: halves)
                    .frame(width: halves.readout.width, height: halves.readout.height)
                    .offset(x: halves.readout.minX, y: halves.readout.minY)
            }
            .onChange(of: division) { _, regions in
                log.info("division regions: \(regions.map { "\($0.frame) active=\($0.isActive)" }, privacy: .public)")
            }
        }
        .ignoresSafeArea()
        .onHingeChange { _, new in
            hinge = new.hinge
            log.info("hinge: \(describe(new.hinge), privacy: .public)")
        }
        .onAppear { motion.start() }
        .onDisappear { motion.stop() }
        .persistentSystemOverlays(.hidden)
        .statusBarHidden()
    }

    private func readout(size: CGSize, division: [ReservedRegion], halves: Halves) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Duo probe").font(.readout(28)).foregroundStyle(Palette.ink)

            TimelineView(.periodic(from: .now, by: 1)) { _ in
                VStack(alignment: .leading, spacing: 4) {
                    row("hinge", describe(hinge))
                    row("view", "\(Int(size.width)) × \(Int(size.height)) pt")
                    row("division", division.isEmpty ? "none" : division.map {
                        "\(format($0.frame)) \($0.isActive ? "active" : "inactive")"
                    }.joined(separator: "; "))
                    row("crease", halves.axisDescription)
                    row("gravity", motion.gravityDescription)
                    row("scenes", ProbeScenes.describe())
                }
            }
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(Palette.inkDim)

            HStack(spacing: 8) {
                Button("Lit: \(lit.rawValue)") { lit = lit.next }
                Button("Colour: \(lampColors[colorIndex].name)") {
                    colorIndex = (colorIndex + 1) % lampColors.count
                }
                Button("Alarm in 30 s") { Task { await scheduleAlarm() } }
            }
            .buttonStyle(.bordered)
            .tint(Palette.ink)

            row("alarm", alarmStatus)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Palette.inkDim)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(Palette.inkFaint).frame(width: 64, alignment: .leading)
            Text(value).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Alarm

    private func scheduleAlarm() async {
        do {
            let auth = try await AlarmManager.shared.requestAuthorization()
            guard auth == .authorized else {
                alarmStatus = "authorization: \(auth)"
                return
            }
            let alert = AlarmPresentation.Alert(
                title: "Lantern probe",
                secondaryButton: AlarmButton(text: "Snooze", textColor: .white, systemImageName: "zzz"),
                secondaryButtonBehavior: .countdown
            )
            let attributes = AlarmAttributes<ProbeAlarmMetadata>(
                presentation: AlarmPresentation(alert: alert),
                tintColor: Palette.inTune
            )
            let configuration = AlarmManager.AlarmConfiguration(
                countdownDuration: Alarm.CountdownDuration(preAlert: 30, postAlert: 60),
                attributes: attributes
            )
            let alarm = try await AlarmManager.shared.schedule(id: UUID(), configuration: configuration)
            alarmStatus = "scheduled, fires at \(Date.now.addingTimeInterval(30).formatted(date: .omitted, time: .standard)) (\(alarm.state))"
            log.info("alarm scheduled \(alarm.id, privacy: .public)")
        } catch {
            alarmStatus = "error: \(error)"
            log.error("alarm failed: \(error, privacy: .public)")
        }
    }
}

// MARK: - Geometry

/// Which half the lamp paints. "Near" is the half before the crease (top or leading), "far" the
/// half after it. Which one actually faces the wall in the tent pose is what we're finding out.
private enum LitHalf: String, CaseIterable {
    case far, near, both, none

    var next: LitHalf {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
    var includesNear: Bool { self == .near || self == .both }
    var includesFar: Bool { self == .far || self == .both }
}

/// Splits the view at the crease. The axis comes from the crease's own shape, never from
/// orientation: a wide, short region is a horizontal crease.
private struct Halves {
    let near: CGRect
    let far: CGRect
    let readout: CGRect
    let axisDescription: String

    init(size: CGSize, crease: CGRect?) {
        let bounds = CGRect(origin: .zero, size: size)
        guard let crease, crease.width > 0 || crease.height > 0 else {
            // No crease reported: split down the middle of the longer side so the probe still
            // shows something, and say so.
            let horizontal = size.height >= size.width
            (near, far) = Halves.split(bounds, horizontal: horizontal, at: horizontal ? size.height / 2 : size.width / 2, gap: 0)
            readout = near
            axisDescription = "none reported (fallback split)"
            return
        }
        let horizontal = crease.width >= crease.height
        let edge = horizontal ? crease.minY : crease.minX
        let gap = horizontal ? crease.height : crease.width
        (near, far) = Halves.split(bounds, horizontal: horizontal, at: edge, gap: gap)
        readout = near
        axisDescription = horizontal ? "horizontal at y=\(Int(edge))" : "vertical at x=\(Int(edge))"
    }

    private static func split(_ bounds: CGRect, horizontal: Bool, at edge: CGFloat, gap: CGFloat) -> (CGRect, CGRect) {
        if horizontal {
            return (CGRect(x: 0, y: 0, width: bounds.width, height: edge),
                    CGRect(x: 0, y: edge + gap, width: bounds.width, height: bounds.height - edge - gap))
        }
        return (CGRect(x: 0, y: 0, width: edge, height: bounds.height),
                CGRect(x: edge + gap, y: 0, width: bounds.width - edge - gap, height: bounds.height))
    }
}

@available(iOS 27.1, *)
private func describe(_ hinge: DeviceHinge?) -> String {
    guard let hinge else { return "unavailable" }
    let status = switch hinge.status {
    case .closed: "closed"
    case .partiallyOpen: "partially open"
    case .fullyOpen: "fully open"
    default: "unknown"
    }
    return "\(status), \(Int(hinge.angle.degrees.rounded()))°"
}

private func format(_ rect: CGRect) -> String {
    "(\(Int(rect.minX)),\(Int(rect.minY)) \(Int(rect.width))×\(Int(rect.height)))"
}

// MARK: - Motion and scenes

@Observable
private final class ProbeMotion {
    private let manager = CMMotionManager()
    private(set) var gravity: CMAcceleration?

    var gravityDescription: String {
        guard manager.isDeviceMotionAvailable else { return "unavailable (simulator?)" }
        guard let g = gravity else { return "waiting" }
        return String(format: "x %+.2f  y %+.2f  z %+.2f", g.x, g.y, g.z)
    }

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 0.1
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            MainActor.assumeIsolated { self?.gravity = motion?.gravity }
        }
    }

    func stop() { manager.stopDeviceMotionUpdates() }
}

private enum ProbeScenes {
    /// Every scene the app can see, with its role and screen. If the outer display ever shows
    /// up as something we can draw on, it appears here.
    static func describe() -> String {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard !scenes.isEmpty else { return "none" }
        return scenes.map { scene in
            let bounds = scene.screen.bounds
            return "\(scene.session.role.rawValue) \(scene.activationState.label) screen \(Int(bounds.width))×\(Int(bounds.height))@\(scene.screen.scale)x"
        }.joined(separator: "\n")
    }
}

private extension UIScene.ActivationState {
    var label: String {
        switch self {
        case .foregroundActive: "active"
        case .foregroundInactive: "inactive"
        case .background: "background"
        case .unattached: "unattached"
        @unknown default: "unknown"
        }
    }
}

nonisolated struct ProbeAlarmMetadata: AlarmMetadata {}
