#if canImport(AVFAudio)
import AVFAudio
#endif

/// Microphone permission, wrapped so the app layer doesn't need to know which platform it's on.
public enum MicrophoneAccess {

    public enum Status: Sendable, Hashable {
        case granted
        case denied
        case undetermined
    }

    public static var status: Status {
        #if os(iOS)
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return .granted
        case .denied: return .denied
        default: return .undetermined
        }
        #else
        // macOS grants through TCC at first use; there is nothing to ask for up front.
        return .granted
        #endif
    }

    /// Prompts if the user hasn't been asked yet. Safe to call every launch — the system only
    /// shows the alert once.
    public static func request() async -> Bool {
        #if os(iOS)
        // Asking again while a prompt is already on screen fails immediately, so never ask when
        // the answer is already known.
        if status == .granted { return true }
        return await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        #else
        return true
        #endif
    }
}
