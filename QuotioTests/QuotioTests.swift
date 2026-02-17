import XCTest
@testable import Quotio

final class QuotioTests: XCTestCase {
    func testProviderSlugNormalizationIsStable() {
        let slugs = ["Codex", "Claude", "Gemini", "Copilot"]
        let normalized = slugs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

        XCTAssertEqual(normalized, ["codex", "claude", "gemini", "copilot"])
        XCTAssertEqual(Set(normalized).count, slugs.count)
    }

    func testProxyURLSanitizeRemovesCredentialsAndTrailingSlash() {
        let raw = "  http://alice:secret@example.com:8080/proxy/  "
        let sanitized = ProxyURLValidator.sanitize(raw)
        XCTAssertEqual(sanitized, "http://example.com:8080/proxy")
        XCTAssertFalse(sanitized.contains("alice"))
        XCTAssertFalse(sanitized.contains("secret"))
    }

    func testProxyURLValidateRequiresPortForSocks5() {
        XCTAssertEqual(ProxyURLValidator.validate("socks5://127.0.0.1"), .missingPort)
        XCTAssertEqual(ProxyURLValidator.validate("socks5://127.0.0.1:1080"), .valid)
    }

    func testSSEEventDedupeKeyPrefersRequestID() {
        let event = SSERequestEvent(
            type: "request",
            timestamp: "2026-02-16T00:00:00Z",
            requestId: "req-123",
            provider: "openai",
            model: "gpt-5",
            authFile: "default",
            source: "codex",
            success: true,
            tokens: 42,
            latencyMs: 90,
            error: nil
        )
        XCTAssertEqual(event.dedupeKey, "req-123")
    }

    func testSSEEventDedupeKeyFallbackIsStableForSamePayload() {
        let eventA = SSERequestEvent(
            type: "request",
            timestamp: "2026-02-16T00:00:00Z",
            requestId: nil,
            provider: "openai",
            model: "gpt-5",
            authFile: "default",
            source: "codex",
            success: true,
            tokens: 42,
            latencyMs: nil,
            error: nil
        )
        let eventB = SSERequestEvent(
            type: "request",
            timestamp: "2026-02-16T00:00:00Z",
            requestId: nil,
            provider: "openai",
            model: "gpt-5",
            authFile: "default",
            source: "codex",
            success: true,
            tokens: 42,
            latencyMs: nil,
            error: nil
        )
        XCTAssertEqual(eventA.dedupeKey, eventB.dedupeKey)
    }

    func testRequestHistoryItemIDFallbackWhenRequestIDMissing() {
        let item = RequestHistoryItem(
            timestamp: "2026-02-16T00:00:00Z",
            requestId: nil,
            apiKey: nil,
            model: "gpt-5",
            authIndex: "primary",
            source: "codex",
            success: true,
            tokens: 1
        )
        XCTAssertEqual(item.id, "2026-02-16T00:00:00Z|primary|gpt-5|codex||1|true")
    }

    func testRequestHistoryItemIDFallbackSeparatesDistinctRequests() {
        let base = RequestHistoryItem(
            timestamp: "2026-02-16T00:00:00Z",
            requestId: nil,
            apiKey: "openai-main",
            model: "gpt-5",
            authIndex: "primary",
            source: "codex",
            success: true,
            tokens: 10
        )
        let differentSource = RequestHistoryItem(
            timestamp: "2026-02-16T00:00:00Z",
            requestId: nil,
            apiKey: "openai-main",
            model: "gpt-5",
            authIndex: "primary",
            source: "cli",
            success: true,
            tokens: 10
        )

        XCTAssertNotEqual(base.id, differentSource.id)
    }
}
