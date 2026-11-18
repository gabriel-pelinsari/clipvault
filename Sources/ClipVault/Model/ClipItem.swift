import CryptoKit
import Foundation

/// One entry in the clipboard history.
///
/// Image bytes live in their own encrypted file; the item only carries what the
/// list needs to render without decrypting them.
nonisolated struct ClipItem: Codable, Identifiable, Hashable, Sendable {
    nonisolated enum Content: Codable, Hashable, Sendable {
        case text(String)
        case image(width: Int, height: Int, byteCount: Int)
    }

    let id: UUID
    let content: Content
    /// SHA-256 of the content, used to collapse repeated copies into one entry.
    let digest: String
    let createdAt: Date
    var lastCopiedAt: Date
    var isPinned: Bool
    var sourceAppName: String?
    var sourceBundleID: String?

    var text: String? {
        switch content {
        case .text(let text): text
        case .image: nil
        }
    }

    var isImage: Bool {
        switch content {
        case .text: false
        case .image: true
        }
    }

    func matches(_ query: String) -> Bool {
        if let text, text.localizedStandardContains(query) { return true }
        if let sourceAppName, sourceAppName.localizedStandardContains(query) { return true }
        return isImage && "imagem image".localizedStandardContains(query)
    }
}

/// Content read from the pasteboard, before it becomes a `ClipItem`.
nonisolated enum CapturedContent: Sendable, Equatable {
    case text(String)
    case image(png: Data, width: Int, height: Int)

    var digest: String {
        var hasher = SHA256()
        switch self {
        case .text(let text):
            hasher.update(data: Data("text:".utf8))
            hasher.update(data: Data(text.utf8))
        case .image(let png, _, _):
            hasher.update(data: Data("image:".utf8))
            hasher.update(data: png)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// The app that was frontmost when something was copied.
nonisolated struct SourceApp: Equatable, Sendable {
    let bundleID: String?
    let name: String?
}
