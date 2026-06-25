import Foundation

enum LocalStorageSecurity {
    private static let fileManager = FileManager.default

    static func codexHubApplicationSupportDirectory() -> URL {
        let directory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("CodexHub", isDirectory: true)
        try? createPrivateDirectory(at: directory)
        return directory
    }

    static func createPrivateDirectory(at url: URL) throws {
        try fileManager.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }

    static func setPrivateFilePermissions(_ url: URL) throws {
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static func writePrivateFileAtomically(_ data: Data, to url: URL, hardenParentDirectory: Bool = true) throws {
        let directory = url.deletingLastPathComponent()
        if hardenParentDirectory {
            try createPrivateDirectory(at: directory)
        }

        let temporaryURL = directory
            .appendingPathComponent(".\(url.lastPathComponent).tmp-\(UUID().uuidString)")
        var didCreateTemporaryFile = false
        do {
            didCreateTemporaryFile = fileManager.createFile(
                atPath: temporaryURL.path,
                contents: nil,
                attributes: [.posixPermissions: 0o600]
            )
            guard didCreateTemporaryFile else {
                throw CocoaError(.fileWriteUnknown)
            }
            try setPrivateFilePermissions(temporaryURL)
            let handle = try FileHandle(forWritingTo: temporaryURL)
            handle.write(data)
            try? handle.synchronize()
            try? handle.close()
            try setPrivateFilePermissions(temporaryURL)

            if fileManager.fileExists(atPath: url.path) {
                _ = try fileManager.replaceItemAt(url, withItemAt: temporaryURL)
            } else {
                try fileManager.moveItem(at: temporaryURL, to: url)
            }
            try setPrivateFilePermissions(url)
        } catch {
            if didCreateTemporaryFile || fileManager.fileExists(atPath: temporaryURL.path) {
                try? fileManager.removeItem(at: temporaryURL)
            }
            throw error
        }
    }
}
