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

    func testReviewQueueHistoryPrefersSummaryJson() async throws {
        let workspace = try makeTempWorkspace(name: "review-queue-summary")
        defer { try? FileManager.default.removeItem(at: workspace) }
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

        let first = try await Self.loadFirstHistoryItem(workspacePath: workspace.path)
        XCTAssertEqual(first.jobId, "20260217-120000-abc12345")
        XCTAssertEqual(first.workerCount, 4)
        XCTAssertEqual(first.failedWorkerCount, 1)
        XCTAssertEqual(first.phase, .completed)
        XCTAssertEqual(first.model, "gpt-5.3-codex")
    }

    func testReviewQueueHistoryFallbackInferenceWithoutSummary() async throws {
        let workspace = try makeTempWorkspace(name: "review-queue-fallback")
        defer { try? FileManager.default.removeItem(at: workspace) }
        let queueDir = workspace
            .appendingPathComponent(".runtime-cache")
            .appendingPathComponent("review-queue")
            .appendingPathComponent("20260217-130000-def67890")
        try FileManager.default.createDirectory(at: queueDir, withIntermediateDirectories: true)

        let workerPath = queueDir.appendingPathComponent("worker-01.md")
        try "worker output".write(to: workerPath, atomically: true, encoding: .utf8)
        let stderrPath = queueDir.appendingPathComponent("worker-01.stderr.log")
        try "fatal error".write(to: stderrPath, atomically: true, encoding: .utf8)

        let first = try await Self.loadFirstHistoryItem(workspacePath: workspace.path)
        XCTAssertEqual(first.workerCount, 1)
        XCTAssertEqual(first.failedWorkerCount, 1)
        XCTAssertEqual(first.phase, .failed)
    }

    func testReviewQueueHistoryFallbackMarksAggregateOnlyRunAsCompleted() async throws {
        let workspace = try makeTempWorkspace(name: "review-queue-aggregate-only")
        defer { try? FileManager.default.removeItem(at: workspace) }
        let queueDir = workspace
            .appendingPathComponent(".runtime-cache")
            .appendingPathComponent("review-queue")
            .appendingPathComponent("20260217-140000-a1b2c3d4")
        try FileManager.default.createDirectory(at: queueDir, withIntermediateDirectories: true)

        try "worker output".write(to: queueDir.appendingPathComponent("worker-01.md"), atomically: true, encoding: .utf8)
        try "aggregate output".write(to: queueDir.appendingPathComponent("aggregate.md"), atomically: true, encoding: .utf8)

        let config = ReviewQueueConfig(
            workspacePath: workspace.path,
            reviewPrompts: ["deep review"],
            aggregatePrompt: "aggregate",
            fixPrompt: "fix",
            runAggregate: true,
            runFix: false,
            model: "gpt-5.3-codex",
            fullAuto: true,
            skipGitRepoCheck: false,
            ephemeral: false
        )
        let configData = try JSONEncoder().encode(config)
        try configData.write(to: queueDir.appendingPathComponent("config.json"))

        let first = try await Self.loadFirstHistoryItem(workspacePath: workspace.path)
        XCTAssertEqual(first.phase, .completed)
        XCTAssertNotNil(first.aggregateOutputPath)
        XCTAssertNil(first.fixOutputPath)
    }

    func testReviewQueueMaxConcurrentWorkersIsCapped() {
        XCTAssertEqual(CodexReviewQueueService.maxConcurrentWorkers(for: 0), 0)
        XCTAssertEqual(CodexReviewQueueService.maxConcurrentWorkers(for: 1), 1)
        XCTAssertEqual(CodexReviewQueueService.maxConcurrentWorkers(for: ReviewQueueLimits.maxWorkers), ReviewQueueLimits.maxWorkers)
        XCTAssertEqual(CodexReviewQueueService.maxConcurrentWorkers(for: 100), ReviewQueueLimits.maxWorkers)
    }

    func testReviewQueuePromptPlanningForCustomPromptsShowsBatching() async throws {
        try await MainActor.run {
            let vm = ReviewQueueViewModel()
            vm.useCustomPrompts = true
            vm.customReviewPromptsText = (1...12).map { "prompt-\($0)" }.joined(separator: "\n")

            XCTAssertEqual(vm.customPromptCount, 12)
            XCTAssertEqual(vm.plannedPromptCount, 12)
            XCTAssertEqual(vm.plannedConcurrentWorkers, ReviewQueueLimits.maxWorkers)
            XCTAssertTrue(vm.willQueueInBatches)
        }
    }

    func testReviewQueuePromptPlanningForSharedPromptCapsWorkerCount() async throws {
        try await MainActor.run {
            let vm = ReviewQueueViewModel()
            vm.useCustomPrompts = false
            vm.sharedReviewPrompt = "deep review"
            vm.workerCount = 99

            XCTAssertEqual(vm.plannedPromptCount, ReviewQueueLimits.maxWorkers)
            XCTAssertEqual(vm.plannedConcurrentWorkers, ReviewQueueLimits.maxWorkers)
            XCTAssertFalse(vm.willQueueInBatches)
        }
    }

    func testCLIExecutorWithInputReturnsQuicklyAfterCancellation() async throws {
        let executor = CLIExecutor.shared
        let start = Date()
        let task = Task {
            await executor.executeCLIWithInput(
                name: "bash",
                arguments: ["-lc", "sleep 10"],
                input: "",
                timeout: 30
            )
        }

        try await Task.sleep(nanoseconds: 300_000_000)
        task.cancel()
        let result = await task.value
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertLessThan(elapsed, 5.0)
        XCTAssertFalse(result.success)
        XCTAssertEqual(result.exitCode, -2)
        XCTAssertTrue(result.errorOutput.localizedCaseInsensitiveContains("cancel"))
    }

    func testReviewQueueWorkerArgumentsRemainCompatibleWithCurrentCLI() {
        let config = makeReviewQueueConfigForCLICompatibility()
        let arguments = CodexReviewQueueService.reviewWorkerArguments(config: config)

        assertHasCommonExecFlags(arguments)
        XCTAssertTrue(arguments.contains("review"))
        XCTAssertTrue(arguments.contains("--json"))
        XCTAssertFalse(arguments.contains("--output-last-message"))
        XCTAssertEqual(arguments.last, "-")
    }

    func testReviewQueueAggregateArgumentsRemainCompatibleWithCurrentCLI() {
        let config = makeReviewQueueConfigForCLICompatibility()
        let outputPath = "/tmp/aggregate.md"
        let arguments = CodexReviewQueueService.aggregateStageArguments(config: config, outputPath: outputPath)

        assertHasCommonExecFlags(arguments)
        XCTAssertTrue(arguments.contains("--json"))
        XCTAssertTrue(arguments.contains("--output-last-message"))
        XCTAssertFalse(arguments.contains("review"))
        assertHasOutputPathAndStdin(arguments, outputPath: outputPath)
    }

    func testReviewQueueFixArgumentsRemainCompatibleWithCurrentCLI() {
        let config = makeReviewQueueConfigForCLICompatibility()
        let outputPath = "/tmp/fix.md"
        let arguments = CodexReviewQueueService.fixStageArguments(config: config, outputPath: outputPath)

        assertHasCommonExecFlags(arguments)
        XCTAssertTrue(arguments.contains("--json"))
        XCTAssertTrue(arguments.contains("--output-last-message"))
        XCTAssertFalse(arguments.contains("review"))
        assertHasOutputPathAndStdin(arguments, outputPath: outputPath)
    }

    func testParseLastAgentMessageIgnoresInterleavedUnknownEvents() {
        let jsonl = """
        {"type":"turn.started","id":"turn-1"}
        {"type":"model/rerouted","model":"gpt-5.3-codex-low"}
        {"type":"item.completed","item":{"type":"agent_message","text":"first"}}
        {"type":"custom/new_event","payload":{"x":1}}
        {"type":"item.completed","item":{"type":"agent_message","text":"final message"}}
        """

        let parsed = CodexReviewQueueService.parseLastAgentMessageFromJSONL(jsonl)
        XCTAssertEqual(parsed, "final message")
    }

    func testParseLastAgentMessageReturnsNilWhenNoAgentMessage() {
        let jsonl = """
        {"type":"turn.started","id":"turn-1"}
        {"type":"item.completed","item":{"type":"tool_call","text":"ignored"}}
        {"type":"model/rerouted","model":"gpt-5.3-codex-low"}
        """

        let parsed = CodexReviewQueueService.parseLastAgentMessageFromJSONL(jsonl)
        XCTAssertNil(parsed)
    }

    func testAtomFeedHeaderSanitizerNormalizesLegacyEscapedETag() {
        let legacy = #" W\/"cc057be83df695f54f499e2ef1f36f26" "#
        let sanitized = AtomFeedHeaderSanitizer.sanitizeETag(legacy)
        XCTAssertEqual(sanitized, #"W/"cc057be83df695f54f499e2ef1f36f26""#)
    }

    func testAtomFeedHeaderSanitizerRejectsControlCharacters() {
        let malformed = "W/\"abc\"\nInjected: yes"
        XCTAssertNil(AtomFeedHeaderSanitizer.sanitizeETag(malformed))
    }

    private func assertHasCommonExecFlags(_ arguments: [String], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(arguments.prefix(4), ["exec", "--model", "gpt-5.3-codex", "--full-auto"], file: file, line: line)
        XCTAssertTrue(arguments.contains("--skip-git-repo-check"), file: file, line: line)
        XCTAssertTrue(arguments.contains("--ephemeral"), file: file, line: line)
    }

    private func assertHasOutputPathAndStdin(_ arguments: [String], outputPath: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(arguments.suffix(2), [outputPath, "-"], file: file, line: line)
    }

    private func makeReviewQueueConfigForCLICompatibility() -> ReviewQueueConfig {
        ReviewQueueConfig(
            workspacePath: "/tmp",
            reviewPrompts: ["review this repo"],
            aggregatePrompt: "aggregate",
            fixPrompt: "fix",
            runAggregate: true,
            runFix: true,
            model: "gpt-5.3-codex",
            fullAuto: true,
            skipGitRepoCheck: true,
            ephemeral: true
        )
    }

    private func makeTempWorkspace(name: String) throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let dir = root.appendingPathComponent("quotio-tests-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @MainActor
    private static func loadFirstHistoryItem(workspacePath: String) async throws -> ReviewQueueHistoryItem {
        let vm = ReviewQueueViewModel()
        vm.workspacePath = workspacePath
        vm.refreshHistory()
        for _ in 0..<40 {
            if let first = vm.historyItems.first {
                return first
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("Timed out waiting for review queue history refresh")
        throw NSError(domain: "QuotioTests", code: 1)
    }
}
