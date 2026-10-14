import OpenNoTypeCore

enum DictationProcessingMode: String, Codable, CaseIterable, Identifiable {
    case aiCleanup, onDeviceVerbatim
    var id: String { rawValue }
    var title: String {
        switch self {
        case .aiCleanup: L("정리해서 입력", "Clean up before typing")
        case .onDeviceVerbatim: L("빠른 로컬 받아쓰기", "Quick on-device dictation")
        }
    }
}
