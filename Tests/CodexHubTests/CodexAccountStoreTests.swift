import XCTest
@testable import CodexHub

final class CodexAccountStoreTests: XCTestCase {
    private var previousCodexHome: String?

    override func setUp() {
        super.setUp()
        previousCodexHome = ProcessInfo.processInfo.environment["CODEX_HOME"]
    }

    override func tearDown() {
        if let previousCodexHome {
            setenv("CODEX_HOME", previousCodexHome, 1)
        } else {
            unsetenv("CODEX_HOME")
        }
        super.tearDown()
    }

    func testLoadAccountsCapturesCurrentAuthIntoRegistry() throws {
        let codexHome = try makeTemporaryCodexHome()
        defer { try? FileManager.default.removeItem(at: codexHome) }
        setenv("CODEX_HOME", codexHome.path, 1)
        try writeAuth(to: codexHome, userID: "user-1", accountID: "account-1", email: "one@example.com", plan: "chatgpt_plus")

        let result = CodexAccountStore(processRunner: .neverCalled).loadAccounts()

        XCTAssertNil(result.error)
        XCTAssertEqual(result.accounts.count, 1)
        XCTAssertEqual(result.accounts.first?.identity, "user-1::account-1")
        XCTAssertEqual(result.accounts.first?.email, "one@example.com")
        XCTAssertEqual(result.accounts.first?.plan, "chatgpt_plus")
        XCTAssertEqual(result.accounts.first?.isActive, true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: codexHome.appendingPathComponent("accounts/registry.json").path))
    }

    func testRemoveStoredAccountRemovesInactiveSnapshotAndRegistryEntry() throws {
        let codexHome = try makeTemporaryCodexHome()
        defer { try? FileManager.default.removeItem(at: codexHome) }
        setenv("CODEX_HOME", codexHome.path, 1)
        let store = CodexAccountStore(processRunner: .neverCalled)

        try writeAuth(to: codexHome, userID: "user-1", accountID: "account-1", email: "one@example.com", plan: "chatgpt_plus")
        XCTAssertEqual(store.captureCurrentLogin(alias: nil).status, 0)
        try writeAuth(to: codexHome, userID: "user-2", accountID: "account-2", email: "two@example.com", plan: "chatgpt_pro")
        XCTAssertEqual(store.captureCurrentLogin(alias: nil).status, 0)

        let remove = store.removeStoredAccount(identity: "user-1::account-1")
        let loaded = store.loadAccounts()

        XCTAssertEqual(remove.status, 0)
        XCTAssertEqual(loaded.accounts.map(\.identity), ["user-2::account-2"])
        XCTAssertEqual(loaded.accounts.first?.isActive, true)
    }

    func testRemoveStoredAccountRejectsActiveAccount() throws {
        let codexHome = try makeTemporaryCodexHome()
        defer { try? FileManager.default.removeItem(at: codexHome) }
        setenv("CODEX_HOME", codexHome.path, 1)
        let store = CodexAccountStore(processRunner: .neverCalled)

        try writeAuth(to: codexHome, userID: "user-1", accountID: "account-1", email: "one@example.com", plan: "chatgpt_plus")
        XCTAssertEqual(store.captureCurrentLogin(alias: nil).status, 0)

        let remove = store.removeStoredAccount(identity: "user-1::account-1")

        XCTAssertNotEqual(remove.status, 0)
        XCTAssertEqual(store.loadAccounts().accounts.count, 1)
    }

    func testLoadAccountsPreservesRegistryInsertionOrder() throws {
        let codexHome = try makeTemporaryCodexHome()
        defer { try? FileManager.default.removeItem(at: codexHome) }
        setenv("CODEX_HOME", codexHome.path, 1)
        let store = CodexAccountStore(processRunner: .neverCalled)

        try writeAuth(to: codexHome, userID: "user-n", accountID: "account-n", email: "n@example.com", plan: "chatgpt_edu")
        XCTAssertEqual(store.captureCurrentLogin(alias: nil).status, 0)
        try writeAuth(to: codexHome, userID: "user-w", accountID: "account-w", email: "w@example.com", plan: "chatgpt_team")
        XCTAssertEqual(store.captureCurrentLogin(alias: nil).status, 0)
        try writeAuth(to: codexHome, userID: "user-h", accountID: "account-h", email: "h@example.com", plan: "chatgpt_go")
        XCTAssertEqual(store.captureCurrentLogin(alias: nil).status, 0)

        let loaded = store.loadAccounts()

        XCTAssertEqual(loaded.accounts.map(\.email), ["n@example.com", "w@example.com", "h@example.com"])
    }

    func testUpdateStoredUsageStoresPlanAndClearsSecondaryForMonthlyQuota() throws {
        let codexHome = try makeTemporaryCodexHome()
        defer { try? FileManager.default.removeItem(at: codexHome) }
        setenv("CODEX_HOME", codexHome.path, 1)
        let store = CodexAccountStore(processRunner: .neverCalled)

        try writeAuth(to: codexHome, userID: "user-1", accountID: "account-1", email: "one@example.com", plan: "unknown")
        XCTAssertEqual(store.captureCurrentLogin(alias: nil).status, 0)
        store.updateStoredUsage(
            identity: "user-1::account-1",
            limits: AppServerRateLimits(
                primary: AppServerRateLimitWindow(
                    displayPercent: 25,
                    resetsAt: Date(timeIntervalSince1970: 1_800_000_000),
                    kind: .monthly,
                    windowDurationMinutes: 30 * 24 * 60
                ),
                secondary: nil,
                planType: "chatgpt_pro"
            )
        )

        let account = try XCTUnwrap(store.loadAccounts().accounts.first)
        XCTAssertEqual(account.plan, "chatgpt_pro")
        XCTAssertEqual(account.primaryQuotaLabel, "1mo")
        XCTAssertEqual(account.fiveHourUsedPercent, 25)
        XCTAssertFalse(account.shouldShowSecondaryQuota)
        XCTAssertNil(account.weeklyUsedPercent)
    }

    func testLoadAccountsAcceptsMinimalRegistryJSON() throws {
        let codexHome = try makeTemporaryCodexHome()
        defer { try? FileManager.default.removeItem(at: codexHome) }
        setenv("CODEX_HOME", codexHome.path, 1)
        let accountsDirectory = codexHome.appendingPathComponent("accounts", isDirectory: true)
        try FileManager.default.createDirectory(at: accountsDirectory, withIntermediateDirectories: true)
        try writeAuth(to: codexHome, userID: "user-1", accountID: "account-1", email: "one@example.com", plan: "chatgpt_plus")
        let registry = """
        {
          "active_account_key": "user-1::account-1",
          "accounts": [
            {
              "account_key": "user-1::account-1",
              "email": "one@example.com",
              "plan": "chatgpt_plus",
              "last_used_at": "1800000000"
            }
          ]
        }
        """
        try registry.write(to: accountsDirectory.appendingPathComponent("registry.json"), atomically: true, encoding: .utf8)

        let loaded = CodexAccountStore(processRunner: .neverCalled).loadAccounts()

        XCTAssertNil(loaded.error)
        XCTAssertEqual(loaded.accounts.count, 1)
        XCTAssertEqual(loaded.accounts.first?.identity, "user-1::account-1")
        XCTAssertEqual(loaded.accounts.first?.email, "one@example.com")
        XCTAssertEqual(loaded.accounts.first?.isActive, true)
    }

    func testUpdateStoredUsagePreservesUnknownRegistryFields() throws {
        let codexHome = try makeTemporaryCodexHome()
        defer { try? FileManager.default.removeItem(at: codexHome) }
        setenv("CODEX_HOME", codexHome.path, 1)
        let accountsDirectory = codexHome.appendingPathComponent("accounts", isDirectory: true)
        try FileManager.default.createDirectory(at: accountsDirectory, withIntermediateDirectories: true)
        let registryURL = accountsDirectory.appendingPathComponent("registry.json")
        let registry = """
        {
          "active_account_key": "user-1::account-1",
          "future_top_level": {"keep": true},
          "config": {
            "auto_switch": true,
            "future_config": ["a", "b"]
          },
          "accounts": [
            {
              "account_key": "user-1::account-1",
              "email": "one@example.com",
              "future_account": 42,
              "last_usage": {
                "future_usage": "keep",
                "primary": {
                  "used_percent": 10,
                  "future_window": {"nested": 1}
                }
              }
            }
          ]
        }
        """
        try registry.write(to: registryURL, atomically: true, encoding: .utf8)

        CodexAccountStore(processRunner: .neverCalled).updateStoredUsage(
            identity: "user-1::account-1",
            limits: AppServerRateLimits(
                primary: AppServerRateLimitWindow(displayPercent: 20, resetsAt: nil, kind: .fiveHour),
                secondary: nil,
                planType: "chatgpt_plus"
            )
        )

        let data = try Data(contentsOf: registryURL)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(object["future_top_level"])
        let config = try XCTUnwrap(object["config"] as? [String: Any])
        XCTAssertNotNil(config["future_config"])
        let accounts = try XCTUnwrap(object["accounts"] as? [[String: Any]])
        let account = try XCTUnwrap(accounts.first)
        XCTAssertEqual(account["future_account"] as? Double, 42)
        let usage = try XCTUnwrap(account["last_usage"] as? [String: Any])
        XCTAssertEqual(usage["future_usage"] as? String, "keep")
        let primary = try XCTUnwrap(usage["primary"] as? [String: Any])
        XCTAssertNotNil(primary["future_window"])
        XCTAssertEqual(primary["used_percent"] as? Int, 20)
    }

    private func makeTemporaryCodexHome() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexAccountStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeAuth(to codexHome: URL, userID: String, accountID: String, email: String, plan: String) throws {
        let claims: [String: Any] = [
            "https://api.openai.com/auth": [
                "chatgpt_account_id": accountID,
                "chatgpt_user_id": userID,
                "chatgpt_plan_type": plan
            ],
            "https://api.openai.com/profile": [
                "email": email
            ],
            "name": email
        ]
        let token = try makeJWT(claims: claims)
        let auth: [String: Any] = [
            "auth_mode": "chatgpt",
            "tokens": [
                "account_id": accountID,
                "id_token": token,
                "access_token": token
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: auth, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: codexHome.appendingPathComponent("auth.json"), options: .atomic)
    }

    private func makeJWT(claims: [String: Any]) throws -> String {
        let header = try JSONSerialization.data(withJSONObject: ["alg": "none"], options: [])
        let payload = try JSONSerialization.data(withJSONObject: claims, options: [])
        return [
            base64URLEncoded(header),
            base64URLEncoded(payload),
            "signature"
        ].joined(separator: ".")
    }

    private func base64URLEncoded(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
    }
}

private extension ProcessRunner {
    static let neverCalled = ProcessRunner { _, _, _, _ in
        XCTFail("ProcessRunner should not be called")
        return CommandResult(status: 127, output: "unexpected process invocation")
    }
}
