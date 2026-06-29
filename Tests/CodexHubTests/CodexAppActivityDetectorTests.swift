import XCTest
@testable import CodexHub

final class CodexAppActivityDetectorTests: XCTestCase {
    func testParsesLoadedThreadIDs() {
        let line = #"{"jsonrpc":"2.0","id":2,"result":{"data":["thread-a","thread-b"],"nextCursor":null}}"#

        XCTAssertEqual(
            CodexAppThreadActivityParser.parseLoadedThreadIDs(from: line, responseID: 2),
            ["thread-a", "thread-b"]
        )
        XCTAssertNil(CodexAppThreadActivityParser.parseLoadedThreadIDs(from: line, responseID: 3))
    }

    func testParsesActiveThreadStatusAndFlags() {
        let line = #"{"jsonrpc":"2.0","id":5,"result":{"thread":{"id":"thread-a","status":{"type":"active","activeFlags":["waitingOnApproval","waitingOnUserInput"]}}}}"#

        let status = CodexAppThreadActivityParser.parseThreadReadStatus(from: line, responseID: 5)

        XCTAssertEqual(status?.isActive, true)
        XCTAssertEqual(status?.activeFlags, ["waitingOnApproval", "waitingOnUserInput"])
    }

    func testParsesIdleThreadStatusAsInactive() {
        let line = #"{"jsonrpc":"2.0","id":5,"result":{"thread":{"id":"thread-a","status":{"type":"idle"}}}}"#

        let status = CodexAppThreadActivityParser.parseThreadReadStatus(from: line, responseID: 5)

        XCTAssertEqual(status?.isActive, false)
        XCTAssertEqual(status?.activeFlags, [])
    }
}
