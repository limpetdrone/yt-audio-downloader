import Foundation

public enum DownloadQuality: String, CaseIterable, Identifiable {
    case best = "320"
    case high = "256"
    case medium = "192"
    case standard = "128"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .best: return "320 kbps (Best Quality)"
        case .high: return "256 kbps (High)"
        case .medium: return "192 kbps (Recommended)"
        case .standard: return "128 kbps (Compact)"
        }
    }
}

public struct DownloadedTrack: Identifiable, Codable {
    public let id: UUID
    public let title: String
    public let fileName: String
    public let date: Date
    public let quality: String

    public init(id: UUID = UUID(), title: String, fileName: String, date: Date = Date(), quality: String = "320") {
        self.id = id
        self.title = title
        self.fileName = fileName
        self.date = date
        self.quality = quality
    }
}
