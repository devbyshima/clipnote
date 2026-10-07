import Foundation

nonisolated enum ClipError: LocalizedError, Equatable {
    case fileMissing
    case notMedia
    case unreadableAudio
    case whisperModelMissing
    case appleSpeechUnavailable
    case appleSpeechLocaleUnsupported(String)

    var errorDescription: String? {
        switch self {
        case .fileMissing:
            "The video file can't be found. It may have been moved, renamed, or deleted."
        case .notMedia:
            "This file has no audio or video Clipnote can read."
        case .unreadableAudio:
            "The video's audio couldn't be decoded."
        case .whisperModelMissing:
            "The Whisper model is missing from the app."
        case .appleSpeechUnavailable:
            "Apple's on-device speech recognition isn't available on this Mac."
        case .appleSpeechLocaleUnsupported(let language):
            "Apple's on-device speech recognition doesn't support \(language)."
        }
    }
}
