import AppKit

enum Formatting {
    static let locale = Locale(identifier: "pt_BR")

    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .short
        return formatter
    }()

    private static let bytes: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    static func relativeTime(_ date: Date, now: Date = .now) -> String {
        now.timeIntervalSince(date) < 5 ? "agora" : relative.localizedString(for: date, relativeTo: now)
    }

    static func dateTime(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(locale))
    }

    static func byteCount(_ count: Int) -> String {
        bytes.string(fromByteCount: Int64(count))
    }

    static func number(_ value: Int) -> String {
        value.formatted(.number.locale(locale))
    }
}

extension ClipItem {
    /// One-line label for the list.
    var title: String {
        switch content {
        case .text(let text):
            let firstLine = text.split(whereSeparator: \.isNewline)
                .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
            let collapsed = firstLine.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            return String(collapsed.prefix(240))
        case .image(let width, let height, _):
            return "Imagem \(width) × \(height)"
        }
    }

    var sizeDescription: String {
        switch content {
        case .text(let text):
            let lines = text.trimmingCharacters(in: .newlines)
                .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).count
            let characters = "\(Formatting.number(text.count)) caractere\(text.count == 1 ? "" : "s")"
            return lines > 1 ? "\(characters) · \(Formatting.number(lines)) linhas" : characters
        case .image(let width, let height, let byteCount):
            return "\(width) × \(height) px · \(Formatting.byteCount(byteCount))"
        }
    }
}

/// Caches app icons by bundle identifier.
enum AppIcons {
    private static var cache: [String: NSImage] = [:]

    static func icon(for bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        if let cached = cache[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        cache[bundleID] = icon
        return icon
    }
}
