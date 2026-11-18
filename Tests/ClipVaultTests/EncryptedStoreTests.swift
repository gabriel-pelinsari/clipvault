import CryptoKit
import Foundation
import Testing
@testable import ClipVault

struct EncryptedStoreTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "clipvault-tests-\(UUID().uuidString)")
    let key = SymmetricKey(size: .bits256)

    @Test func `round-trips data and never writes plaintext`() throws {
        let store = try EncryptedStore(directory: directory, key: key)
        let secret = Data("my secret clipboard".utf8)
        try store.write(secret, named: "history.v1")

        #expect(try store.read(named: "history.v1") == secret)
        let onDisk = try Data(contentsOf: directory.appending(path: "history.v1"))
        #expect(onDisk.range(of: secret) == nil)
    }

    @Test func `restricts file and directory permissions`() throws {
        let store = try EncryptedStore(directory: directory, key: key)
        try store.write(Data("x".utf8), named: "history.v1")

        let fileMode = try FileManager.default.attributesOfItem(atPath: directory.appending(path: "history.v1").path)[.posixPermissions] as? Int
        let dirMode = try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? Int
        #expect(fileMode == 0o600)
        #expect(dirMode == 0o700)
    }

    @Test func `rejects tampered ciphertext`() throws {
        let store = try EncryptedStore(directory: directory, key: key)
        try store.write(Data("payload".utf8), named: "history.v1")
        let url = directory.appending(path: "history.v1")
        var bytes = try Data(contentsOf: url)
        bytes[bytes.count / 2] ^= 0xFF
        try bytes.write(to: url)

        #expect(throws: (any Error).self) { try store.read(named: "history.v1") }
    }

    @Test func `rejects a file moved to another name`() throws {
        let store = try EncryptedStore(directory: directory, key: key)
        try store.write(Data("payload".utf8), named: "image-a.v1")
        try FileManager.default.moveItem(
            at: directory.appending(path: "image-a.v1"), to: directory.appending(path: "image-b.v1")
        )

        #expect(throws: (any Error).self) { try store.read(named: "image-b.v1") }
    }

    @Test func `rejects a different key`() throws {
        try EncryptedStore(directory: directory, key: key).write(Data("payload".utf8), named: "history.v1")
        let other = try EncryptedStore(directory: directory, key: SymmetricKey(size: .bits256))

        #expect(throws: (any Error).self) { try other.read(named: "history.v1") }
    }

    @Test func `missing file reads as nil`() throws {
        let store = try EncryptedStore(directory: directory, key: key)
        #expect(try store.read(named: "nothing.v1") == nil)
    }
}
