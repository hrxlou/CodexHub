import Darwin
import Foundation

enum LoginMode {
    case browser
    case deviceCode
}

struct AccountLoadResult {
    let accounts: [CodexAccount]
    let error: String?
}

final class CodexAccountStore {
    private let fileManager = FileManager.default
    private let lock = NSLock()

    private var codexHomeURL: URL {
        let environment = ProcessInfo.processInfo.environment
        if let home = environment["CODEX_HOME"], home.isEmpty == false {
            let url = URL(fileURLWithPath: home, isDirectory: true)
            if fileManager.fileExists(atPath: url.path) {
                return url
            }
        }
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent(".codex", isDirectory: true)
    }

    private var authURL: URL {
        codexHomeURL.appendingPathComponent("auth.json")
    }

    private var accountsDirectoryURL: URL {
        codexHomeURL.appendingPathComponent("accounts", isDirectory: true)
    }

    private var registryURL: URL {
        accountsDirectoryURL.appendingPathComponent("registry.json")
    }

    func loadAccounts() -> AccountLoadResult {
        lock.lock()
        defer { lock.unlock() }

        if !fileManager.fileExists(atPath: registryURL.path) {
            if let captured = try? captureCurrentLoginLocked(alias: nil), captured {
                return loadAccountsFromRegistryLocked()
            }
            return AccountLoadResult(accounts: [], error: L.text(ko: "저장된 Codex 계정이 없습니다", en: "No stored Codex accounts found"))
        }
        return loadAccountsFromRegistryLocked()
    }

    func startCodexLogin(mode: LoginMode) -> CommandResult {
        guard let codexPath = codexCLIPath() else {
            return CommandResult(status: 127, output: L.text(ko: "codex 명령을 찾지 못했습니다", en: "codex command was not found"))
        }
        var args = ["login", "-c", "cli_auth_credentials_store=\"file\""]
        if mode == .deviceCode {
            args.append("--device-auth")
        }
        return run(codexPath, args, timeout: 600)
    }

    func captureCurrentLogin(alias: String?) -> CommandResult {
        lock.lock()
        defer { lock.unlock() }
        do {
            let captured = try captureCurrentLoginLocked(alias: alias)
            if captured {
                return CommandResult(status: 0, output: L.text(ko: "현재 Codex 로그인을 저장했습니다", en: "Current Codex login was saved"))
            }
            return CommandResult(status: 1, output: L.text(ko: "저장할 Codex 로그인 파일이 없습니다", en: "No Codex login file was available to save"))
        } catch {
            return CommandResult(status: 1, output: error.localizedDescription)
        }
    }

    func switchAccount(identity: String) -> CommandResult {
        lock.lock()
        defer { lock.unlock() }
        do {
            _ = try captureCurrentLoginLocked(alias: nil)
            var registry = try readRegistryLocked()
            guard let accounts = registry["accounts"] as? [[String: Any]],
                  let index = accounts.firstIndex(where: { ($0["account_key"] as? String) == identity }) else {
                return CommandResult(status: 1, output: L.text(ko: "계정을 찾지 못했습니다", en: "Account was not found"))
            }
            let snapshotURL = authSnapshotURL(for: identity)
            guard fileManager.fileExists(atPath: snapshotURL.path) else {
                return CommandResult(status: 1, output: L.text(ko: "계정 로그인 저장 파일이 없습니다", en: "Stored account login file is missing"))
            }

            try createDirectoryIfNeededLocked()
            backupFileIfPresent(authURL, prefix: "auth.json.bak")
            try replaceFile(at: authURL, withContentsOf: snapshotURL)
            try setPrivatePermissions(authURL)

            var updatedAccounts = accounts
            let nowSeconds = Int(Date().timeIntervalSince1970)
            let nowMilliseconds = Int(Date().timeIntervalSince1970 * 1000)
            updatedAccounts[index]["last_used_at"] = nowSeconds
            registry["accounts"] = updatedAccounts
            registry["active_account_key"] = identity
            registry["active_account_activated_at_ms"] = nowMilliseconds
            try writeRegistryLocked(registry)
            return CommandResult(status: 0, output: "")
        } catch {
            return CommandResult(status: 1, output: error.localizedDescription)
        }
    }

    func removeStoredAccount(identity: String) -> CommandResult {
        lock.lock()
        defer { lock.unlock() }
        do {
            var registry = try readRegistryLocked()
            if (registry["active_account_key"] as? String) == identity {
                return CommandResult(status: 1, output: L.text(ko: "활성 계정은 삭제할 수 없습니다", en: "The active account cannot be removed"))
            }
            guard let accounts = registry["accounts"] as? [[String: Any]] else {
                return CommandResult(status: 1, output: L.text(ko: "계정 레지스트리를 읽지 못했습니다", en: "Account registry could not be read"))
            }
            let updated = accounts.filter { ($0["account_key"] as? String) != identity }
            guard updated.count != accounts.count else {
                return CommandResult(status: 1, output: L.text(ko: "계정을 찾지 못했습니다", en: "Account was not found"))
            }
            registry["accounts"] = updated
            backupFileIfPresent(authSnapshotURL(for: identity), prefix: nil)
            try? fileManager.removeItem(at: authSnapshotURL(for: identity))
            try writeRegistryLocked(registry)
            return CommandResult(status: 0, output: "")
        } catch {
            return CommandResult(status: 1, output: error.localizedDescription)
        }
    }

    private func loadAccountsFromRegistryLocked() -> AccountLoadResult {
        do {
            let registry = try readRegistryLocked()
            guard let rawAccounts = registry["accounts"] as? [[String: Any]] else {
                return AccountLoadResult(accounts: [], error: L.text(ko: "계정 레지스트리 형식이 올바르지 않습니다", en: "Account registry format is invalid"))
            }
            let activeKey = registry["active_account_key"] as? String
            let accounts = rawAccounts.enumerated().compactMap { index, raw in
                makeAccount(index: index, raw: raw, activeKey: activeKey)
            }
            return AccountLoadResult(
                accounts: accounts,
                error: accounts.isEmpty ? L.text(ko: "저장된 Codex 계정이 없습니다", en: "No stored Codex accounts found") : nil
            )
        } catch {
            return AccountLoadResult(accounts: [], error: error.localizedDescription)
        }
    }

    private func makeAccount(index: Int, raw: [String: Any], activeKey: String?) -> CodexAccount? {
        guard let identity = raw["account_key"] as? String else { return nil }
        let email = (raw["email"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let alias = (raw["alias"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayEmail = (email?.isEmpty == false ? email : nil)
            ?? extractAuthInfo(from: authSnapshotURL(for: identity)).email
            ?? identity
        let plan = ((raw["plan"] as? String)?.isEmpty == false ? raw["plan"] as? String : nil)
            ?? ((raw["last_usage"] as? [String: Any])?["plan_type"] as? String)
            ?? "unknown"
        let usage = raw["last_usage"] as? [String: Any]
        let primary = makeUsageText(raw: usage?["primary"] as? [String: Any], kind: .fiveHour)
        let secondary = makeUsageText(raw: usage?["secondary"] as? [String: Any], kind: .weekly)
        let lastUsedAt = dateFromUnixSeconds(raw["last_used_at"])
        let lastActivity = lastUsedAt.map(Format.relative) ?? "-"
        return CodexAccount(
            selector: "\(index + 1)",
            identity: identity,
            email: displayEmail,
            alias: alias?.isEmpty == false ? alias : nil,
            plan: plan,
            fiveHourUsage: primary.text,
            fiveHourUsedPercent: primary.percent,
            weeklyUsage: secondary.text,
            weeklyUsedPercent: secondary.percent,
            lastActivity: lastActivity,
            lastUsedAt: lastUsedAt,
            isActive: identity == activeKey
        )
    }

    private enum QuotaWindowKind {
        case fiveHour
        case weekly
    }

    private func makeUsageText(raw: [String: Any]?, kind: QuotaWindowKind) -> (text: String, percent: Int?) {
        guard let raw, let percent = intValue(raw["used_percent"]) else {
            return ("-", nil)
        }
        let clamped = max(0, min(100, percent))
        guard let resetSeconds = doubleValue(raw["resets_at"]) else {
            return ("\(clamped)%", clamped)
        }
        let reset = Date(timeIntervalSince1970: resetSeconds)
        let text = kind == .weekly
            ? "\(clamped)% (\(Format.shortDate(reset)))"
            : "\(clamped)% (\(Format.time(reset)))"
        return (text, clamped)
    }

    private func captureCurrentLoginLocked(alias: String?) throws -> Bool {
        guard fileManager.fileExists(atPath: authURL.path) else { return false }
        let info = extractAuthInfo(from: authURL)
        guard let identity = info.identity else {
            throw StoreError.invalidAuth
        }
        try createDirectoryIfNeededLocked()
        let snapshotURL = authSnapshotURL(for: identity)
        if fileManager.fileExists(atPath: snapshotURL.path) {
            backupFileIfPresent(snapshotURL, prefix: nil)
        }
        try replaceFile(at: snapshotURL, withContentsOf: authURL)
        try setPrivatePermissions(snapshotURL)

        var registry = (try? readRegistryLocked()) ?? emptyRegistry()
        var accounts = registry["accounts"] as? [[String: Any]] ?? []
        let nowSeconds = Int(Date().timeIntervalSince1970)
        let existingIndex = accounts.firstIndex { ($0["account_key"] as? String) == identity }
        var account = existingIndex.map { accounts[$0] } ?? [:]
        account["account_key"] = identity
        account["chatgpt_account_id"] = info.accountID ?? account["chatgpt_account_id"]
        account["chatgpt_user_id"] = info.userID ?? account["chatgpt_user_id"]
        account["email"] = info.email ?? account["email"]
        if let alias, alias.isEmpty == false {
            account["alias"] = alias
        } else if account["alias"] == nil {
            account["alias"] = ""
        }
        account["account_name"] = info.name ?? account["account_name"]
        account["plan"] = info.plan ?? account["plan"] ?? "unknown"
        account["auth_mode"] = info.authMode ?? account["auth_mode"] ?? "chatgpt"
        account["created_at"] = account["created_at"] ?? nowSeconds
        if existingIndex == nil {
            accounts.append(account)
        } else if let existingIndex {
            accounts[existingIndex] = account
        }
        registry["accounts"] = accounts
        registry["active_account_key"] = identity
        registry["active_account_activated_at_ms"] = Int(Date().timeIntervalSince1970 * 1000)
        try writeRegistryLocked(registry)
        return true
    }

    private func extractAuthInfo(from url: URL) -> AuthInfo {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return AuthInfo()
        }
        let tokens = object["tokens"] as? [String: Any]
        let authMode = object["auth_mode"] as? String
        var info = AuthInfo(
            identity: nil,
            accountID: tokens?["account_id"] as? String,
            userID: nil,
            email: nil,
            name: nil,
            plan: nil,
            authMode: authMode
        )
        if let idToken = tokens?["id_token"] as? String {
            let claims = decodeJWTClaims(idToken)
            merge(claims: claims, into: &info)
        }
        if let accessToken = tokens?["access_token"] as? String {
            let claims = decodeJWTClaims(accessToken)
            merge(claims: claims, into: &info)
        }
        if info.accountID == nil {
            info.accountID = tokens?["account_id"] as? String
        }
        if let userID = info.userID, let accountID = info.accountID {
            info.identity = "\(userID)::\(accountID)"
        } else if let accountID = info.accountID {
            info.identity = accountID
        }
        return info
    }

    private func merge(claims: [String: Any], into info: inout AuthInfo) {
        let auth = claims["https://api.openai.com/auth"] as? [String: Any]
        let profile = claims["https://api.openai.com/profile"] as? [String: Any]
        info.accountID = info.accountID ?? auth?["chatgpt_account_id"] as? String
        info.userID = info.userID ?? auth?["chatgpt_user_id"] as? String ?? auth?["user_id"] as? String
        info.email = info.email ?? profile?["email"] as? String ?? claims["email"] as? String
        info.name = info.name ?? claims["name"] as? String
        info.plan = info.plan ?? auth?["chatgpt_plan_type"] as? String
    }

    private func decodeJWTClaims(_ token: String) -> [String: Any] {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return [:] }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = payload.count % 4
        if padding > 0 {
            payload.append(String(repeating: "=", count: 4 - padding))
        }
        guard let data = Data(base64Encoded: payload),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return object
    }

    private func readRegistryLocked() throws -> [String: Any] {
        let data = try Data(contentsOf: registryURL)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw StoreError.invalidRegistry
        }
        return object
    }

    private func writeRegistryLocked(_ registry: [String: Any]) throws {
        try createDirectoryIfNeededLocked()
        backupFileIfPresent(registryURL, prefix: "registry.json.bak")
        let data = try JSONSerialization.data(withJSONObject: registry, options: [.prettyPrinted, .sortedKeys])
        try writeDataAtomically(data, to: registryURL)
        try setPrivatePermissions(registryURL)
    }

    private func emptyRegistry() -> [String: Any] {
        [
            "active_account_key": NSNull(),
            "active_account_activated_at_ms": NSNull(),
            "config": [
                "auto_switch": false,
                "usage_api": false,
                "account_api": false
            ],
            "accounts": []
        ]
    }

    private func createDirectoryIfNeededLocked() throws {
        try fileManager.createDirectory(at: accountsDirectoryURL, withIntermediateDirectories: true)
    }

    private func authSnapshotURL(for identity: String) -> URL {
        let preferred = accountsDirectoryURL.appendingPathComponent("\(encodedFileStem(for: identity, urlSafe: true)).auth.json")
        if fileManager.fileExists(atPath: preferred.path) {
            return preferred
        }
        let standard = accountsDirectoryURL.appendingPathComponent("\(encodedFileStem(for: identity, urlSafe: false)).auth.json")
        if fileManager.fileExists(atPath: standard.path) {
            return standard
        }
        return preferred
    }

    private func encodedFileStem(for identity: String, urlSafe: Bool) -> String {
        let encoded = Data(identity.utf8)
            .base64EncodedString()
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
        guard urlSafe else { return encoded }
        return encoded
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
    }

    private func backupFileIfPresent(_ url: URL, prefix: String?) {
        guard fileManager.fileExists(atPath: url.path) else { return }
        let stamp = backupTimestamp()
        let backupName = prefix.map { "\($0).\(stamp)" } ?? "\(url.lastPathComponent).bak.\(Int(Date().timeIntervalSince1970))"
        let backupURL = accountsDirectoryURL.appendingPathComponent(backupName)
        try? fileManager.copyItem(at: url, to: backupURL)
    }

    private func backupTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    private func replaceFile(at target: URL, withContentsOf source: URL) throws {
        let data = try Data(contentsOf: source)
        try writeDataAtomically(data, to: target)
    }

    private func writeDataAtomically(_ data: Data, to url: URL) throws {
        let temporaryURL = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).tmp-\(UUID().uuidString)")
        try data.write(to: temporaryURL, options: .atomic)
        if fileManager.fileExists(atPath: url.path) {
            _ = try fileManager.replaceItemAt(url, withItemAt: temporaryURL)
        } else {
            try fileManager.moveItem(at: temporaryURL, to: url)
        }
    }

    private func setPrivatePermissions(_ url: URL) throws {
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func codexCLIPath() -> String? {
        let candidates = [
            "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ]
        if let path = candidates.first(where: { fileManager.isExecutableFile(atPath: $0) }) {
            return path
        }
        let result = run("/bin/zsh", ["-l", "-c", "which codex"], timeout: 1)
        let path = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.status == 0 && fileManager.isExecutableFile(atPath: path) ? path : nil
    }

    private func run(_ executable: String, _ args: [String], timeout: TimeInterval) -> CommandResult {
        let process = Process()
        let pipe = Pipe()
        let outputLock = NSLock()
        var output = Data()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        process.standardOutput = pipe
        process.standardError = pipe
        process.environment = processEnvironment(prependingExecutableDirectory: executable)
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
            return CommandResult(status: process.terminationStatus, output: drainedOutput(from: pipe, accumulated: output, lock: outputLock))
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
        return environment
    }

    private func dateFromUnixSeconds(_ value: Any?) -> Date? {
        doubleValue(value).map { Date(timeIntervalSince1970: $0) }
    }

    private func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let double = value as? Double { return Int(double) }
        if let string = value as? String { return Int(string) }
        return nil
    }

    private func doubleValue(_ value: Any?) -> Double? {
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let string = value as? String { return Double(string) }
        return nil
    }

    private struct AuthInfo {
        var identity: String?
        var accountID: String?
        var userID: String?
        var email: String?
        var name: String?
        var plan: String?
        var authMode: String?
    }

    private enum StoreError: LocalizedError {
        case invalidAuth
        case invalidRegistry

        var errorDescription: String? {
            switch self {
            case .invalidAuth:
                return L.text(ko: "Codex 로그인 파일에서 계정 정보를 읽지 못했습니다", en: "Could not read account information from the Codex login file")
            case .invalidRegistry:
                return L.text(ko: "계정 레지스트리 형식이 올바르지 않습니다", en: "Account registry format is invalid")
            }
        }
    }
}
