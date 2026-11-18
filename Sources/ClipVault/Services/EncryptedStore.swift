import CryptoKit
import Foundation

/// A directory of AES-256-GCM sealed files.
///
/// Each file's name is bound into the ciphertext as authenticated data, so files
/// can't be swapped or renamed without failing authentication on read.
nonisolated struct EncryptedStore: Sendable {
    enum Failure: Error {
        case sealingFailed
    }

    let directory: URL
    private let key: SymmetricKey

    init(directory: URL, key: SymmetricKey) throws {
        self.directory = directory
        self.key = key
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }

    func write(_ plaintext: Data, named name: String) throws {
        let box = try AES.GCM.seal(plaintext, using: key, authenticating: Data(name.utf8))
        guard let sealed = box.combined else { throw Failure.sealingFailed }
        let url = fileURL(name)
        try sealed.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    /// Returns `nil` when the file doesn't exist; throws when it exists but fails authentication.
    func read(named name: String) throws -> Data? {
        let url = fileURL(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let box = try AES.GCM.SealedBox(combined: Data(contentsOf: url))
        return try AES.GCM.open(box, using: key, authenticating: Data(name.utf8))
    }

    func delete(named name: String) {
        try? FileManager.default.removeItem(at: fileURL(name))
    }

    func fileNames() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
    }

    func deleteAll() {
        fileNames().forEach(delete(named:))
    }

    private func fileURL(_ name: String) -> URL {
        precondition(!name.contains("/") && !name.hasPrefix("."), "Invalid store file name: \(name)")
        return directory.appending(path: name, directoryHint: .notDirectory)
    }
}
