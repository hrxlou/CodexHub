import Darwin
import Foundation

struct ProcessRunner {
    var run: (_ executable: String, _ args: [String], _ timeout: TimeInterval, _ environment: [String: String]) -> CommandResult

    static let live = ProcessRunner { executable, args, timeout, environment in
        let process = Process()
        let pipe = Pipe()
        let outputLock = NSLock()
        var output = Data()

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        process.standardOutput = pipe
        process.standardError = pipe
        process.environment = environment

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard data.isEmpty == false else { return }
            outputLock.lock()
            output.append(data)
            outputLock.unlock()
        }

        do {
            try process.run()
            let semaphore = DispatchSemaphore(value: 0)
            DispatchQueue.global(qos: .utility).async {
                process.waitUntilExit()
                semaphore.signal()
            }

            if semaphore.wait(timeout: .now() + timeout) == .timedOut {
                if process.isRunning {
                    process.terminate()
                }
                if semaphore.wait(timeout: .now() + 1) == .timedOut, process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                    _ = semaphore.wait(timeout: .now() + 1)
                }
                pipe.fileHandleForReading.readabilityHandler = nil
                return CommandResult(status: 124, output: L.text(ko: "명령 실행 시간이 초과됐습니다", en: "Command timed out"))
            }

            pipe.fileHandleForReading.readabilityHandler = nil
            return CommandResult(
                status: process.terminationStatus,
                output: drainedOutput(from: pipe, accumulated: output, lock: outputLock)
            )
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            return CommandResult(status: 127, output: error.localizedDescription)
        }
    }

    private static func drainedOutput(from pipe: Pipe, accumulated: Data, lock: NSLock) -> String {
        lock.lock()
        var data = accumulated
        lock.unlock()
        data.append(pipe.fileHandleForReading.readDataToEndOfFile())
        return String(data: data, encoding: .utf8) ?? ""
    }
}

enum CodexProcessEnvironment {
    static func make(
        prependingExecutableDirectory executable: String? = nil,
        includeBundledCodexPath: Bool = false,
        overrides: [String: String] = [:]
    ) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let currentPath = environment["PATH"] ?? ""
        var pathEntries: [String] = []
        if let executable {
            pathEntries.append(URL(fileURLWithPath: executable).deletingLastPathComponent().path)
        }
        pathEntries.append(contentsOf: [
            "\(NSHomeDirectory())/.local/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ])
        if !currentPath.isEmpty {
            pathEntries.append(currentPath)
        }
        environment["PATH"] = pathEntries.joined(separator: ":")

        let bundledCodex = "/Applications/Codex.app/Contents/Resources/codex"
        if includeBundledCodexPath, FileManager.default.isExecutableFile(atPath: bundledCodex) {
            environment["CODEX_CLI_PATH"] = bundledCodex
        }

        for (key, value) in overrides {
            environment[key] = value
        }
        return environment
    }
}
