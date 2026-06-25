import Darwin
import Foundation

final class CodexAuthService {
    private let accountStore = CodexAccountStore()
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
            case .fallback: return L.text(ko: "참고 표시", en: "Fallback")
            case .failed: return L.text(ko: "실패", en: "Failed")
            }
        }

        var isHealthy: Bool {
            self != .failed
        }
    }

    func listAccounts(useAPI: Bool) -> (accounts: [CodexAccount], error: String?, quotaAPIStatus: QuotaAPIStatus, autoDisabledAPI: Bool) {
        let loaded = accountStore.loadAccounts()
        guard useAPI else {
            return (loaded.accounts, loaded.error, .off, false)
        }
        let lookup = applyAppServerRateLimitsIfUseful(loaded.accounts)
        let status: QuotaAPIStatus = lookup.usedLiveAppServer ? .on : (lookup.usedFallback ? .fallback : .failed)
        return (lookup.accounts, loaded.error, status, false)
    }

    func setQuotaAPIEnabled(_ enabled: Bool) -> CommandResult {
        CommandResult(status: 0, output: enabled ? L.quotaAPIEnabled : L.quotaAPIDisabled)
    }

    func startCodexLogin(mode: LoginMode) -> CommandResult {
        accountStore.startCodexLogin(mode: mode)
    }

    func captureCurrentLogin(alias: String?) -> CommandResult {
        accountStore.captureCurrentLogin(alias: alias)
    }

    func switchTo(_ emailOrSelector: String, useAPI: Bool) -> CommandResult {
        if useAPI {
            saveActiveUsageSnapshotIfPossible()
        }
        return accountStore.switchAccount(identity: emailOrSelector)
    }

    func removeStoredAccount(_ identity: String) -> CommandResult {
        accountStore.removeStoredAccount(identity: identity)
    }

    private func applyAppServerRateLimitsIfUseful(_ accounts: [CodexAccount]) -> (accounts: [CodexAccount], usedLiveAppServer: Bool, usedFallback: Bool) {
        guard let active = accounts.first(where: { $0.isActive }) else { return (accounts, false, false) }
        if let lookup = readActiveRateLimitsFromCodexAppServer(accountIdentity: active.identity) {
            accountStore.updateStoredUsage(identity: active.identity, limits: lookup.limits)
            let updated = accounts.map { account in
                account.isActive ? account.applyingAppServerRateLimits(lookup.limits) : account
            }
            return (updated, !lookup.fromCache, lookup.fromCache)
        }

        return (accounts, false, false)
    }

    private func saveActiveUsageSnapshotIfPossible() {
        let loaded = accountStore.loadAccounts()
        guard let active = loaded.accounts.first(where: { $0.isActive }),
              let lookup = readActiveRateLimitsFromCodexAppServer(accountIdentity: active.identity) else {
            return
        }
        accountStore.updateStoredUsage(identity: active.identity, limits: lookup.limits)
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

        enum CodingKeys: String, CodingKey {
            case usedPercent
            case resetsAt
            case usedPercentSnake = "used_percent"
            case resetsAtSnake = "resets_at"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            usedPercent = try container.decodeIfPresent(Double.self, forKey: .usedPercent)
                ?? container.decode(Double.self, forKey: .usedPercentSnake)
            resetsAt = try container.decodeIfPresent(Double.self, forKey: .resetsAt)
                ?? container.decodeIfPresent(Double.self, forKey: .resetsAtSnake)
        }
    }

    private struct AppServerLookup {
        let limits: AppServerRateLimits
        let fromCache: Bool
    }

    private struct AppServerQuotaCache: Codable {
        let accountIdentity: String?
        let savedAt: Date
        let limits: AppServerRateLimits
    }

    private func readActiveRateLimitsFromCodexAppServer(accountIdentity: String) -> AppServerLookup? {
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
        process.environment = processEnvironment(prependingExecutableDirectory: codexPath)

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
                saveAppServerCache(resolvedLimits, accountIdentity: accountIdentity)
                return AppServerLookup(limits: resolvedLimits, fromCache: false)
            }
            return loadAppServerCache(accountIdentity: accountIdentity).map { AppServerLookup(limits: $0, fromCache: true) }
        } catch {
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            return loadAppServerCache(accountIdentity: accountIdentity).map { AppServerLookup(limits: $0, fromCache: true) }
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

    private func loadAppServerCache(accountIdentity: String) -> AppServerRateLimits? {
        guard let data = try? Data(contentsOf: appServerCacheURL),
              let cache = try? JSONDecoder.codexHub.decode(AppServerQuotaCache.self, from: data),
              cache.accountIdentity == accountIdentity,
              Date().timeIntervalSince(cache.savedAt) < 900 else { return nil }
        return cache.limits
    }

    private func saveAppServerCache(_ limits: AppServerRateLimits, accountIdentity: String) {
        let cache = AppServerQuotaCache(accountIdentity: accountIdentity, savedAt: Date(), limits: limits)
        guard let data = try? JSONEncoder.codexHub.encode(cache) else { return }
        try? data.write(to: appServerCacheURL, options: .atomic)
    }

    private func makeAppServerWindow(_ payload: AppServerRateLimitWindowPayload) -> AppServerRateLimitWindow {
        let used = Int(payload.usedPercent.rounded())
        let clampedUsed = max(0, min(100, used))
        let reset = payload.resetsAt.map { Date(timeIntervalSince1970: $0) }
        return AppServerRateLimitWindow(displayPercent: clampedUsed, resetsAt: reset)
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

    private func processEnvironment(prependingExecutableDirectory executable: String? = nil) -> [String: String] {
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
        process.environment = processEnvironment(prependingExecutableDirectory: executable)
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
                return CommandResult(status: 124, output: L.text(ko: "명령 실행 시간이 초과됐습니다", en: "Command timed out") + ": \(URL(fileURLWithPath: executable).lastPathComponent) \(args.joined(separator: " "))\n\(text)")
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
