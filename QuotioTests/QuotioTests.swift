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

    func testAvailableModelProviderPresentationUsesVertexClaudeForVertexLiteOwner() {
        let presentation = AvailableModel.providerPresentation(
            rawProvider: "vertex-lite",
            modelId: "claude-sonnet-4-5"
        )

        XCTAssertEqual(presentation.displayLabel, "Vertex Claude")
        XCTAssertEqual(presentation.iconProvider, .vertex)
    }

    func testAvailableModelProviderPresentationUsesVertexClaudeForVertexSonnetModel() {
        let presentation = AvailableModel.providerPresentation(
            rawProvider: "anthropic",
            modelId: "vertex-sonnet-4-5"
        )

        XCTAssertEqual(presentation.displayLabel, "Vertex Claude")
        XCTAssertEqual(presentation.iconProvider, .vertex)
    }

    func testAvailableModelProviderPresentationKeepsRegularClaudeMapping() {
        let presentation = AvailableModel.providerPresentation(
            rawProvider: "anthropic",
            modelId: "claude-sonnet-4-5"
        )

        XCTAssertNotEqual(presentation.displayLabel, "Vertex Claude")
        XCTAssertEqual(presentation.iconProvider, .claude)
    }

    @MainActor
    func testUpstreamHitClassifierCountsVertex() {
        let kind = UnifiedProxySettingsSection.classifyUpstreamHit(
            provider: "openai",
            model: "vertex-sonnet-4-5",
            source: nil,
            authFile: nil
        )
        XCTAssertEqual(kind, .vertex)
    }

    @MainActor
    func testUpstreamHitClassifierCountsV0() {
        let kind = UnifiedProxySettingsSection.classifyUpstreamHit(
            provider: "custom",
            model: "custom-model",
            source: "v0.dev",
            authFile: nil
        )
        XCTAssertEqual(kind, .v0)
    }

    @MainActor
    func testUpstreamHitClassifierCountsGemini() {
        let kind = UnifiedProxySettingsSection.classifyUpstreamHit(
            provider: "google",
            model: "gemini-2.5-pro",
            source: nil,
            authFile: nil
        )
        XCTAssertEqual(kind, .gemini)
    }

    @MainActor
    func testUpstreamHitClassifierIgnoresUnrelatedModel() {
        let kind = UnifiedProxySettingsSection.classifyUpstreamHit(
            provider: "openai",
            model: "gpt-5.3-codex",
            source: "codex-cli",
            authFile: "default"
        )
        XCTAssertEqual(kind, .other)
    }

    @MainActor
    func testUpstreamHitWindowSnapshotSeparatesCurrentAndPreviousWindows() {
        let now = Date(timeIntervalSince1970: 1_768_000_000)
        let currentVertex = SSERequestEvent(
            type: "request",
            seq: nil,
            eventId: nil,
            timestamp: ISO8601DateFormatter().string(from: now.addingTimeInterval(-5 * 60)),
            requestId: nil,
            provider: "openai",
            model: "vertex-sonnet-4-5",
            authFile: nil,
            source: nil,
            success: true,
            tokens: nil,
            latencyMs: nil,
            error: nil
        )
        let previousGemini = SSERequestEvent(
            type: "request",
            seq: nil,
            eventId: nil,
            timestamp: ISO8601DateFormatter().string(from: now.addingTimeInterval(-20 * 60)),
            requestId: nil,
            provider: "google",
            model: "gemini-2.5-pro",
            authFile: nil,
            source: nil,
            success: true,
            tokens: nil,
            latencyMs: nil,
            error: nil
        )
        let oldV0 = SSERequestEvent(
            type: "request",
            seq: nil,
            eventId: nil,
            timestamp: ISO8601DateFormatter().string(from: now.addingTimeInterval(-40 * 60)),
            requestId: nil,
            provider: "custom",
            model: "v0",
            authFile: nil,
            source: "v0.dev",
            success: true,
            tokens: nil,
            latencyMs: nil,
            error: nil
        )

        let snapshot = UnifiedProxySettingsSection.calculateUpstreamHitWindowSnapshot(
            events: [currentVertex, previousGemini, oldV0],
            now: now
        )

        XCTAssertEqual(snapshot.current.vertex, 1)
        XCTAssertEqual(snapshot.current.gemini, 0)
        XCTAssertEqual(snapshot.previous.gemini, 1)
        XCTAssertEqual(snapshot.previous.v0, 0)
    }

    @MainActor
    func testUpstreamHitTrendAndShareHelpers() {
        XCTAssertEqual(
            UnifiedProxySettingsSection.upstreamHitTrendSymbol(current: 5, previous: 2),
            "↑"
        )
        XCTAssertEqual(
            UnifiedProxySettingsSection.upstreamHitTrendSymbol(current: 1, previous: 3),
            "↓"
        )
        XCTAssertEqual(
            UnifiedProxySettingsSection.upstreamHitTrendSymbol(current: 4, previous: 4),
            "→"
        )

        XCTAssertEqual(UnifiedProxySettingsSection.upstreamHitShare(count: 0, total: 0), 0)
        XCTAssertEqual(UnifiedProxySettingsSection.upstreamHitShareText(count: 1, total: 4), "25%")
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

    func testCLIExecutorWithInputHandlesLargeStdoutWithoutBlocking() async {
        let executor = CLIExecutor.shared
        let result = await executor.executeCLIWithInput(
            name: "bash",
            arguments: ["-lc", "yes x | head -n 60000"],
            input: "",
            timeout: 5
        )

        XCTAssertTrue(result.success, "Expected command to succeed, got: \(result.errorOutput)")
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertFalse(result.output.isEmpty)
        XCTAssertTrue(result.output.contains("x"))
    }

    func testResolveStartupPortsSkipsOccupiedPortInDirectMode() throws {
        let occupiedPorts: Set<UInt16> = [8080, 8081]
        let ports = try CLIProxyManager.resolveStartupPorts(
            preferredUserPort: 8080,
            bridgeEnabled: false,
            isPortInUse: { occupiedPorts.contains($0) }
        )
        XCTAssertEqual(ports.userPort, 8082)
        XCTAssertEqual(ports.cliProxyPort, 8082)
    }

    func testResolveStartupPortsSkipsWhenBridgeInternalPortIsOccupied() throws {
        let occupiedPorts: Set<UInt16> = [8080, 18081]
        let ports = try CLIProxyManager.resolveStartupPorts(
            preferredUserPort: 8080,
            bridgeEnabled: true,
            isPortInUse: { occupiedPorts.contains($0) }
        )
        XCTAssertEqual(ports.userPort, 8082)
        XCTAssertEqual(ports.cliProxyPort, 18082)
    }

    func testResolveStartupPortsThrowsWhenNoPortAvailable() {
        XCTAssertThrowsError(
            try CLIProxyManager.resolveStartupPorts(
                preferredUserPort: UInt16.max,
                bridgeEnabled: false,
                isPortInUse: { _ in true }
            )
        )
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

    func testProxyBridgeDecrementedActiveConnectionsNeverGoesNegative() {
        XCTAssertEqual(ProxyBridge.decrementedActiveConnections(3), 2)
        XCTAssertEqual(ProxyBridge.decrementedActiveConnections(1), 0)
        XCTAssertEqual(ProxyBridge.decrementedActiveConnections(0), 0)
    }

    func testProxyBridgeUpdatedResponseWindowKeepsHeadAndTail() {
        let existing = Data((0..<10).map(UInt8.init))
        let incoming = Data((10..<30).map(UInt8.init))

        let window = ProxyBridge.updatedResponseWindow(
            existing: existing,
            incoming: incoming,
            headLimit: 4,
            tailLimit: 6
        )

        XCTAssertEqual(Array(window), [0, 1, 2, 3, 24, 25, 26, 27, 28, 29])
        XCTAssertEqual(window.count, 10)
    }

    func testProxyBridgeUpdatedResponseWindowLeavesSmallPayloadUntouched() {
        let existing = Data([1, 2, 3])
        let incoming = Data([4, 5])

        let window = ProxyBridge.updatedResponseWindow(
            existing: existing,
            incoming: incoming,
            headLimit: 8,
            tailLimit: 8
        )

        XCTAssertEqual(Array(window), [1, 2, 3, 4, 5])
    }

    func testUIExperienceDefaultPayloadEvidenceCaptureIsDisabled() {
        XCTAssertFalse(UIExperienceSettingsManager.defaultCaptureRequestPayloadEvidence)
    }

    func testPrivacyRedactorRedactsEndpointQueryValues() {
        let endpoint = "/v1/chat/completions?api_key=sk-secret&trace_id=abc123"
        let redacted = PrivacyRedactor.redactEndpointQuery(endpoint)

        XCTAssertTrue(redacted.contains("api_key=%5Bredacted%5D"))
        XCTAssertTrue(redacted.contains("trace_id=%5Bredacted%5D"))
        XCTAssertFalse(redacted.contains("sk-secret"))
        XCTAssertFalse(redacted.contains("abc123"))
    }

    func testPrivacyRedactorRedactsStructuredPayloadAndNestedURL() {
        let payload = """
        {"api_key":"sk-secret-123","endpointURL":"https://example.com/v1?token=abc&mode=test","messages":[{"content":"hello"}]}
        """
        let redacted = PrivacyRedactor.redactStructuredText(payload)

        XCTAssertFalse(redacted.contains("sk-secret-123"))
        XCTAssertFalse(redacted.contains("token=abc"))
        XCTAssertTrue(redacted.contains("[masked len="))
        XCTAssertTrue(redacted.contains("token=%5Bredacted%5D"))
    }

    func testPrivacyRedactorRedactsLooseFormEncodedText() {
        let payload = "model=gpt-4o&api_key=sk-form-secret&refresh_token=rt-secret"
        let redacted = PrivacyRedactor.redactStructuredText(payload)

        XCTAssertFalse(redacted.contains("sk-form-secret"))
        XCTAssertFalse(redacted.contains("rt-secret"))
        XCTAssertTrue(redacted.contains("api_key=[redacted]"))
        XCTAssertTrue(redacted.contains("refresh_token=[redacted]"))
    }

    func testPrivacyRedactorRedactsAuthorizationValueInLooseText() {
        let payload = "authorization=sk-live-super-secret"
        let redacted = PrivacyRedactor.redactStructuredText(payload)

        XCTAssertFalse(redacted.contains("sk-live-super-secret"))
        XCTAssertTrue(redacted.contains("authorization=[redacted]"))
    }

    func testOpenAIRefreshTokenFormBodyUsesStandardURLEncodingForSpecialCharacters() {
        let rawRefreshToken = "rt+/=?:& %"
        guard let bodyData = OpenAIQuotaFetcher.formEncodedRefreshTokenBody(refreshToken: rawRefreshToken),
              let body = String(data: bodyData, encoding: .utf8) else {
            XCTFail("Expected encoded form body")
            return
        }

        XCTAssertTrue(body.hasPrefix("refresh_token="))
        XCTAssertFalse(body.contains(rawRefreshToken))

        var components = URLComponents()
        components.percentEncodedQuery = body
        let decodedRefreshToken = components.queryItems?.first(where: { $0.name == "refresh_token" })?.value
        XCTAssertEqual(decodedRefreshToken, rawRefreshToken)
    }

    @MainActor
    func testSettingsAuditTrailMasksURLSettingsValues() {
        let trail = SettingsAuditTrail.shared
        trail.clear()

        trail.recordChange(
            key: "proxyURL",
            oldValue: "https://alice:secret@example.com/v1?token=abc",
            newValue: "https://alice:secret@example.com/v1?token=next",
            source: "unit-test"
        )

        guard let first = trail.recent(limit: 1).first else {
            XCTFail("Expected one settings audit event")
            return
        }

        XCTAssertFalse(first.oldValue.contains("alice"))
        XCTAssertFalse(first.oldValue.contains("secret"))
        XCTAssertFalse(first.oldValue.contains("token=abc"))
        XCTAssertTrue(first.newValue.contains("token=%5Bredacted%5D"))
    }

    @MainActor
    func testRequestTrackerExportRedactsStoredEndpointPayloadAndResponse() throws {
        let tracker = RequestTracker.shared
        tracker.clearHistory()

        let entry = RequestLog(
            timestamp: Date(timeIntervalSince1970: 1_768_000_000),
            requestId: "req-privacy-1",
            method: "POST",
            endpoint: "/v1/messages?api_key=sk-secret&debug=true",
            provider: "anthropic",
            model: "claude-sonnet-4-5",
            source: "Codex CLI",
            sourceRaw: "codex",
            accountHint: "primary",
            requestPayloadSnippet: #"{"authorization":"Bearer super-secret","endpointURL":"https://api.example.com/v1?token=abc"}"#,
            resolvedModel: nil,
            resolvedProvider: nil,
            inputTokens: nil,
            outputTokens: nil,
            durationMs: 120,
            statusCode: 429,
            requestSize: 512,
            responseSize: 256,
            errorMessage: #"{"error":"quota exceeded","details":{"refresh_token":"rt-secret","retry_url":"https://api.example.com/retry?ticket=123"}}"#
        )
        tracker.addEntry(entry)

        let data = try tracker.exportAuditPackageData()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let package = try decoder.decode(RequestTracker.RequestAuditPackage.self, from: data)

        guard let exported = package.recentRequests.first else {
            XCTFail("Expected one exported request")
            return
        }

        XCTAssertTrue(exported.endpoint.contains("api_key=%5Bredacted%5D"))
        XCTAssertFalse(exported.endpoint.contains("sk-secret"))
        XCTAssertFalse(exported.requestPayloadSnippet?.contains("super-secret") ?? false)
        XCTAssertFalse(exported.errorMessage?.contains("rt-secret") ?? false)
        XCTAssertTrue(exported.errorMessage?.contains("ticket=%5Bredacted%5D") ?? false)
    }

    func testCreateProxiedConfigurationStaticBuildsSocks5ProxyDictionary() {
        UserDefaults.standard.set("socks5://alice:secret@127.0.0.1:1080", forKey: "proxyURL")
        defer { UserDefaults.standard.removeObject(forKey: "proxyURL") }

        let config = ProxyConfigurationService.createProxiedConfigurationStatic(timeout: 9)
        guard let proxy = config.connectionProxyDictionary else {
            XCTFail("Expected SOCKS5 proxy dictionary to be generated")
            return
        }

        XCTAssertEqual(config.timeoutIntervalForRequest, 9)
        XCTAssertEqual(proxy[kCFStreamPropertySOCKSProxyHost] as? String, "127.0.0.1")
        XCTAssertEqual(proxy[kCFStreamPropertySOCKSProxyPort] as? Int, 1080)
        XCTAssertEqual(proxy[kCFStreamPropertySOCKSVersion] as? String, kCFStreamSocketSOCKSVersion5 as String)
        XCTAssertNil(proxy[kCFStreamPropertySOCKSUser], "Sanitizer should strip embedded credentials")
        XCTAssertNil(proxy[kCFStreamPropertySOCKSPassword], "Sanitizer should strip embedded credentials")
    }

    func testCreateProxiedConfigurationStaticRejectsUnsupportedProxyScheme() {
        UserDefaults.standard.set("ftp://proxy.example.com:21", forKey: "proxyURL")
        defer { UserDefaults.standard.removeObject(forKey: "proxyURL") }

        let config = ProxyConfigurationService.createProxiedConfigurationStatic(timeout: 11)
        XCTAssertEqual(config.timeoutIntervalForRequest, 11)
        XCTAssertNil(config.connectionProxyDictionary)
    }

    @MainActor
    func testRequestHistoryStoreTreatsMissingStatusCodeAsFailure() {
        var store = RequestHistoryStore.empty
        store.addEntry(
            RequestLog(
                timestamp: Date(timeIntervalSince1970: 1_768_000_010),
                requestId: "req-fail-nil-status",
                method: "POST",
                endpoint: "/v1/responses",
                provider: "openai",
                model: "gpt-5",
                durationMs: 90,
                statusCode: nil,
                requestSize: 100,
                responseSize: 0,
                errorMessage: "timeout"
            )
        )
        store.addEntry(
            RequestLog(
                timestamp: Date(timeIntervalSince1970: 1_768_000_020),
                requestId: "req-success",
                method: "POST",
                endpoint: "/v1/responses",
                provider: "openai",
                model: "gpt-5",
                durationMs: 110,
                statusCode: 201,
                requestSize: 120,
                responseSize: 240,
                errorMessage: nil
            )
        )

        let stats = store.calculateStats()
        XCTAssertEqual(stats.totalRequests, 2)
        XCTAssertEqual(stats.successfulRequests, 1)
        XCTAssertEqual(stats.failedRequests, 1)
        let openAIRequestCount = stats.byProvider["openai"]?.requestCount
        XCTAssertEqual(openAIRequestCount, 2)
    }

    @MainActor
    func testUpstreamProxyURLSanitizesCredentialsAndRejectsInvalidSocks5WithoutPort() {
        UserDefaults.standard.set("  http://alice:secret@example.com:8080/proxy/  ", forKey: "proxyURL")
        defer { UserDefaults.standard.removeObject(forKey: "proxyURL") }

        XCTAssertEqual(ProxyConfigurationService.shared.upstreamProxyURL, "http://example.com:8080/proxy")

        UserDefaults.standard.set("socks5://127.0.0.1", forKey: "proxyURL")
        XCTAssertNil(ProxyConfigurationService.shared.upstreamProxyURL)

        let config = ProxyConfigurationService.createProxiedConfigurationStatic()
        XCTAssertNil(config.connectionProxyDictionary)
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
