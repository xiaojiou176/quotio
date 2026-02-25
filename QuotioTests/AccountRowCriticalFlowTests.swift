import XCTest
@testable import Quotio

final class AccountRowCriticalFlowTests: XCTestCase {
    func testProxyAccountRowMainJourneyExtractsEmailAndTeamFlag() {
        let auth = AuthFile(
            id: "acc-1",
            name: "codex-1d155e15-chatgpt71@xiaojiou176.me-team.json",
            provider: "openai",
            label: nil,
            status: "ready",
            statusMessage: nil,
            disabled: false,
            unavailable: false,
            email: nil,
            errorKind: nil,
            errorReason: nil
        )

        let row = AccountRowData.from(authFile: auth)

        XCTAssertEqual(row.source, .proxy)
        XCTAssertEqual(row.displayName, "chatgpt71@xiaojiou176.me")
        XCTAssertEqual(row.rawName, "codex-1d155e15-chatgpt71@xiaojiou176.me-team.json")
        XCTAssertTrue(row.isTeamAccount)
        XCTAssertTrue(row.canDelete)
    }

    func testProxyAccountRowErrorStateNormalizesNetworkErrorKind() {
        let auth = AuthFile(
            id: "acc-2",
            name: "network-user@example.com.json",
            provider: "openai",
            label: nil,
            status: "error",
            statusMessage: "network error while proxy forwarding",
            disabled: false,
            unavailable: true,
            email: "network-user@example.com",
            errorKind: "network-error",
            errorReason: "socket closed"
        )

        let row = AccountRowData.from(authFile: auth)

        XCTAssertEqual(row.status, "error")
        XCTAssertEqual(row.errorKind, "network_error")
        XCTAssertEqual(row.errorReason, "socket closed")
        XCTAssertFalse(row.isDisabled)
    }
}
