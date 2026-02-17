import XCTest
@testable import Quotio

final class QuotioTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
    }

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
            seq: nil,
            eventId: nil,
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
            seq: nil,
            eventId: nil,
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
            seq: nil,
            eventId: nil,
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

    @MainActor
    func testReviewQueueHistoryPrefersSummaryJson() throws {
        let workspace = try makeTempWorkspace(name: "review-queue-summary")
        let queueDir = workspace
            .appendingPathComponent(".runtime-cache")
            .appendingPathComponent("review-queue")
            .appendingPathComponent("20260217-120000-abc12345")
        try FileManager.default.createDirectory(at: queueDir, withIntermediateDirectories: true)

        let summary = ReviewQueueJobSummary(
            version: 1,
            jobId: "20260217-120000-abc12345",
            jobPath: queueDir.path,
            phase: .completed,
            createdAt: Date(timeIntervalSince1970: 1_739_793_600),
            updatedAt: Date(timeIntervalSince1970: 1_739_793_660),
            workerCount: 4,
            completedWorkerCount: 3,
            failedWorkerCount: 1,
            workers: [
                ReviewWorkerResult(id: 1, prompt: "p1", status: .completed, outputPath: nil, stdoutPath: nil, stderrPath: nil, error: nil),
                ReviewWorkerResult(id: 2, prompt: "p2", status: .failed, outputPath: nil, stdoutPath: nil, stderrPath: nil, error: "x")
            ],
            aggregateOutputPath: nil,
            fixOutputPath: nil,
            runAggregate: true,
            runFix: true,
            model: "gpt-5.3-codex"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(summary)
        try data.write(to: queueDir.appendingPathComponent("summary.json"))

        let vm = ReviewQueueViewModel()
        vm.workspacePath = workspace.path
        vm.refreshHistory()

        let first = try XCTUnwrap(vm.historyItems.first)
        XCTAssertEqual(first.jobId, "20260217-120000-abc12345")
        XCTAssertEqual(first.workerCount, 4)
        XCTAssertEqual(first.failedWorkerCount, 1)
        XCTAssertEqual(first.phase, .completed)
        XCTAssertEqual(first.model, "gpt-5.3-codex")
    }

    @MainActor
    func testReviewQueueHistoryFallbackInferenceWithoutSummary() throws {
        let workspace = try makeTempWorkspace(name: "review-queue-fallback")
        let queueDir = workspace
            .appendingPathComponent(".runtime-cache")
            .appendingPathComponent("review-queue")
            .appendingPathComponent("20260217-130000-def67890")
        try FileManager.default.createDirectory(at: queueDir, withIntermediateDirectories: true)

        let workerPath = queueDir.appendingPathComponent("worker-01.md")
        try "worker output".write(to: workerPath, atomically: true, encoding: .utf8)
        let stderrPath = queueDir.appendingPathComponent("worker-01.stderr.log")
        try "fatal error".write(to: stderrPath, atomically: true, encoding: .utf8)

        let vm = ReviewQueueViewModel()
        vm.workspacePath = workspace.path
        vm.refreshHistory()

        let first = try XCTUnwrap(vm.historyItems.first)
        XCTAssertEqual(first.workerCount, 1)
        XCTAssertEqual(first.failedWorkerCount, 1)
        XCTAssertEqual(first.phase, .failed)
    }

    private func makeTempWorkspace(name: String) throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let dir = root.appendingPathComponent("quotio-tests-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: dir)
        }
        return dir
    }
}
