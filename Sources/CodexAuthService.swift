import Darwin
import Foundation

final class CodexAuthService {
    private let appServerCacheURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("CodexHub", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport.appendingPathComponent("app-server-quota-cache.json")
    }()

    enum QuotaAPIStatus: Equatable {
        case on
        case off
        case fallback
        case failed

        var label: String {
            switch self {
            case .on: return L.text(ko: "켜짐", en: "On")
            case .off: return L.text(ko: "꺼짐", en: "Off")
            case .fallback: return L.text(ko: "대체 사용", en: "Fallback")
            case .failed: return L.text(ko: "실패", en: "Failed")
            }
        }

        var isHealthy: Bool {
            self != .failed
        }
    }

    func listAccounts(useAPI: Bool) -> (accounts: [CodexAccount], error: String?, quotaAPIStatus: QuotaAPIStatus, autoDisabledAPI: Bool) {
        let result = runCodexAuth(["list"], timeout: 8)
        guard result.status == 0 else {
            let message = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            return ([], message.isEmpty ? L.text(ko: "codex-auth list 실패", en: "codex-auth list failed") : message, .failed, false)
        }

        let parsed = parseAccounts(result.output)
        let fallback = applyAppServerFallbackIfUseful(parsed)
        var status: QuotaAPIStatus = useAPI ? .on : .off
        if fallback.usedAppServer {
            status = .fallback
        }
        let error = parsed.isEmpty ? L.text(ko: "codex-auth 계정을 찾을 수 없습니다", en: "No codex-auth accounts found") : fallback.notice
        return (fallback.accounts, error, status, false)
    }

    func setQuotaAPIEnabled(_ enabled: Bool) -> CommandResult {
        runCodexAuth(["config", "api", enabled ? "enable" : "disable"], timeout: 8)
    }

    func switchTo(_ emailOrSelector: String) -> CommandResult {
        runCodexAuth(["switch", emailOrSelector], timeout: 12)
    }

    func restartCodex() -> CommandResult {
        let quit = run("/usr/bin/osascript", ["-e", "quit app \"Codex\""], timeout: 4)
        Thread.sleep(forTimeInterval: 0.4)
        let open = run("/usr/bin/open", ["-a", "Codex"], timeout: 4)
        return open.status == 0 ? open : quit
    }

    private func parseAccounts(_ output: String) -> [CodexAccount] {
        output.split(whereSeparator: \.isNewline).compactMap { rawLine in
            let tokens = rawLine.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard !tokens.isEmpty else { return nil }
            let isActive = tokens.first == "*"
            let offset = isActive ? 1 : 0
            guard tokens.count >= offset + 3, tokens[offset].allSatisfy(\.isNumber) else { return nil }
            let selector = tokens[offset]
            let email = tokens[offset + 1]
            let plan = tokens[offset + 2]
            var cursor = offset + 3
            let fiveHour = Self.parseUsage(tokens, from: cursor)
            cursor = fiveHour.nextIndex
            let weekly = Self.parseUsage(tokens, from: cursor)
            cursor = weekly.nextIndex
            let lastActivity = tokens.dropFirst(cursor).joined(separator: " ")
            return CodexAccount(
                selector: selector,
                email: email,
                plan: plan,
                fiveHourUsage: fiveHour.text,
                fiveHourUsedPercent: fiveHour.usedPercent,
                weeklyUsage: weekly.text,
                weeklyUsedPercent: weekly.usedPercent,
                lastActivity: lastActivity.isEmpty ? "-" : lastActivity,
                isActive: isActive
            )
        }
    }

    private func applyAppServerFallbackIfUseful(_ accounts: [CodexAccount]) -> (accounts: [CodexAccount], usedAppServer: Bool, notice: String?) {
        guard let active = accounts.first(where: { $0.isActive }) else { return (accounts, false, nil) }
        let needsFallback = active.fiveHourUsedPercent == nil
            || active.weeklyUsedPercent == nil
            || active.weeklyUsage == "-"
            || active.weeklyUsage == "Unavailable"
        guard needsFallback else { return (accounts, false, nil) }
        guard let lookup = readActiveRateLimitsFromCodexAppServer() else {
            let updated = accounts.map { account in
                account.isActive ? account.withUnavailableRateLimitsIfNeeded() : account
            }
            return (updated, false, L.text(ko: "활성 계정의 app-server 할당량을 사용할 수 없습니다", en: "Active account app-server quota unavailable"))
        }
        let limits = lookup.limits
        let updated = accounts.map { account in
            account.isActive ? account.applyingAppServerRateLimits(limits) : account
        }
        let notice = lookup.fromCache
            ? L.text(ko: "활성 계정 할당량에 캐시된 app-server 대체값을 사용 중입니다", en: "Using cached app-server fallback for active account quota only")
            : L.text(ko: "활성 계정 할당량에 app-server 대체값을 사용 중입니다", en: "Using app-server fallback for active account quota only")
        return (updated, true, notice)
    }

    private struct AppServerResponse: Decodable {
        let id: Int?
        let result: AppServerRateLimitResult?
    }

    private struct AppServerRateLimitResult: Decodable {
        let rateLimits: AppServerRateLimitSnapshot?
        let rateLimitsByLimitId: [String: AppServerRateLimitSnapshot]?
    }

    private struct AppServerRateLimitSnapshot: Decodable {
        let primary: AppServerRateLimitWindowPayload?
        let secondary: AppServerRateLimitWindowPayload?
    }

    private struct AppServerRateLimitWindowPayload: Decodable {
        let usedPercent: Double
        let resetsAt: Double?
    }

    private struct AppServerLookup {
        let limits: AppServerRateLimits
        let fromCache: Bool
    }

    private struct AppServerQuotaCache: Codable {
        let savedAt: Date
        let limits: AppServerRateLimits
    }

    private func readActiveRateLimitsFromCodexAppServer() -> AppServerLookup? {
        guard let codexPath = codexCLIPath() else { return nil }
        let request1 = #"{"id":1,"method":"initialize","params":{"clientInfo":{"name":"codexhub","title":"CodexHub","version":"1"},"capabilities":{"experimentalApi":true,"requestAttestation":false,"optOutNotificationMethods":[]}}}"#
        let request2 = #"{"id":2,"method":"account/rateLimits/read"}"#

        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        let stdin = Pipe()
        process.executableURL = URL(fileURLWithPath: codexPath)
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        process.environment = processEnvironment()

        let lock = NSLock()
        let completed = DispatchSemaphore(value: 0)
        let exited = DispatchSemaphore(value: 0)
        var buffer = Data()
        var resolvedLimits: AppServerRateLimits?

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard data.isEmpty == false else { return }
            lock.lock()
            buffer.append(data)
            while let newline = buffer.firstIndex(of: 10) {
                let lineData = buffer[..<newline]
                buffer.removeSubrange(...newline)
                if let line = String(data: lineData, encoding: .utf8),
                   let limits = self?.parseAppServerRateLimitsLine(line) {
                    resolvedLimits = limits
                    completed.signal()
                    break
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
            let payload = "\(request1)\n\(request2)\n"
            if let data = payload.data(using: .utf8) {
                stdin.fileHandleForWriting.write(data)
            }
            try? stdin.fileHandleForWriting.close()
            let timedOut = completed.wait(timeout: .now() + 4) == .timedOut
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
            if !timedOut, let resolvedLimits {
                saveAppServerCache(resolvedLimits)
                return AppServerLookup(limits: resolvedLimits, fromCache: false)
            }
            return loadAppServerCache().map { AppServerLookup(limits: $0, fromCache: true) }
        } catch {
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            return loadAppServerCache().map { AppServerLookup(limits: $0, fromCache: true) }
        }
    }

    private func parseAppServerRateLimitsLine(_ line: String) -> AppServerRateLimits? {
        let decoder = JSONDecoder()
        guard line.contains(#""id":2"#),
              let data = line.data(using: .utf8),
              let response = try? decoder.decode(AppServerResponse.self, from: data) else { return nil }
        let snapshot = response.result?.rateLimitsByLimitId?["codex"] ?? response.result?.rateLimits
        guard let snapshot else { return nil }
        return AppServerRateLimits(
            primary: snapshot.primary.map(makeAppServerWindow),
            secondary: snapshot.secondary.map(makeAppServerWindow)
        )
    }

    private func loadAppServerCache() -> AppServerRateLimits? {
        guard let data = try? Data(contentsOf: appServerCacheURL),
              let cache = try? JSONDecoder.codexHub.decode(AppServerQuotaCache.self, from: data),
              Date().timeIntervalSince(cache.savedAt) < 900 else { return nil }
        return cache.limits
    }

    private func saveAppServerCache(_ limits: AppServerRateLimits) {
        let cache = AppServerQuotaCache(savedAt: Date(), limits: limits)
        guard let data = try? JSONEncoder.codexHub.encode(cache) else { return }
        try? data.write(to: appServerCacheURL, options: .atomic)
    }

    private func makeAppServerWindow(_ payload: AppServerRateLimitWindowPayload) -> AppServerRateLimitWindow {
        let used = Int(payload.usedPercent.rounded())
        let clampedUsed = max(0, min(100, used))
        let reset = payload.resetsAt.map { Date(timeIntervalSince1970: $0) }
        return AppServerRateLimitWindow(displayPercent: clampedUsed, resetsAt: reset)
    }

    private static func parseUsage(_ tokens: [String], from startIndex: Int) -> (text: String, usedPercent: Int?, nextIndex: Int) {
        guard startIndex < tokens.count else { return ("-", nil, startIndex) }
        let first = tokens[startIndex]
        if first == "-" { return ("-", nil, startIndex + 1) }
        if !first.contains("%") {
            if first == "401" || first == "400" { return ("Login expired", nil, startIndex + 1) }
            return ("Unavailable", nil, startIndex + 1)
        }
        var parts = [first]
        var cursor = startIndex + 1
        if cursor < tokens.count, tokens[cursor].hasPrefix("(") {
            while cursor < tokens.count {
                parts.append(tokens[cursor])
                if tokens[cursor].hasSuffix(")") {
                    cursor += 1
                    break
                }
                cursor += 1
            }
        }
        return (parts.joined(separator: " "), firstPercent(in: first), cursor)
    }

    private static func firstPercent(in token: String) -> Int? {
        let digits = token.prefix { $0.isNumber }
        return digits.isEmpty ? nil : Int(digits)
    }

    private func runCodexAuth(_ args: [String], timeout: TimeInterval) -> CommandResult {
        guard let path = codexAuthPath() else {
            return CommandResult(status: 127, output: L.text(ko: "codex-auth를 찾을 수 없습니다", en: "codex-auth was not found"))
        }
        return run(path, args, timeout: timeout)
    }

    private func codexAuthPath() -> String? {
        let home = NSHomeDirectory()
        let nvmNodeDir = URL(fileURLWithPath: "\(home)/.nvm/versions/node")
        if let versions = try? FileManager.default.contentsOfDirectory(at: nvmNodeDir, includingPropertiesForKeys: nil) {
            for versionDir in versions {
                let path = versionDir.appendingPathComponent("bin/codex-auth").path
                if FileManager.default.isExecutableFile(atPath: path) { return path }
            }
        }

        let candidates = [
            "\(home)/.local/bin/codex-auth",
            "/opt/homebrew/bin/codex-auth",
            "/usr/local/bin/codex-auth"
        ]
        if let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return path
        }

        let result = run("/bin/zsh", ["-l", "-c", "which codex-auth"], timeout: 1)
        let path = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.status == 0 && FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }

    private func codexCLIPath() -> String? {
        let candidates = [
            "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ]
        if let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return path
        }

        let result = run("/bin/zsh", ["-l", "-c", "which codex"], timeout: 1)
        let path = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.status == 0 && FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }

    private func processEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "\(NSHomeDirectory())/.nvm/versions/node/v20.20.2/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        let bundledNode = "/Applications/Codex.app/Contents/Resources/node"
        if FileManager.default.isExecutableFile(atPath: bundledNode) {
            environment["CODEX_AUTH_NODE_EXECUTABLE"] = bundledNode
        }
        let bundledCodex = "/Applications/Codex.app/Contents/Resources/codex"
        if FileManager.default.isExecutableFile(atPath: bundledCodex) {
            environment["CODEX_CLI_PATH"] = bundledCodex
        }
        return environment
    }

    private func run(_ executable: String, _ args: [String], timeout: TimeInterval) -> CommandResult {
        let process = Process()
        let pipe = Pipe()
        let lock = NSLock()
        var output = Data()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        process.standardOutput = pipe
        process.standardError = pipe
        process.environment = processEnvironment()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard data.isEmpty == false else { return }
            lock.lock()
            output.append(data)
            lock.unlock()
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
                let text = drainedOutput(from: pipe, accumulated: output, lock: lock)
                return CommandResult(status: 124, output: L.text(ko: "명령 시간이 초과되었습니다", en: "Command timed out") + ": \(URL(fileURLWithPath: executable).lastPathComponent) \(args.joined(separator: " "))\n\(text)")
            }
            pipe.fileHandleForReading.readabilityHandler = nil
            return CommandResult(status: process.terminationStatus, output: drainedOutput(from: pipe, accumulated: output, lock: lock))
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            return CommandResult(status: 127, output: error.localizedDescription)
        }
    }

    private func drainedOutput(from pipe: Pipe, accumulated: Data, lock: NSLock) -> String {
        lock.lock()
        var data = accumulated
        lock.unlock()
        data.append(pipe.fileHandleForReading.readDataToEndOfFile())
        return String(data: data, encoding: .utf8) ?? ""
    }
}
