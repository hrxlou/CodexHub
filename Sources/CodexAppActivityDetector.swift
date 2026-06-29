import Darwin
import Foundation

struct CodexAppThreadActivity: Equatable {
    var loadedThreadCount: Int
    var activeThreadCount: Int
    var waitingOnApprovalCount: Int
    var waitingOnUserInputCount: Int

    var hasActiveThreads: Bool {
        activeThreadCount > 0
    }
}

enum CodexAppThreadActivityParser {
    static func parseLoadedThreadIDs(from line: String, responseID: Int) -> [String]? {
        guard let dictionary = jsonDictionary(from: line),
              dictionary["id"] as? Int == responseID,
              let result = dictionary["result"] as? [String: Any],
              let data = result["data"] as? [String] else {
            return nil
        }
        return data
    }

    static func parseThreadReadStatus(from line: String, responseID: Int) -> (isActive: Bool, activeFlags: [String])? {
        guard let dictionary = jsonDictionary(from: line),
              dictionary["id"] as? Int == responseID,
              let result = dictionary["result"] as? [String: Any],
              let thread = result["thread"] as? [String: Any],
              let status = thread["status"] as? [String: Any],
              let type = status["type"] as? String else {
            return nil
        }
        let flags = status["activeFlags"] as? [String] ?? []
        return (type == "active", flags)
    }

    private static func jsonDictionary(from line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            return nil
        }
        return dictionary
    }
}

final class CodexAppActivityDetector {
    private let codexPathProvider: () -> String?
    private let timeout: TimeInterval

    init(codexPathProvider: @escaping () -> String?, timeout: TimeInterval = 1.5) {
        self.codexPathProvider = codexPathProvider
        self.timeout = timeout
    }

    func readThreadActivity() -> CodexAppThreadActivity? {
        guard let codexPath = codexPathProvider() else { return nil }

        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        let stdin = Pipe()
        process.executableURL = URL(fileURLWithPath: codexPath)
        process.arguments = ["app-server", "proxy"]
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        process.environment = CodexProcessEnvironment.make(
            prependingExecutableDirectory: codexPath,
            includeBundledCodexPath: true
        )

        let lock = NSLock()
        let loaded = DispatchSemaphore(value: 0)
        let readsCompleted = DispatchSemaphore(value: 0)
        let exited = DispatchSemaphore(value: 0)
        var buffer = Data()
        var loadedThreadIDs: [String]?
        var expectedReadIDs: Set<Int> = []
        var readResults: [(isActive: Bool, activeFlags: [String])] = []

        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard data.isEmpty == false else { return }
            lock.lock()
            buffer.append(data)
            while let newline = buffer.firstIndex(of: 10) {
                let lineData = buffer[..<newline]
                buffer.removeSubrange(...newline)
                guard let line = String(data: lineData, encoding: .utf8) else { continue }
                if loadedThreadIDs == nil,
                   let ids = CodexAppThreadActivityParser.parseLoadedThreadIDs(from: line, responseID: 2) {
                    loadedThreadIDs = ids
                    loaded.signal()
                    continue
                }
                if let matchedResponse = expectedReadIDs.first(where: {
                    CodexAppThreadActivityParser.parseThreadReadStatus(from: line, responseID: $0) != nil
                }),
                   let result = CodexAppThreadActivityParser.parseThreadReadStatus(from: line, responseID: matchedResponse) {
                    expectedReadIDs.remove(matchedResponse)
                    readResults.append(result)
                    if expectedReadIDs.isEmpty {
                        readsCompleted.signal()
                    }
                }
            }
            lock.unlock()
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }

        do {
            try process.run()
            DispatchQueue.global(qos: .utility).async {
                process.waitUntilExit()
                exited.signal()
            }

            writeJSON([
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": [
                    "clientInfo": ["name": "codexhub", "title": "CodexHub", "version": "1"],
                    "capabilities": ["experimentalApi": true, "requestAttestation": false, "optOutNotificationMethods": []]
                ]
            ], to: stdin)
            writeJSON([
                "jsonrpc": "2.0",
                "id": 2,
                "method": "thread/loaded/list",
                "params": [String: Any]()
            ], to: stdin)

            guard loaded.wait(timeout: .now() + timeout) == .success else {
                cleanup(process: process, stdin: stdin, stdout: stdout, stderr: stderr, exited: exited)
                return nil
            }

            lock.lock()
            let threadIDs = loadedThreadIDs ?? []
            expectedReadIDs = Set((0..<threadIDs.count).map { $0 + 3 })
            lock.unlock()

            guard threadIDs.isEmpty == false else {
                cleanup(process: process, stdin: stdin, stdout: stdout, stderr: stderr, exited: exited)
                return CodexAppThreadActivity(loadedThreadCount: 0, activeThreadCount: 0, waitingOnApprovalCount: 0, waitingOnUserInputCount: 0)
            }

            for (index, threadID) in threadIDs.enumerated() {
                writeJSON([
                    "jsonrpc": "2.0",
                    "id": index + 3,
                    "method": "thread/read",
                    "params": ["threadId": threadID, "includeTurns": false]
                ], to: stdin)
            }

            guard readsCompleted.wait(timeout: .now() + timeout) == .success else {
                cleanup(process: process, stdin: stdin, stdout: stdout, stderr: stderr, exited: exited)
                return nil
            }

            cleanup(process: process, stdin: stdin, stdout: stdout, stderr: stderr, exited: exited)

            lock.lock()
            let results = readResults
            lock.unlock()
            return CodexAppThreadActivity(
                loadedThreadCount: threadIDs.count,
                activeThreadCount: results.filter(\.isActive).count,
                waitingOnApprovalCount: results.filter { $0.activeFlags.contains("waitingOnApproval") }.count,
                waitingOnUserInputCount: results.filter { $0.activeFlags.contains("waitingOnUserInput") }.count
            )
        } catch {
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            return nil
        }
    }

    private func writeJSON(_ object: [String: Any], to pipe: Pipe) {
        guard JSONSerialization.isValidJSONObject(object),
              var data = try? JSONSerialization.data(withJSONObject: object) else {
            return
        }
        data.append(10)
        pipe.fileHandleForWriting.write(data)
    }

    private func cleanup(
        process: Process,
        stdin: Pipe,
        stdout: Pipe,
        stderr: Pipe,
        exited: DispatchSemaphore
    ) {
        try? stdin.fileHandleForWriting.close()
        if process.isRunning {
            process.terminate()
            if exited.wait(timeout: .now() + 1) == .timedOut, process.isRunning {
                kill(process.processIdentifier, SIGKILL)
                _ = exited.wait(timeout: .now() + 1)
            }
        } else {
            _ = exited.wait(timeout: .now())
        }
        stdout.fileHandleForReading.readabilityHandler = nil
        stderr.fileHandleForReading.readabilityHandler = nil
    }
}
