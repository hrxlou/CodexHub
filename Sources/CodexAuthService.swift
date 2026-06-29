import Darwin
import AppKit
import Foundation

final class CodexAuthService {
    private let accountStore: CodexAccountStore
    private let appServerCacheURL: URL
    private let processRunner: ProcessRunner
    private lazy var appActivityDetector = CodexAppActivityDetector { [weak self] in
        self?.codexCLIPath()
    }

    init(
        accountStore: CodexAccountStore = CodexAccountStore(),
        appServerCacheURL: URL? = nil,
        processRunner: ProcessRunner = .live
    ) {
        self.accountStore = accountStore
        let appSupport = LocalStorageSecurity.codexHubApplicationSupportDirectory()
        self.appServerCacheURL = appServerCacheURL ?? appSupport.appendingPathComponent("app-server-quota-cache.json")
        self.processRunner = processRunner
        if FileManager.default.fileExists(atPath: self.appServerCacheURL.path) {
            try? LocalStorageSecurity.setPrivateFilePermissions(self.appServerCacheURL)
        }
    }

    enum QuotaAPIStatus: Equatable {
        case on
        case off
        case fallback
        case failed

        var label: String {
            switch self {
            case .on: return L.text(ko: "켜짐", en: "On")
            case .off: return L.text(ko: "꺼짐", en: "Off")
            case .fallback: return L.text(ko: "로컬 기록", en: "Local records")
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
            let local = applyLocalRateLimitsIfUseful(loaded.accounts)
            return (local.accounts, loaded.error, local.usedLocalState ? .fallback : .off, false)
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

    func loginAndStoreAccount(mode: LoginMode) -> AccountLoginResult {
        accountStore.loginAndStoreIsolated(mode: mode, alias: nil)
    }

    func captureCurrentLogin(alias: String?) -> CommandResult {
        accountStore.captureCurrentLogin(alias: alias)
    }

    func currentLoginIdentity() -> String? {
        accountStore.currentLoginIdentity()
    }

    func waitForCurrentLoginIdentity(preferDifferentFrom previousIdentity: String?, timeout: TimeInterval) -> String? {
        accountStore.waitForCurrentLoginIdentity(preferDifferentFrom: previousIdentity, timeout: timeout)
    }

    func switchTo(_ emailOrSelector: String, useAPI: Bool) -> CommandResult {
        if useAPI {
            saveActiveUsageSnapshotIfPossible()
        }
        let result = accountStore.switchAccount(identity: emailOrSelector)
        if result.status == 0 {
            switch restartCodexDesktopAppIfRunning() {
            case .restarted, .notRunning:
                return result
            case .terminationBlocked:
                return CommandResult(status: 0, output: L.codexRestartBlockedByInterrupt)
            case .failed:
                return CommandResult(status: 0, output: L.codexRestartRequired)
            }
        }
        return result
    }

    func codexAppThreadActivity() -> CodexAppThreadActivity? {
        appActivityDetector.readThreadActivity()
    }

    func removeStoredAccount(_ identity: String) -> CommandResult {
        accountStore.removeStoredAccount(identity: identity)
    }

    private func applyAppServerRateLimitsIfUseful(_ accounts: [CodexAccount]) -> (accounts: [CodexAccount], usedLiveAppServer: Bool, usedFallback: Bool) {
        var limitsByIdentity: [String: AppServerLookup] = [:]
        var usedLiveAppServer = false
        var usedFallback = false

        for account in accounts {
            let lookup = account.isActive
                ? readRateLimitsFromCodexAppServer(accountIdentity: account.identity)
                : readRateLimitsFromStoredAccountSnapshot(accountIdentity: account.identity)
            guard let lookup else { continue }
            limitsByIdentity[account.identity] = lookup
            accountStore.updateStoredUsage(identity: account.identity, limits: lookup.limits)
            if lookup.fromCache {
                usedFallback = true
            } else {
                usedLiveAppServer = true
            }
        }

        guard limitsByIdentity.isEmpty == false else {
            let local = applyLocalRateLimitsIfUseful(accounts)
            return (local.accounts, false, local.usedLocalState)
        }

        let updated = accounts.map { account in
            guard let lookup = limitsByIdentity[account.identity] else { return account }
            return account.applyingAppServerRateLimits(lookup.limits)
        }
        return (updated, usedLiveAppServer, usedFallback)
    }

    private func applyLocalRateLimitsIfUseful(_ accounts: [CodexAccount]) -> (accounts: [CodexAccount], usedLocalState: Bool) {
        guard let active = accounts.first(where: { $0.isActive }),
              let lookup = readActiveRateLimitsFromLocalSessions(since: active.lastUsedAt) else {
            return (accounts, false)
        }
        accountStore.updateStoredUsage(identity: active.identity, limits: lookup.limits)
        let updated = accounts.map { account in
            account.isActive ? account.applyingAppServerRateLimits(lookup.limits) : account
        }
        return (updated, true)
    }

    private func saveActiveUsageSnapshotIfPossible() {
        let loaded = accountStore.loadAccounts()
        guard let active = loaded.accounts.first(where: { $0.isActive }),
              let lookup = readRateLimitsFromCodexAppServer(accountIdentity: active.identity) else {
            return
        }
        accountStore.updateStoredUsage(identity: active.identity, limits: lookup.limits)
    }

    private func restartCodexDesktopAppIfRunning() -> CodexRestartResult {
        let codexBundleIdentifier = "com.openai.codex"
        let codexAppURL = URL(fileURLWithPath: "/Applications/Codex.app", isDirectory: true)
        let workspace = NSWorkspace.shared
        let runningCodexApps = runningCodexDesktopApplications(
            workspace: workspace,
            bundleIdentifier: codexBundleIdentifier,
            appURL: codexAppURL
        )
        guard runningCodexApps.isEmpty == false else { return .notRunning }
        let reopenURL = runningCodexApps.first?.bundleURL ?? codexAppURL

        for app in runningCodexApps {
            _ = app.terminate()
        }

        let terminationDeadline = Date().addingTimeInterval(45)
        while Date() < terminationDeadline {
            let stillRunning = runningCodexDesktopApplications(
                workspace: workspace,
                bundleIdentifier: codexBundleIdentifier,
                appURL: codexAppURL
            )
            if stillRunning.isEmpty {
                break
            }
            Thread.sleep(forTimeInterval: 0.25)
        }

        guard runningCodexDesktopApplications(
            workspace: workspace,
            bundleIdentifier: codexBundleIdentifier,
            appURL: codexAppURL
        ).isEmpty else {
            return .terminationBlocked
        }

        guard FileManager.default.fileExists(atPath: reopenURL.path) else { return .failed }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        let opened = DispatchSemaphore(value: 0)
        var didOpen = false
        workspace.openApplication(at: reopenURL, configuration: configuration) { app, error in
            didOpen = app != nil && error == nil
            opened.signal()
        }
        guard opened.wait(timeout: .now() + 10) == .success, didOpen else {
            return .failed
        }
        let launchDeadline = Date().addingTimeInterval(10)
        while Date() < launchDeadline {
            if runningCodexDesktopApplications(
                workspace: workspace,
                bundleIdentifier: codexBundleIdentifier,
                appURL: codexAppURL
            ).isEmpty == false {
                return .restarted
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return .failed
    }

    private func runningCodexDesktopApplications(
        workspace: NSWorkspace,
        bundleIdentifier: String,
        appURL: URL
    ) -> [NSRunningApplication] {
        workspace.runningApplications.filter { app in
            app.isTerminated == false && (
                app.bundleIdentifier == bundleIdentifier
                || app.bundleURL?.standardizedFileURL == appURL.standardizedFileURL
            )
        }
    }

    private enum CodexRestartResult {
        case restarted
        case notRunning
        case terminationBlocked
        case failed
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

    private struct AppServerQuotaCacheEntry: Codable {
        let savedAt: Date
        let limits: AppServerRateLimits
    }

    private struct AppServerQuotaCacheStore: Codable {
        var accounts: [String: AppServerQuotaCacheEntry]
    }

    private struct LocalSessionRateLimitEvent: Decodable {
        let type: String
        let payload: Payload?

        struct Payload: Decodable {
            let type: String?
            let rateLimits: LocalSessionRateLimits?

            enum CodingKeys: String, CodingKey {
                case type
                case rateLimits = "rate_limits"
            }
        }
    }

    private struct LocalSessionRateLimits: Decodable {
        let limitId: String?
        let primary: AppServerRateLimitWindowPayload?
        let secondary: AppServerRateLimitWindowPayload?

        enum CodingKeys: String, CodingKey {
            case limitId = "limit_id"
            case primary
            case secondary
        }
    }

    private func readRateLimitsFromStoredAccountSnapshot(accountIdentity: String) -> AppServerLookup? {
        guard let temporaryCodexHome = accountStore.makeTemporaryCodexHome(for: accountIdentity) else {
            return nil
        }
        defer {
            accountStore.removeTemporaryCodexHome(temporaryCodexHome)
        }
        let lookup = readRateLimitsFromCodexAppServer(accountIdentity: accountIdentity, codexHome: temporaryCodexHome)
        if lookup?.fromCache == false {
            accountStore.updateStoredAuthSnapshot(identity: accountIdentity, fromTemporaryCodexHome: temporaryCodexHome)
        }
        return lookup
    }

    private func readRateLimitsFromCodexAppServer(accountIdentity: String, codexHome: URL? = nil) -> AppServerLookup? {
        guard let codexPath = codexCLIPath() else { return nil }
        let request1 = #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"codexhub","title":"CodexHub","version":"1"},"capabilities":{"experimentalApi":true,"requestAttestation":false,"optOutNotificationMethods":[]}}}"#
        let request2 = #"{"jsonrpc":"2.0","id":2,"method":"account/rateLimits/read"}"#

        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        let stdin = Pipe()
        process.executableURL = URL(fileURLWithPath: codexPath)
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        var environment = CodexProcessEnvironment.make(
            prependingExecutableDirectory: codexPath,
            includeBundledCodexPath: true
        )
        if let codexHome {
            environment["CODEX_HOME"] = codexHome.path
        }
        process.environment = environment

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
            let timedOut = completed.wait(timeout: .now() + 4) == .timedOut
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
            lock.lock()
            let limits = resolvedLimits
            lock.unlock()
            if !timedOut, let limits {
                saveAppServerCache(limits, accountIdentity: accountIdentity)
                return AppServerLookup(limits: limits, fromCache: false)
            }
            return loadAppServerCache(accountIdentity: accountIdentity).map { AppServerLookup(limits: $0, fromCache: true) }
        } catch {
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            return loadAppServerCache(accountIdentity: accountIdentity).map { AppServerLookup(limits: $0, fromCache: true) }
        }
    }

    private func readActiveRateLimitsFromLocalSessions(since: Date?) -> AppServerLookup? {
        guard let since else { return nil }
        let root = accountStore.resolvedCodexHome()
            .appendingPathComponent("sessions", isDirectory: true)
        guard FileManager.default.fileExists(atPath: root.path) else { return nil }
        let candidates = recentSessionFiles(in: root, modifiedAfter: since)
        let decoder = JSONDecoder()
        for file in candidates {
            for line in recentLines(from: file).reversed() {
                guard line.contains(#""rate_limits""#),
                      line.contains(#""token_count""#),
                      let lineData = String(line).data(using: .utf8),
                      let event = try? decoder.decode(LocalSessionRateLimitEvent.self, from: lineData),
                      event.type == "event_msg",
                      event.payload?.type == "token_count",
                      let snapshot = event.payload?.rateLimits,
                      snapshot.limitId == nil || snapshot.limitId == "codex",
                      snapshot.primary != nil || snapshot.secondary != nil else { continue }
                return AppServerLookup(
                    limits: AppServerRateLimits(
                        primary: snapshot.primary.map { AppServerRateLimitParser.makeWindow($0, fallbackKind: .fiveHour) },
                        secondary: snapshot.secondary.map { AppServerRateLimitParser.makeWindow($0, fallbackKind: .weekly) },
                        planType: nil
                    ),
                    fromCache: true
                )
            }
        }
        return nil
    }

    private func recentLines(from file: URL, maxBytes: UInt64 = 512 * 1024) -> [Substring] {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return [] }
        defer { try? handle.close() }
        do {
            let byteCount = try handle.seekToEnd()
            let startOffset = byteCount > maxBytes ? byteCount - maxBytes : 0
            try handle.seek(toOffset: startOffset)
            let data = handle.readDataToEndOfFile()
            guard let text = String(data: data, encoding: .utf8) else { return [] }
            var lines = text.split(separator: "\n", omittingEmptySubsequences: true)
            if startOffset > 0, lines.isEmpty == false {
                lines.removeFirst()
            }
            return lines
        } catch {
            return []
        }
    }

    private func recentSessionFiles(in root: URL, modifiedAfter lowerBound: Date) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var files: [(url: URL, modifiedAt: Date)] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]),
                  values.isRegularFile == true,
                  let modifiedAt = values.contentModificationDate,
                  modifiedAt >= lowerBound else { continue }
            files.append((url, modifiedAt))
        }
        return files
            .sorted { $0.modifiedAt > $1.modifiedAt }
            .prefix(30)
            .map(\.url)
    }

    private func parseAppServerRateLimitsLine(_ line: String) -> AppServerRateLimits? {
        AppServerRateLimitParser.parseJSONRPCLine(line)
    }

    private func loadAppServerCache(accountIdentity: String) -> AppServerRateLimits? {
        guard let entry = loadAppServerCacheEntries()[accountIdentity],
              Date().timeIntervalSince(entry.savedAt) < 900 else { return nil }
        return entry.limits
    }

    private func saveAppServerCache(_ limits: AppServerRateLimits, accountIdentity: String) {
        var entries = loadAppServerCacheEntries()
        entries[accountIdentity] = AppServerQuotaCacheEntry(savedAt: Date(), limits: limits)
        let cache = AppServerQuotaCacheStore(accounts: entries)
        guard let data = try? JSONEncoder.codexHub.encode(cache) else { return }
        try? LocalStorageSecurity.writePrivateFileAtomically(data, to: appServerCacheURL)
    }

    private func loadAppServerCacheEntries() -> [String: AppServerQuotaCacheEntry] {
        guard let data = try? Data(contentsOf: appServerCacheURL) else { return [:] }
        if let store = try? JSONDecoder.codexHub.decode(AppServerQuotaCacheStore.self, from: data) {
            return store.accounts
        }
        if let legacy = try? JSONDecoder.codexHub.decode(AppServerQuotaCache.self, from: data),
           let accountIdentity = legacy.accountIdentity {
            return [
                accountIdentity: AppServerQuotaCacheEntry(savedAt: legacy.savedAt, limits: legacy.limits)
            ]
        }
        return [:]
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

    private func run(_ executable: String, _ args: [String], timeout: TimeInterval) -> CommandResult {
        let environment = CodexProcessEnvironment.make(
            prependingExecutableDirectory: executable,
            includeBundledCodexPath: true
        )
        let result = processRunner.run(executable, args, timeout, environment)
        guard result.status == 124 else { return result }
        return CommandResult(
            status: result.status,
            output: "\(result.output): \(URL(fileURLWithPath: executable).lastPathComponent) \(args.joined(separator: " "))"
        )
    }
}
