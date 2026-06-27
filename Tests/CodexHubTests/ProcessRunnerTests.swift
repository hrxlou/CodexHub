import XCTest
@testable import CodexHub

final class ProcessRunnerTests: XCTestCase {
    func testLiveRunnerCapturesOutputAndStatus() {
        let result = ProcessRunner.live.run(
            "/bin/echo",
            ["hello"],
            5,
            CodexProcessEnvironment.make(prependingExecutableDirectory: "/bin/echo")
        )

        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.output.trimmingCharacters(in: .whitespacesAndNewlines), "hello")
    }

    func testEnvironmentPrependsExecutableDirectoryAndAppliesOverrides() {
        let environment = CodexProcessEnvironment.make(
            prependingExecutableDirectory: "/tmp/tool/bin/codex",
            overrides: ["CODEX_HOME": "/tmp/codex-home"]
        )

        XCTAssertEqual(environment["CODEX_HOME"], "/tmp/codex-home")
        XCTAssertTrue(environment["PATH"]?.hasPrefix("/tmp/tool/bin:") == true)
    }
}
