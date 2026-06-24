import Foundation

final class CodexAuthService {
    enum QuotaAPIStatus: Equatable {
        case on
        case off
        case fallback
        case failed

        var label: String {
            switch self {
            case .on: return "On"
            case .off: return "Off"
            case .fallback: return "Fallback"
            case .failed: return "Failed"
            }
        }

        var isHealthy: Bool {
            self != .failed
        }
    }

    func listAccounts(useAPI: Bool) -> (accounts: [CodexAccount], error: String?, quotaAPIStatus: QuotaAPIStatus, autoDisabledAPI: Bool) {
        var result: CommandResult
        var quotaStatus: QuotaAPIStatus
        var autoDisabledAPI = false

        if useAPI {
            let enable = setQuotaAPIEnabled(true)
            guard enable.status == 0 else {
                _ = setQuotaAPIEnabled(false)
                result = runCodexAuth(["list"])
                quotaStatus = result.status == 0 ? .fallback : .failed
                let error = result.status == 0 ? enable.output.trimmingCharacters(in: .whitespacesAndNewlines) : result.output.trimmingCharacters(in: .whitespacesAndNewlines)
                return (parseAccounts(result.output), error.isEmpty ? nil : error, quotaStatus, true)
            }
            result = runCodexAuth(["list"])
            quotaStatus = result.status == 0 ? .on : .failed
        } else {
            _ = setQuotaAPIEnabled(false)
            result = runCodexAuth(["list"])
            quotaStatus = .off
        }

        if useAPI && result.status != 0 {
            _ = setQuotaAPIEnabled(false)
            autoDisabledAPI = true
            let apiError = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            result = runCodexAuth(["list"])
            quotaStatus = result.status == 0 ? .fallback : .failed
            if result.status == 0 {
                let accounts = applyAppServerFallbackIfUseful(parseAccounts(result.output), always: true)
                let notice = apiError.isEmpty ? "Quota API failed; using local quota mode" : "Quota API failed; using local quota mode"
                return (accounts, accounts.isEmpty ? "No codex-auth accounts found" : notice, quotaStatus, autoDisabledAPI)
            }
        }

        guard result.status == 0 else {
            return ([], result.output.trimmingCharacters(in: .whitespacesAndNewlines), quotaStatus, autoDisabledAPI)
        }
        let accounts = applyAppServerFallbackIfUseful(parseAccounts(result.output), always: !useAPI || quotaStatus == .fallback)
        return (accounts, accounts.isEmpty ? "No codex-auth accounts found" : nil, quotaStatus, autoDisabledAPI)
    }

    func setQuotaAPIEnabled(_ enabled: Bool) -> CommandResult {
        runCodexAuth(["config", "api", enabled ? "enable" : "disable"])
    }

    func switchTo(_ emailOrSelector: String) -> CommandResult {
        runCodexAuth(["switch", emailOrSelector])
    }

    func restartCodex() -> CommandResult {
        let quit = run("/usr/bin/osascript", ["-e", "quit app \"Codex\""])
        Thread.sleep(forTimeInterval: 0.4)
        let open = run("/usr/bin/open", ["-a", "Codex"])
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

    private func applyAppServerFallbackIfUseful(_ accounts: [CodexAccount], always: Bool) -> [CodexAccount] {
        guard let active = accounts.first(where: { $0.isActive }) else { return accounts }
        let needsFallback = always
            || active.fiveHourUsedPercent == nil
            || active.weeklyUsedPercent == nil
            || active.weeklyUsedPercent == 0
            || active.weeklyUsage == "-"
            || active.weeklyUsage == "Unavailable"
        guard needsFallback, let limits = readActiveRateLimitsFromCodexAppServer() else { return accounts }
        return accounts.map { account in
            account.isActive ? account.applyingAppServerRateLimits(limits) : account
        }
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

    private func readActiveRateLimitsFromCodexAppServer() -> AppServerRateLimits? {
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

        do {
            try process.run()
            let payload = "\(request1)\n\(request2)\n"
            if let data = payload.data(using: .utf8) {
                stdin.fileHandleForWriting.write(data)
            }
            Thread.sleep(forTimeInterval: 2.5)
            if process.isRunning {
                process.terminate()
            }
            let output = stdout.fileHandleForReading.readDataToEndOfFile()
            return parseAppServerRateLimits(String(data: output, encoding: .utf8) ?? "")
        } catch {
            return nil
        }
    }

    private func parseAppServerRateLimits(_ output: String) -> AppServerRateLimits? {
        let decoder = JSONDecoder()
        for line in output.split(whereSeparator: \.isNewline).map(String.init) {
            guard line.contains(#""id":2"#),
                  let data = line.data(using: .utf8),
                  let response = try? decoder.decode(AppServerResponse.self, from: data) else { continue }
            let snapshot = response.result?.rateLimitsByLimitId?["codex"] ?? response.result?.rateLimits
            guard let snapshot else { continue }
            return AppServerRateLimits(
                primary: snapshot.primary.map(makeAppServerWindow),
                secondary: snapshot.secondary.map(makeAppServerWindow)
            )
        }
        return nil
    }

    private func makeAppServerWindow(_ payload: AppServerRateLimitWindowPayload) -> AppServerRateLimitWindow {
        let used = Int(payload.usedPercent.rounded())
        let remaining = max(0, min(100, 100 - used))
        let reset = payload.resetsAt.map { Date(timeIntervalSince1970: $0) }
        return AppServerRateLimitWindow(displayPercent: remaining, resetsAt: reset)
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

    private func runCodexAuth(_ args: [String]) -> CommandResult {
        guard let path = codexAuthPath() else {
            return CommandResult(status: 127, output: "codex-auth was not found")
        }
        return run(path, args)
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

        let result = run("/bin/zsh", ["-l", "-c", "which codex-auth"])
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

        let result = run("/bin/zsh", ["-l", "-c", "which codex"])
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

    private func run(_ executable: String, _ args: [String]) -> CommandResult {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        process.standardOutput = pipe
        process.standardError = pipe
        process.environment = processEnvironment()
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return CommandResult(status: process.terminationStatus, output: String(data: data, encoding: .utf8) ?? "")
        } catch {
            return CommandResult(status: 127, output: error.localizedDescription)
        }
    }
}
