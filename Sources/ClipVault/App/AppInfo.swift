import Foundation

nonisolated enum AppInfo {
    static let bundleID = "io.github.gabriel-pelinsari.ClipVault"
    static let repositoryURL = URL(string: "https://github.com/gabriel-pelinsari/clipvault")!

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}
