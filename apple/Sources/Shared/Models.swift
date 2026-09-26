import Foundation

public enum DownloadType: String, CaseIterable, Identifiable, Codable {
    case audio = "audio"
    case video = "video"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .audio: return "Audio (MP3)"
        case .video: return "Video (MP4)"
        }
    }
}

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
    public let isVideo: Bool

    public init(id: UUID = UUID(), title: String, fileName: String, date: Date = Date(), quality: String = "320", isVideo: Bool = false) {
        self.id = id
        self.title = title
        self.fileName = fileName
        self.date = date
        self.quality = quality
        self.isVideo = isVideo
    }

    enum CodingKeys: String, CodingKey {
        case id, title, fileName, date, quality, isVideo
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.title = try container.decode(String.self, forKey: .title)
        self.fileName = try container.decode(String.self, forKey: .fileName)
        self.date = try container.decode(Date.self, forKey: .date)
        self.quality = try container.decode(String.self, forKey: .quality)
        self.isVideo = try container.decodeIfPresent(Bool.self, forKey: .isVideo) ?? fileName.hasSuffix(".mp4")
    }
}
