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

struct AccountLoginResult {
    let result: CommandResult
    let identity: String?
}

final class CodexAccountStore {
    private let fileManager = FileManager.default
    private let lock = NSLock()
    private let processRunner: ProcessRunner

    init(processRunner: ProcessRunner = .live) {
        self.processRunner = processRunner
    }

    private var codexHomeURL: URL {
        let environment = ProcessInfo.processInfo.environment
        if let home = environment["CODEX_HOME"], home.isEmpty == false {
            return URL(fileURLWithPath: home, isDirectory: true)
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

        try? hardenStoredFilePermissionsLocked()
        if !fileManager.fileExists(atPath: registryURL.path) {
            if let captured = try? captureCurrentLoginLocked(alias: nil), captured {
                return loadAccountsFromRegistryLocked()
            }
            return AccountLoadResult(accounts: [], error: L.text(ko: "저장된 Codex 계정이 없습니다", en: "No stored Codex accounts found"))
        }
        try? syncCurrentLoginStateLocked()
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

    func loginAndStoreIsolated(mode: LoginMode, alias: String?) -> AccountLoginResult {
        _ = captureCurrentLogin(alias: nil)
        guard let codexPath = codexCLIPath() else {
            return AccountLoginResult(
                result: CommandResult(status: 127, output: L.text(ko: "codex 명령을 찾지 못했습니다", en: "codex command was not found")),
                identity: nil
            )
        }

        let temporaryCodexHome = fileManager.temporaryDirectory
            .appendingPathComponent("CodexHub-Login-\(UUID().uuidString)", isDirectory: true)
        do {
            try createPrivateDirectory(at: temporaryCodexHome)
        } catch {
            return AccountLoginResult(result: CommandResult(status: 1, output: error.localizedDescription), identity: nil)
        }
        defer {
            removeTemporaryCodexHome(temporaryCodexHome)
        }

        var args = ["login", "-c", "cli_auth_credentials_store=\"file\""]
        if mode == .deviceCode {
            args.append("--device-auth")
        }
        let login = run(codexPath, args, timeout: 600, environmentOverrides: ["CODEX_HOME": temporaryCodexHome.path])
        guard login.status == 0 else {
            return AccountLoginResult(result: login, identity: nil)
        }

        let temporaryAuthURL = temporaryCodexHome.appendingPathComponent("auth.json")
        let identity: String
        do {
            lock.lock()
            identity = try storeAuthFileLocked(temporaryAuthURL, alias: alias, activate: false)
            lock.unlock()
        } catch {
            lock.unlock()
            return AccountLoginResult(result: CommandResult(status: 1, output: error.localizedDescription), identity: nil)
        }

        return AccountLoginResult(result: CommandResult(status: 0, output: ""), identity: identity)
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

    func currentLoginIdentity() -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard fileManager.fileExists(atPath: authURL.path) else { return nil }
        return extractAuthInfo(from: authURL).identity
    }

    func resolvedCodexHome() -> URL {
        codexHomeURL
    }

    func waitForCurrentLoginIdentity(preferDifferentFrom previousIdentity: String?, timeout: TimeInterval) -> String? {
        let deadline = Date().addingTimeInterval(timeout)
        var latestIdentity: String?
        while Date() < deadline {
            if let identity = currentLoginIdentity() {
                latestIdentity = identity
                if previousIdentity == nil || identity != previousIdentity {
                    return identity
                }
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return latestIdentity
    }

    func switchAccount(identity: String) -> CommandResult {
        lock.lock()
        defer { lock.unlock() }
        do {
            _ = try captureCurrentLoginLocked(alias: nil)
            let previousRegistry = try readRegistryLocked()
            let previousAuthExisted = fileManager.fileExists(atPath: authURL.path)
            let previousAuthData = previousAuthExisted ? try Data(contentsOf: authURL) : nil
            guard previousRegistry.accounts.contains(where: { $0.accountKey == identity }) else {
                return CommandResult(status: 1, output: L.text(ko: "계정을 찾지 못했습니다", en: "Account was not found"))
            }
            let snapshotURL = authSnapshotURL(for: identity)
            guard fileManager.fileExists(atPath: snapshotURL.path) else {
                return CommandResult(status: 1, output: L.text(ko: "계정 로그인 저장 파일이 없습니다", en: "Stored account login file is missing"))
            }

            try createDirectoryIfNeededLocked()
            try replaceFile(at: authURL, withContentsOf: snapshotURL)
            try setPrivatePermissions(authURL)

            let validation = validateCurrentLogin()
            guard validation.status == 0 else {
                try restoreAuthLocked(data: previousAuthData, existed: previousAuthExisted)
                try writeRegistryLocked(previousRegistry)
                let message = validation.output.trimmingCharacters(in: .whitespacesAndNewlines)
                return CommandResult(
                    status: validation.status == 0 ? 1 : validation.status,
                    output: message.isEmpty ? L.text(ko: "전환한 계정의 로그인이 유효하지 않습니다", en: "The switched account login is not valid") : message
                )
            }

            _ = try captureCurrentLoginLocked(alias: nil)
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
            let originalRegistry = registry
            if registry.activeAccountKey == identity {
                return CommandResult(status: 1, output: L.text(ko: "활성 계정은 삭제할 수 없습니다", en: "The active account cannot be removed"))
            }
            guard let removeIndex = registry.accounts.firstIndex(where: { $0.accountKey == identity }) else {
                return CommandResult(status: 1, output: L.text(ko: "계정을 찾지 못했습니다", en: "Account was not found"))
            }

            let snapshotURL = authSnapshotURL(for: identity)
            var tombstoneURL: URL?
            if fileManager.fileExists(atPath: snapshotURL.path) {
                try createDirectoryIfNeededLocked()
                let tombstone = accountsDirectoryURL
                    .appendingPathComponent(".\(snapshotURL.lastPathComponent).delete-\(UUID().uuidString)")
                try fileManager.moveItem(at: snapshotURL, to: tombstone)
                tombstoneURL = tombstone
            }

            registry.accounts.remove(at: removeIndex)
            do {
                try writeRegistryLocked(registry)
            } catch {
                if let tombstoneURL {
                    try? fileManager.moveItem(at: tombstoneURL, to: snapshotURL)
                    try? setPrivatePermissions(snapshotURL)
                }
                throw error
            }

            if let tombstoneURL {
                do {
                    try fileManager.removeItem(at: tombstoneURL)
                } catch {
                    try? writeRegistryLocked(originalRegistry)
                    try? fileManager.moveItem(at: tombstoneURL, to: snapshotURL)
                    try? setPrivatePermissions(snapshotURL)
                    throw error
                }
            }
            return CommandResult(status: 0, output: "")
        } catch {
            return CommandResult(status: 1, output: error.localizedDescription)
        }
    }

    func updateStoredUsage(identity: String, limits: AppServerRateLimits) {
        lock.lock()
        defer { lock.unlock() }
        do {
            var registry = try readRegistryLocked()
            guard let existingIndex = registry.accounts.firstIndex(where: { $0.accountKey == identity }) else {
                return
            }
            registry.accounts[existingIndex].updateUsage(limits)
            try writeRegistryLocked(registry)
        } catch {
            return
        }
    }

    func makeTemporaryCodexHome(for identity: String) -> URL? {
        lock.lock()
        defer { lock.unlock() }
        let snapshotURL = authSnapshotURL(for: identity)
        guard fileManager.fileExists(atPath: snapshotURL.path) else { return nil }
        let temporaryRoot = fileManager.temporaryDirectory
            .appendingPathComponent("CodexHub-CodexHome-\(UUID().uuidString)", isDirectory: true)
        do {
            try createPrivateDirectory(at: temporaryRoot)
            let temporaryAuthURL = temporaryRoot.appendingPathComponent("auth.json")
            try fileManager.copyItem(at: snapshotURL, to: temporaryAuthURL)
            try setPrivatePermissions(temporaryAuthURL)
            return temporaryRoot
        } catch {
            removeTemporaryCodexHome(temporaryRoot)
            return nil
        }
    }

    func removeTemporaryCodexHome(_ temporaryCodexHome: URL) {
        let temporaryAuthURL = temporaryCodexHome.appendingPathComponent("auth.json")
        if fileManager.fileExists(atPath: temporaryAuthURL.path) {
            try? setPrivatePermissions(temporaryAuthURL)
            try? fileManager.removeItem(at: temporaryAuthURL)
        }
        try? fileManager.removeItem(at: temporaryCodexHome)
    }

    func updateStoredAuthSnapshot(identity: String, fromTemporaryCodexHome temporaryCodexHome: URL) {
        lock.lock()
        defer { lock.unlock() }
        let temporaryAuthURL = temporaryCodexHome.appendingPathComponent("auth.json")
        guard fileManager.fileExists(atPath: temporaryAuthURL.path),
              extractAuthInfo(from: temporaryAuthURL).identity == identity else {
            return
        }
        do {
            let snapshotURL = authSnapshotURL(for: identity)
            try replaceFile(at: snapshotURL, withContentsOf: temporaryAuthURL)
            try setPrivatePermissions(snapshotURL)
        } catch {
            return
        }
    }

    private func loadAccountsFromRegistryLocked() -> AccountLoadResult {
        do {
            let registry = try readRegistryLocked()
            let activeKey = registry.activeAccountKey
            let accounts = registry.accounts.enumerated().compactMap { index, account in
                makeAccount(index: index, stored: account, activeKey: activeKey)
            }
            return AccountLoadResult(
                accounts: accounts,
                error: accounts.isEmpty ? L.text(ko: "저장된 Codex 계정이 없습니다", en: "No stored Codex accounts found") : nil
            )
        } catch {
            return AccountLoadResult(accounts: [], error: error.localizedDescription)
        }
    }

    private func makeAccount(index: Int, stored: StoredAccount, activeKey: String?) -> CodexAccount? {
        guard let identity = stored.accountKey else { return nil }
        let email = stored.email?.trimmingCharacters(in: .whitespacesAndNewlines)
        let alias = stored.alias?.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayEmail = (email?.isEmpty == false ? email : nil)
            ?? extractAuthInfo(from: authSnapshotURL(for: identity)).email
            ?? identity
        let storedPlan = stored.plan?.trimmingCharacters(in: .whitespacesAndNewlines)
        let usagePlan = stored.lastUsage?.planType?.trimmingCharacters(in: .whitespacesAndNewlines)
        let plan = (storedPlan?.isEmpty == false && storedPlan?.lowercased() != "unknown" ? storedPlan : nil)
            ?? (usagePlan?.isEmpty == false && usagePlan?.lowercased() != "unknown" ? usagePlan : nil)
            ?? "unknown"
        let lastUsageUpdatedAt = dateFromUnixSeconds(stored.lastUsage?.updatedAt)
        let primary = makeUsageText(window: stored.lastUsage?.primary, fallbackKind: .fiveHour, observedAt: lastUsageUpdatedAt)
        let secondary = makeUsageText(window: stored.lastUsage?.secondary, fallbackKind: .weekly, observedAt: lastUsageUpdatedAt)
        let lastUsedAt = dateFromUnixSeconds(stored.lastUsedAt)
        let lastActivity = (lastUsageUpdatedAt ?? lastUsedAt).map(Format.relative) ?? "-"
        return CodexAccount(
            selector: "\(index + 1)",
            identity: identity,
            email: displayEmail,
            alias: alias?.isEmpty == false ? alias : nil,
            plan: plan,
            fiveHourUsage: primary.text,
            fiveHourUsedPercent: primary.percent,
            fiveHourQuotaKind: primary.kind,
            weeklyUsage: secondary.text,
            weeklyUsedPercent: secondary.percent,
            weeklyQuotaKind: secondary.kind,
            lastActivity: lastActivity,
            lastUsedAt: lastUsedAt,
            isActive: identity == activeKey
        )
    }

    private func makeUsageText(
        window: StoredUsageWindow?,
        fallbackKind: AppServerRateLimitWindow.Kind,
        observedAt: Date?
    ) -> (text: String, percent: Int?, kind: AppServerRateLimitWindow.Kind?) {
        guard let window, let percent = window.usedPercent else {
            return ("-", nil, nil)
        }
        let clamped = max(0, min(100, percent))
        let explicitKind = window.kind
        let windowDurationMinutes = window.windowDurationMins
        guard let resetSeconds = window.resetsAt else {
            return ("\(clamped)%", clamped, explicitKind ?? fallbackKind)
        }
        let reset = Date(timeIntervalSince1970: resetSeconds)
        let displayKind = explicitKind ?? AppServerRateLimitWindow.Kind.inferred(
            windowDurationMinutes: windowDurationMinutes,
            resetsAt: reset,
            observedAt: observedAt ?? Date(),
            fallback: fallbackKind
        )
        let resetText = displayKind.usesDateReset ? Format.shortDate(reset) : Format.time(reset)
        return ("\(clamped)% (\(resetText))", clamped, displayKind)
    }

    private func captureCurrentLoginLocked(alias: String?) throws -> Bool {
        guard fileManager.fileExists(atPath: authURL.path) else { return false }
        _ = try storeAuthFileLocked(authURL, alias: alias, activate: true)
        return true
    }

    private func storeAuthFileLocked(_ sourceAuthURL: URL, alias: String?, activate: Bool) throws -> String {
        guard fileManager.fileExists(atPath: sourceAuthURL.path) else {
            throw StoreError.invalidAuth
        }
        let info = extractAuthInfo(from: sourceAuthURL)
        guard let identity = info.identity else {
            throw StoreError.invalidAuth
        }
        try createDirectoryIfNeededLocked()
        let snapshotURL = authSnapshotURL(for: identity)
        try replaceFile(at: snapshotURL, withContentsOf: sourceAuthURL)
        try setPrivatePermissions(snapshotURL)

        var registry = (try? readRegistryLocked()) ?? StoredRegistry.empty()
        let nowSeconds = Int(Date().timeIntervalSince1970)
        let existingIndex = registry.accounts.firstIndex { $0.accountKey == identity }
        var account = existingIndex.map { registry.accounts[$0] } ?? StoredAccount()
        account.accountKey = identity
        account.chatgptAccountID = info.accountID ?? account.chatgptAccountID
        account.chatgptUserID = info.userID ?? account.chatgptUserID
        account.email = info.email ?? account.email
        if let alias, alias.isEmpty == false {
            account.alias = alias
        } else if account.alias == nil {
            account.alias = ""
        }
        account.accountName = info.name ?? account.accountName
        account.plan = info.plan ?? account.plan ?? "unknown"
        account.authMode = info.authMode ?? account.authMode ?? "chatgpt"
        account.createdAt = account.createdAt ?? nowSeconds
        account.lastUsedAt = nowSeconds
        if existingIndex == nil {
            registry.accounts.append(account)
        } else if let existingIndex {
            registry.accounts[existingIndex] = account
        }
        if activate {
            registry.activeAccountKey = identity
            registry.activeAccountActivatedAtMs = Int(Date().timeIntervalSince1970 * 1000)
        }
        try writeRegistryLocked(registry)
        return identity
    }

    private func syncCurrentLoginStateLocked() throws {
        guard fileManager.fileExists(atPath: authURL.path) else {
            try clearActiveLoginLocked()
            return
        }
        let info = extractAuthInfo(from: authURL)
        guard let identity = info.identity else {
            try clearActiveLoginLocked()
            return
        }
        var registry = try readRegistryLocked()
        guard let existingIndex = registry.accounts.firstIndex(where: { $0.accountKey == identity }) else {
            _ = try captureCurrentLoginLocked(alias: nil)
            return
        }
        var account = registry.accounts[existingIndex]
        let nowSeconds = Int(Date().timeIntervalSince1970)
        var changed = false

        func setIfChanged(_ keyPath: WritableKeyPath<StoredAccount, String?>, _ value: String?) {
            guard let value else { return }
            if account[keyPath: keyPath] != value {
                account[keyPath: keyPath] = value
                changed = true
            }
        }

        setIfChanged(\.chatgptAccountID, info.accountID)
        setIfChanged(\.chatgptUserID, info.userID)
        setIfChanged(\.email, info.email)
        setIfChanged(\.accountName, info.name)
        setIfChanged(\.plan, info.plan ?? account.plan ?? "unknown")
        setIfChanged(\.authMode, info.authMode ?? account.authMode ?? "chatgpt")
        if account.lastUsedAt == nil {
            account.lastUsedAt = nowSeconds
            changed = true
        }
        if registry.activeAccountKey != identity {
            registry.activeAccountKey = identity
            registry.activeAccountActivatedAtMs = Int(Date().timeIntervalSince1970 * 1000)
            changed = true
        } else if registry.activeAccountActivatedAtMs == nil {
            registry.activeAccountActivatedAtMs = Int(Date().timeIntervalSince1970 * 1000)
            changed = true
        }
        guard changed else { return }
        registry.accounts[existingIndex] = account
        try writeRegistryLocked(registry)
    }

    private func clearActiveLoginLocked() throws {
        var registry = try readRegistryLocked()
        guard registry.activeAccountKey != nil || registry.activeAccountActivatedAtMs != nil else { return }
        registry.activeAccountKey = nil
        registry.activeAccountActivatedAtMs = nil
        try writeRegistryLocked(registry)
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

    private func readRegistryLocked() throws -> StoredRegistry {
        let data = try Data(contentsOf: registryURL)
        guard let registry = try? JSONDecoder().decode(StoredRegistry.self, from: data) else {
            throw StoreError.invalidRegistry
        }
        return registry
    }

    private func writeRegistryLocked(_ registry: StoredRegistry) throws {
        try createDirectoryIfNeededLocked()
        backupFileIfPresent(registryURL, prefix: "registry.json.bak")
        let data = try JSONEncoder.codexHub.encode(registry)
        try writeDataAtomically(data, to: registryURL)
        try setPrivatePermissions(registryURL)
    }

    private func createDirectoryIfNeededLocked() throws {
        try createPrivateDirectory(at: codexHomeURL)
        try createPrivateDirectory(at: accountsDirectoryURL)
    }

    private func createPrivateDirectory(at url: URL) throws {
        try LocalStorageSecurity.createPrivateDirectory(at: url)
    }

    private func hardenStoredFilePermissionsLocked() throws {
        if fileManager.fileExists(atPath: codexHomeURL.path) {
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: codexHomeURL.path)
        }
        if fileManager.fileExists(atPath: authURL.path) {
            try setPrivatePermissions(authURL)
        }
        guard fileManager.fileExists(atPath: accountsDirectoryURL.path) else { return }
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: accountsDirectoryURL.path)
        if fileManager.fileExists(atPath: registryURL.path) {
            try setPrivatePermissions(registryURL)
        }
        guard let enumerator = fileManager.enumerator(
            at: accountsDirectoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsSubdirectoryDescendants]
        ) else { return }
        for case let url as URL in enumerator where url.lastPathComponent.hasSuffix(".auth.json") {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true else { continue }
            try setPrivatePermissions(url)
        }
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

    @discardableResult
    private func backupFileIfPresent(_ url: URL, prefix: String?) -> URL? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let stamp = backupTimestamp()
        let backupName = prefix.map { "\($0).\(stamp)" } ?? "\(url.lastPathComponent).bak.\(Int(Date().timeIntervalSince1970))"
        let backupURL = accountsDirectoryURL.appendingPathComponent(backupName)
        do {
            try fileManager.copyItem(at: url, to: backupURL)
            try setPrivatePermissions(backupURL)
            return backupURL
        } catch {
            return nil
        }
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

    private func restoreAuthLocked(data: Data?, existed: Bool) throws {
        if existed, let data {
            try writeDataAtomically(data, to: authURL)
            try setPrivatePermissions(authURL)
        } else if fileManager.fileExists(atPath: authURL.path) {
            try fileManager.removeItem(at: authURL)
        }
    }

    private func writeDataAtomically(_ data: Data, to url: URL) throws {
        try LocalStorageSecurity.writePrivateFileAtomically(data, to: url)
    }

    private func setPrivatePermissions(_ url: URL) throws {
        try LocalStorageSecurity.setPrivateFilePermissions(url)
    }

    private func validateCurrentLogin() -> CommandResult {
        guard let codexPath = codexCLIPath() else {
            return CommandResult(status: 127, output: L.text(ko: "codex 명령을 찾지 못했습니다", en: "codex command was not found"))
        }
        return run(codexPath, ["login", "-c", "cli_auth_credentials_store=\"file\"", "status"], timeout: 20)
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

    private func run(_ executable: String, _ args: [String], timeout: TimeInterval, environmentOverrides: [String: String] = [:]) -> CommandResult {
        let environment = CodexProcessEnvironment.make(
            prependingExecutableDirectory: executable,
            overrides: environmentOverrides
        )
        return processRunner.run(executable, args, timeout, environment)
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

    private struct DynamicCodingKey: CodingKey, Hashable {
        let stringValue: String
        let intValue: Int?

        init(_ stringValue: String) {
            self.stringValue = stringValue
            self.intValue = nil
        }

        init?(stringValue: String) {
            self.init(stringValue)
        }

        init?(intValue: Int) {
            self.stringValue = "\(intValue)"
            self.intValue = intValue
        }
    }

    private enum JSONValue: Codable, Equatable {
        case object([String: JSONValue])
        case array([JSONValue])
        case string(String)
        case number(Double)
        case bool(Bool)
        case null

        init(from decoder: Decoder) throws {
            if let container = try? decoder.container(keyedBy: DynamicCodingKey.self) {
                var values: [String: JSONValue] = [:]
                for key in container.allKeys {
                    values[key.stringValue] = try container.decode(JSONValue.self, forKey: key)
                }
                self = .object(values)
                return
            }

            if var container = try? decoder.unkeyedContainer() {
                var values: [JSONValue] = []
                while container.isAtEnd == false {
                    values.append(try container.decode(JSONValue.self))
                }
                self = .array(values)
                return
            }

            let container = try decoder.singleValueContainer()
            if container.decodeNil() {
                self = .null
            } else if let value = try? container.decode(Bool.self) {
                self = .bool(value)
            } else if let value = try? container.decode(Double.self) {
                self = .number(value)
            } else if let value = try? container.decode(String.self) {
                self = .string(value)
            } else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
            }
        }

        func encode(to encoder: Encoder) throws {
            switch self {
            case .object(let values):
                var container = encoder.container(keyedBy: DynamicCodingKey.self)
                for key in values.keys.sorted() {
                    try container.encode(values[key], forKey: DynamicCodingKey(key))
                }
            case .array(let values):
                var container = encoder.unkeyedContainer()
                for value in values {
                    try container.encode(value)
                }
            case .string(let value):
                var container = encoder.singleValueContainer()
                try container.encode(value)
            case .number(let value):
                var container = encoder.singleValueContainer()
                try container.encode(value)
            case .bool(let value):
                var container = encoder.singleValueContainer()
                try container.encode(value)
            case .null:
                var container = encoder.singleValueContainer()
                try container.encodeNil()
            }
        }
    }

    private enum UnknownFields {
        static func decode<K: CodingKey & CaseIterable>(
            from decoder: Decoder,
            excluding _: K.Type
        ) throws -> [String: JSONValue] where K.AllCases: Sequence, K.AllCases.Element == K {
            let knownKeys = Set(K.allCases.map(\.stringValue))
            let container = try decoder.container(keyedBy: DynamicCodingKey.self)
            var fields: [String: JSONValue] = [:]
            for key in container.allKeys where knownKeys.contains(key.stringValue) == false {
                fields[key.stringValue] = try container.decode(JSONValue.self, forKey: key)
            }
            return fields
        }

        static func encode<K: CodingKey & CaseIterable>(
            _ fields: [String: JSONValue],
            to encoder: Encoder,
            excluding _: K.Type
        ) throws where K.AllCases: Sequence, K.AllCases.Element == K {
            let knownKeys = Set(K.allCases.map(\.stringValue))
            var container = encoder.container(keyedBy: DynamicCodingKey.self)
            for key in fields.keys.sorted() where knownKeys.contains(key) == false {
                try container.encode(fields[key], forKey: DynamicCodingKey(key))
            }
        }
    }

    private struct StoredRegistry: Codable, Equatable {
        var activeAccountKey: String?
        var activeAccountActivatedAtMs: Int?
        var config: StoredRegistryConfig
        var accounts: [StoredAccount]
        var extraFields: [String: JSONValue]

        enum CodingKeys: String, CodingKey, CaseIterable {
            case activeAccountKey = "active_account_key"
            case activeAccountActivatedAtMs = "active_account_activated_at_ms"
            case config
            case accounts
        }

        init(
            activeAccountKey: String?,
            activeAccountActivatedAtMs: Int?,
            config: StoredRegistryConfig,
            accounts: [StoredAccount],
            extraFields: [String: JSONValue] = [:]
        ) {
            self.activeAccountKey = activeAccountKey
            self.activeAccountActivatedAtMs = activeAccountActivatedAtMs
            self.config = config
            self.accounts = accounts
            self.extraFields = extraFields
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            activeAccountKey = try container.decodeIfPresent(String.self, forKey: .activeAccountKey)
            activeAccountActivatedAtMs = try FlexibleNumber.intIfPresent(in: container, forKey: .activeAccountActivatedAtMs)
            config = try container.decodeIfPresent(StoredRegistryConfig.self, forKey: .config) ?? .default
            accounts = try container.decodeIfPresent([StoredAccount].self, forKey: .accounts) ?? []
            extraFields = try UnknownFields.decode(from: decoder, excluding: CodingKeys.self)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            if let activeAccountKey {
                try container.encode(activeAccountKey, forKey: .activeAccountKey)
            } else {
                try container.encodeNil(forKey: .activeAccountKey)
            }
            if let activeAccountActivatedAtMs {
                try container.encode(activeAccountActivatedAtMs, forKey: .activeAccountActivatedAtMs)
            } else {
                try container.encodeNil(forKey: .activeAccountActivatedAtMs)
            }
            try container.encode(config, forKey: .config)
            try container.encode(accounts, forKey: .accounts)
            try UnknownFields.encode(extraFields, to: encoder, excluding: CodingKeys.self)
        }

        static func empty() -> StoredRegistry {
            StoredRegistry(activeAccountKey: nil, activeAccountActivatedAtMs: nil, config: .default, accounts: [])
        }
    }

    private struct StoredRegistryConfig: Codable, Equatable {
        var autoSwitch: Bool
        var usageAPI: Bool
        var accountAPI: Bool
        var extraFields: [String: JSONValue]

        enum CodingKeys: String, CodingKey, CaseIterable {
            case autoSwitch = "auto_switch"
            case usageAPI = "usage_api"
            case accountAPI = "account_api"
        }

        static let `default` = StoredRegistryConfig(autoSwitch: false, usageAPI: false, accountAPI: false)

        init(autoSwitch: Bool, usageAPI: Bool, accountAPI: Bool, extraFields: [String: JSONValue] = [:]) {
            self.autoSwitch = autoSwitch
            self.usageAPI = usageAPI
            self.accountAPI = accountAPI
            self.extraFields = extraFields
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            autoSwitch = try container.decodeIfPresent(Bool.self, forKey: .autoSwitch) ?? false
            usageAPI = try container.decodeIfPresent(Bool.self, forKey: .usageAPI) ?? false
            accountAPI = try container.decodeIfPresent(Bool.self, forKey: .accountAPI) ?? false
            extraFields = try UnknownFields.decode(from: decoder, excluding: CodingKeys.self)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(autoSwitch, forKey: .autoSwitch)
            try container.encode(usageAPI, forKey: .usageAPI)
            try container.encode(accountAPI, forKey: .accountAPI)
            try UnknownFields.encode(extraFields, to: encoder, excluding: CodingKeys.self)
        }
    }

    private struct StoredAccount: Codable, Equatable {
        var accountKey: String?
        var chatgptAccountID: String?
        var chatgptUserID: String?
        var email: String?
        var alias: String?
        var accountName: String?
        var plan: String?
        var authMode: String?
        var createdAt: Int?
        var lastUsedAt: Int?
        var lastUsage: StoredUsage?
        var extraFields: [String: JSONValue]

        enum CodingKeys: String, CodingKey, CaseIterable {
            case accountKey = "account_key"
            case chatgptAccountID = "chatgpt_account_id"
            case chatgptUserID = "chatgpt_user_id"
            case email
            case alias
            case accountName = "account_name"
            case plan
            case authMode = "auth_mode"
            case createdAt = "created_at"
            case lastUsedAt = "last_used_at"
            case lastUsage = "last_usage"
        }

        init(
            accountKey: String? = nil,
            chatgptAccountID: String? = nil,
            chatgptUserID: String? = nil,
            email: String? = nil,
            alias: String? = nil,
            accountName: String? = nil,
            plan: String? = nil,
            authMode: String? = nil,
            createdAt: Int? = nil,
            lastUsedAt: Int? = nil,
            lastUsage: StoredUsage? = nil,
            extraFields: [String: JSONValue] = [:]
        ) {
            self.accountKey = accountKey
            self.chatgptAccountID = chatgptAccountID
            self.chatgptUserID = chatgptUserID
            self.email = email
            self.alias = alias
            self.accountName = accountName
            self.plan = plan
            self.authMode = authMode
            self.createdAt = createdAt
            self.lastUsedAt = lastUsedAt
            self.lastUsage = lastUsage
            self.extraFields = extraFields
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            accountKey = try container.decodeIfPresent(String.self, forKey: .accountKey)
            chatgptAccountID = try container.decodeIfPresent(String.self, forKey: .chatgptAccountID)
            chatgptUserID = try container.decodeIfPresent(String.self, forKey: .chatgptUserID)
            email = try container.decodeIfPresent(String.self, forKey: .email)
            alias = try container.decodeIfPresent(String.self, forKey: .alias)
            accountName = try container.decodeIfPresent(String.self, forKey: .accountName)
            plan = try container.decodeIfPresent(String.self, forKey: .plan)
            authMode = try container.decodeIfPresent(String.self, forKey: .authMode)
            createdAt = try FlexibleNumber.intIfPresent(in: container, forKey: .createdAt)
            lastUsedAt = try FlexibleNumber.intIfPresent(in: container, forKey: .lastUsedAt)
            lastUsage = try container.decodeIfPresent(StoredUsage.self, forKey: .lastUsage)
            extraFields = try UnknownFields.decode(from: decoder, excluding: CodingKeys.self)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(accountKey, forKey: .accountKey)
            try container.encodeIfPresent(chatgptAccountID, forKey: .chatgptAccountID)
            try container.encodeIfPresent(chatgptUserID, forKey: .chatgptUserID)
            try container.encodeIfPresent(email, forKey: .email)
            try container.encodeIfPresent(alias, forKey: .alias)
            try container.encodeIfPresent(accountName, forKey: .accountName)
            try container.encodeIfPresent(plan, forKey: .plan)
            try container.encodeIfPresent(authMode, forKey: .authMode)
            try container.encodeIfPresent(createdAt, forKey: .createdAt)
            try container.encodeIfPresent(lastUsedAt, forKey: .lastUsedAt)
            try container.encodeIfPresent(lastUsage, forKey: .lastUsage)
            try UnknownFields.encode(extraFields, to: encoder, excluding: CodingKeys.self)
        }

        mutating func updateUsage(_ limits: AppServerRateLimits) {
            var usage = lastUsage ?? StoredUsage()
            if let planType = limits.planType?.trimmingCharacters(in: .whitespacesAndNewlines),
               planType.isEmpty == false {
                usage.planType = planType
            }
            if let primary = limits.primary {
                var window = StoredUsageWindow(primary)
                window.extraFields = usage.primary?.extraFields ?? [:]
                usage.primary = window
            }
            if let secondary = limits.secondary {
                var window = StoredUsageWindow(secondary)
                window.extraFields = usage.secondary?.extraFields ?? [:]
                usage.secondary = window
            } else if limits.primary?.displayKind(fallback: .fiveHour) == .monthly {
                usage.secondary = nil
            }
            usage.updatedAt = Int(Date().timeIntervalSince1970)
            lastUsage = usage
        }
    }

    private struct StoredUsage: Codable, Equatable {
        var planType: String?
        var primary: StoredUsageWindow?
        var secondary: StoredUsageWindow?
        var updatedAt: Int?
        var extraFields: [String: JSONValue]

        enum CodingKeys: String, CodingKey, CaseIterable {
            case planType = "plan_type"
            case primary
            case secondary
            case updatedAt = "updated_at"
        }

        init(
            planType: String? = nil,
            primary: StoredUsageWindow? = nil,
            secondary: StoredUsageWindow? = nil,
            updatedAt: Int? = nil,
            extraFields: [String: JSONValue] = [:]
        ) {
            self.planType = planType
            self.primary = primary
            self.secondary = secondary
            self.updatedAt = updatedAt
            self.extraFields = extraFields
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            planType = try container.decodeIfPresent(String.self, forKey: .planType)
            primary = try container.decodeIfPresent(StoredUsageWindow.self, forKey: .primary)
            secondary = try container.decodeIfPresent(StoredUsageWindow.self, forKey: .secondary)
            updatedAt = try FlexibleNumber.intIfPresent(in: container, forKey: .updatedAt)
            extraFields = try UnknownFields.decode(from: decoder, excluding: CodingKeys.self)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(planType, forKey: .planType)
            try container.encodeIfPresent(primary, forKey: .primary)
            try container.encodeIfPresent(secondary, forKey: .secondary)
            try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
            try UnknownFields.encode(extraFields, to: encoder, excluding: CodingKeys.self)
        }
    }

    private struct StoredUsageWindow: Codable, Equatable {
        var usedPercent: Int?
        var kind: AppServerRateLimitWindow.Kind?
        var windowDurationMins: Double?
        var resetsAt: Double?
        var extraFields: [String: JSONValue]

        enum CodingKeys: String, CodingKey, CaseIterable {
            case usedPercent = "used_percent"
            case kind
            case windowDurationMins = "window_duration_mins"
            case resetsAt = "resets_at"
        }

        init(
            usedPercent: Int? = nil,
            kind: AppServerRateLimitWindow.Kind? = nil,
            windowDurationMins: Double? = nil,
            resetsAt: Double? = nil,
            extraFields: [String: JSONValue] = [:]
        ) {
            self.usedPercent = usedPercent
            self.kind = kind
            self.windowDurationMins = windowDurationMins
            self.resetsAt = resetsAt
            self.extraFields = extraFields
        }

        init(_ window: AppServerRateLimitWindow) {
            usedPercent = window.displayPercent
            kind = window.kind
            windowDurationMins = window.windowDurationMinutes
            resetsAt = window.resetsAt?.timeIntervalSince1970
            extraFields = [:]
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            usedPercent = try FlexibleNumber.intIfPresent(in: container, forKey: .usedPercent)
            kind = try container.decodeIfPresent(AppServerRateLimitWindow.Kind.self, forKey: .kind)
            windowDurationMins = try FlexibleNumber.doubleIfPresent(in: container, forKey: .windowDurationMins)
            resetsAt = try FlexibleNumber.doubleIfPresent(in: container, forKey: .resetsAt)
            extraFields = try UnknownFields.decode(from: decoder, excluding: CodingKeys.self)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(usedPercent, forKey: .usedPercent)
            try container.encodeIfPresent(kind, forKey: .kind)
            try container.encodeIfPresent(windowDurationMins, forKey: .windowDurationMins)
            try container.encodeIfPresent(resetsAt, forKey: .resetsAt)
            try UnknownFields.encode(extraFields, to: encoder, excluding: CodingKeys.self)
        }
    }

    private enum FlexibleNumber {
        static func intIfPresent<Key: CodingKey>(in container: KeyedDecodingContainer<Key>, forKey key: Key) throws -> Int? {
            if let int = try? container.decodeIfPresent(Int.self, forKey: key) { return int }
            if let double = try? container.decodeIfPresent(Double.self, forKey: key) { return Int(double) }
            if let string = try? container.decodeIfPresent(String.self, forKey: key) { return Int(string) }
            return nil
        }

        static func doubleIfPresent<Key: CodingKey>(in container: KeyedDecodingContainer<Key>, forKey key: Key) throws -> Double? {
            if let double = try? container.decodeIfPresent(Double.self, forKey: key) { return double }
            if let int = try? container.decodeIfPresent(Int.self, forKey: key) { return Double(int) }
            if let string = try? container.decodeIfPresent(String.self, forKey: key) { return Double(string) }
            return nil
        }
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
