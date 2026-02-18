//
//  ReviewQueueViewModel.swift
//  Quotio
//
//  UI state for automated Codex review queue.
//

import Foundation
import AppKit
import Observation

@MainActor
@Observable
final class ReviewQueueViewModel {
    private let queueService = CodexReviewQueueService.shared
    private let executor = CLIExecutor.shared

    let presets: [ReviewQueuePreset] = ReviewQueuePreset.builtIn
    var selectedPresetId: String = ReviewQueuePreset.builtIn.first?.id ?? ""

    var workspacePath: String = ""
    var workerCount: Int = 3
    var useCustomPrompts: Bool = false
    var sharedReviewPrompt: String = "请进行深度、全面的 Code Review。"
    var customReviewPromptsText: String = ""
    var aggregatePrompt: String = "请帮我 Review 并验证这些问题是否存在，如果存在，完成去重，给我一个最完整的问题清单。"
    var fixPrompt: String = "请全部修复这些问题。"
    var runAggregate: Bool = true
    var runFix: Bool = true
    var model: String = ""
    var fullAuto: Bool = true
    var skipGitRepoCheck: Bool = false
    var ephemeral: Bool = false

    var phase: ReviewQueuePhase = .idle
    var isRunning: Bool = false
    var workers: [ReviewWorkerResult] = []
    var aggregateOutputPath: String?
    var fixOutputPath: String?
    var jobPath: String?
    var errorMessage: String?
    var lastRunSummary: String?
    var historyItems: [ReviewQueueHistoryItem] = []
    var runEvents: [ReviewQueueRunEvent] = []
    var runStartedAt: Date?
    var runFinishedAt: Date?
    var isCancelling: Bool = false
    var isHistoryRefreshing: Bool = false
    var lastHistoryRefreshAt: Date?

    var customPromptCount: Int {
        parsedCustomPrompts().count
    }

    var plannedPromptCount: Int {
        if useCustomPrompts {
            return customPromptCount
        }
        let prompt = sharedReviewPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return 0 }
        return max(1, min(workerCount, ReviewQueueLimits.maxWorkers))
    }

    var plannedConcurrentWorkers: Int {
        guard plannedPromptCount > 0 else { return 0 }
        return min(plannedPromptCount, ReviewQueueLimits.maxWorkers)
    }

    var willQueueInBatches: Bool {
        plannedPromptCount > plannedConcurrentWorkers
    }

    @ObservationIgnored private var runTask: Task<Void, Never>?
    @ObservationIgnored private var historyRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var historyRefreshToken: UUID = UUID()

    func chooseWorkspace() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            workspacePath = url.path
            refreshHistory()
        }
    }

    func startRun() {
        executeRun(withPrompts: resolvedReviewPrompts())
    }

    func rerunFailedWorkers() {
        let failedPrompts = workers
            .filter { $0.status == .failed }
            .map(\.prompt)
        executeRun(withPrompts: failedPrompts)
    }

    func applySelectedPreset() {
        guard let preset = presets.first(where: { $0.id == selectedPresetId }) else { return }
        sharedReviewPrompt = preset.reviewPrompt
        aggregatePrompt = preset.aggregatePrompt
        fixPrompt = preset.fixPrompt
    }

    func refreshHistory() {
        scheduleHistoryRefresh(debounceNanoseconds: 0)
    }

    func scheduleHistoryRefresh() {
        scheduleHistoryRefresh(debounceNanoseconds: 300_000_000)
    }

    private func scheduleHistoryRefresh(debounceNanoseconds: UInt64) {
        historyRefreshTask?.cancel()
        let token = UUID()
        historyRefreshToken = token
        let workspace = workspacePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !workspace.isEmpty else {
            historyItems = []
            historyRefreshTask = nil
            isHistoryRefreshing = false
            return
        }
        isHistoryRefreshing = true

        historyRefreshTask = Task { [weak self] in
            guard let self else { return }
            if debounceNanoseconds > 0 {
                do {
                    try await Task.sleep(nanoseconds: debounceNanoseconds)
                } catch {
                    await MainActor.run {
                        if self.historyRefreshToken == token {
                            self.isHistoryRefreshing = false
                        }
                    }
                    return
                }
            }
            let items = await Task.detached(priority: .utility) {
                Self.loadHistoryItems(workspace: workspace)
            }.value
            if Task.isCancelled {
                await MainActor.run {
                    if self.historyRefreshToken == token {
                        self.isHistoryRefreshing = false
                    }
                }
                return
            }
            await MainActor.run {
                guard self.historyRefreshToken == token else { return }
                guard self.workspacePath.trimmingCharacters(in: .whitespacesAndNewlines) == workspace else {
                    return
                }
                self.historyItems = items
                self.historyRefreshTask = nil
                self.isHistoryRefreshing = false
                self.lastHistoryRefreshAt = Date()
            }
        }
    }

    private func executeRun(withPrompts prompts: [String]) {
        guard !isRunning else { return }
        clearRuntimeState()
        isRunning = true
        isCancelling = false
        runStartedAt = Date()
        runFinishedAt = nil
        phase = .preparing
        appendRunEvent(
            level: .info,
            message: "Queue started. prompts=\(prompts.count), max_concurrency=\(min(prompts.count, ReviewQueueLimits.maxWorkers))"
        )

        guard !prompts.isEmpty else {
            isRunning = false
            phase = .failed
            errorMessage = "请至少提供一条 Review Prompt。"
            runFinishedAt = Date()
            appendRunEvent(level: .error, message: "Queue blocked: empty prompt list.")
            return
        }
        guard !workspacePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            isRunning = false
            phase = .failed
            errorMessage = "请选择工作区目录。"
            runFinishedAt = Date()
            appendRunEvent(level: .error, message: "Queue blocked: workspace is empty.")
            return
        }
        if runFix && !runAggregate {
            isRunning = false
            phase = .failed
            errorMessage = "启用修复前必须先启用汇总阶段。"
            runFinishedAt = Date()
            appendRunEvent(level: .error, message: "Queue blocked: runFix=true while runAggregate=false.")
            return
        }
        if runAggregate && aggregatePrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            isRunning = false
            phase = .failed
            errorMessage = "汇总 Prompt 不能为空。"
            runFinishedAt = Date()
            appendRunEvent(level: .error, message: "Queue blocked: aggregate prompt is empty.")
            return
        }
        if runFix && fixPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            isRunning = false
            phase = .failed
            errorMessage = "修复 Prompt 不能为空。"
            runFinishedAt = Date()
            appendRunEvent(level: .error, message: "Queue blocked: fix prompt is empty.")
            return
        }

        let cfg = ReviewQueueConfig(
            workspacePath: workspacePath.trimmingCharacters(in: .whitespacesAndNewlines),
            reviewPrompts: prompts,
            aggregatePrompt: aggregatePrompt.trimmingCharacters(in: .whitespacesAndNewlines),
            fixPrompt: fixPrompt.trimmingCharacters(in: .whitespacesAndNewlines),
            runAggregate: runAggregate,
            runFix: runFix,
            model: normalizedModel(),
            fullAuto: fullAuto,
            skipGitRepoCheck: skipGitRepoCheck,
            ephemeral: ephemeral
        )

        runTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.queueService.runQueue(config: cfg) { event in
                    Task { @MainActor [weak self] in
                        self?.handle(event: event)
                    }
                }
                await MainActor.run {
                    self.isRunning = false
                    self.runTask = nil
                    self.isCancelling = false
                    self.runFinishedAt = Date()
                    self.phase = .completed
                    self.jobPath = result.jobPath
                    self.aggregateOutputPath = result.aggregateOutputPath
                    self.fixOutputPath = result.fixOutputPath
                    self.lastRunSummary = "Worker: \(result.workers.count) (ok: \(result.completedWorkerCount), failed: \(result.failedWorkerCount)) | Job: \(result.jobId)"
                    self.appendRunEvent(
                        level: .info,
                        message: "Queue completed. completed=\(result.completedWorkerCount), failed=\(result.failedWorkerCount), job=\(result.jobId)"
                    )
                    self.refreshHistory()
                }
            } catch {
                await MainActor.run {
                    self.isRunning = false
                    self.runTask = nil
                    self.isCancelling = false
                    self.runFinishedAt = Date()
                    if case CodexReviewQueueError.cancelled = error {
                        self.phase = .cancelled
                        self.errorMessage = "任务已取消。"
                        self.appendRunEvent(level: .warning, message: "Queue cancelled.")
                    } else if Task.isCancelled {
                        self.phase = .cancelled
                        self.errorMessage = "任务已取消。"
                        self.appendRunEvent(level: .warning, message: "Queue cancelled.")
                    } else {
                        self.phase = .failed
                        self.errorMessage = self.renderError(error)
                        self.appendRunEvent(level: .error, message: "Queue failed: \(self.errorMessage ?? error.localizedDescription)")
                    }
                    self.refreshHistory()
                }
            }
        }
    }

    func cancelRun() {
        guard isRunning else { return }
        isCancelling = true
        appendRunEvent(level: .warning, message: "Cancellation requested by user.")
        runTask?.cancel()
    }

    func checkCodexInstalled() async -> Bool {
        await executor.isCLIInstalled(name: "codex")
    }

    func openPathInFinder(_ path: String?) {
        guard let path, !path.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    private func clearRuntimeState() {
        workers = []
        aggregateOutputPath = nil
        fixOutputPath = nil
        jobPath = nil
        errorMessage = nil
        lastRunSummary = nil
        runEvents = []
    }

    private func resolvedReviewPrompts() -> [String] {
        if useCustomPrompts {
            return parsedCustomPrompts()
        }
        let prompt = sharedReviewPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return [] }
        return Array(repeating: prompt, count: max(1, min(workerCount, ReviewQueueLimits.maxWorkers)))
    }

    private func normalizedModel() -> String? {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private nonisolated static func parseJobDate(_ jobId: String) -> Date? {
        let prefix = jobId.split(separator: "-").prefix(2).joined(separator: "-")
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.date(from: prefix)
    }

    private nonisolated static func loadHistoryItems(workspace: String) -> [ReviewQueueHistoryItem] {
        let base = URL(fileURLWithPath: workspace)
            .appendingPathComponent(".runtime-cache")
            .appendingPathComponent("review-queue")
        guard let directories = try? FileManager.default.contentsOfDirectory(
            at: base,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let items: [ReviewQueueHistoryItem] = directories.compactMap { url in
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory == true else { return nil }

            let jobId = url.lastPathComponent
            let summaryPath = url.appendingPathComponent("summary.json")
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let summary: ReviewQueueJobSummary? = {
                guard let data = try? Data(contentsOf: summaryPath) else { return nil }
                return try? decoder.decode(ReviewQueueJobSummary.self, from: data)
            }()

            let workerCount: Int
            let failedCount: Int
            let model: String?
            let createdAt: Date?
            let phase: ReviewQueuePhase
            let aggregatePath: String?
            let fixPath: String?

            if let summary {
                workerCount = summary.workerCount
                failedCount = summary.failedWorkerCount
                model = summary.model
                createdAt = summary.createdAt
                phase = summary.phase
                aggregatePath = summary.aggregateOutputPath
                fixPath = summary.fixOutputPath
            } else {
                let aggregateFilePath = url.appendingPathComponent("aggregate.md").path
                let fixFilePath = url.appendingPathComponent("fix.md").path
                let aggregateExists = FileManager.default.fileExists(atPath: aggregateFilePath)
                let fixExists = FileManager.default.fileExists(atPath: fixFilePath)
                let allFiles = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
                let workerPaths = allFiles.filter {
                    $0.lastPathComponent.hasPrefix("worker-") && $0.pathExtension == "md"
                }
                workerCount = workerPaths.count
                failedCount = workerPaths.reduce(into: 0) { partialResult, workerPath in
                    let stderrPath = workerPath.deletingPathExtension().appendingPathExtension("stderr.log").path
                    if let stderr = try? String(contentsOfFile: stderrPath, encoding: .utf8),
                       !stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        partialResult += 1
                    }
                }

                let configPath = url.appendingPathComponent("config.json")
                let cfg: ReviewQueueConfig? = {
                    guard let data = try? Data(contentsOf: configPath) else { return nil }
                    return try? JSONDecoder().decode(ReviewQueueConfig.self, from: data)
                }()
                model = cfg?.model
                createdAt = Self.parseJobDate(jobId)
                if fixExists {
                    phase = .completed
                } else if workerCount > 0 && failedCount == workerCount {
                    phase = .failed
                } else if aggregateExists {
                    if cfg?.runAggregate == true && cfg?.runFix == false {
                        phase = .completed
                    } else {
                        phase = .aggregating
                    }
                } else if cfg?.runAggregate == false && cfg?.runFix == false && workerCount > 0 {
                    phase = .completed
                } else {
                    phase = .reviewing
                }
                aggregatePath = aggregateExists ? aggregateFilePath : nil
                fixPath = fixExists ? fixFilePath : nil
            }

            return ReviewQueueHistoryItem(
                id: jobId,
                jobId: jobId,
                jobPath: url.path,
                createdAt: createdAt,
                phase: phase,
                workerCount: workerCount,
                failedWorkerCount: failedCount,
                aggregateOutputPath: aggregatePath.flatMap { FileManager.default.fileExists(atPath: $0) ? $0 : nil },
                fixOutputPath: fixPath.flatMap { FileManager.default.fileExists(atPath: $0) ? $0 : nil },
                model: model
            )
        }

        return items.sorted { lhs, rhs in
            switch (lhs.createdAt, rhs.createdAt) {
            case let (lhsDate?, rhsDate?):
                return lhsDate > rhsDate
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return lhs.jobId > rhs.jobId
            }
        }
    }

    private func parsedCustomPrompts() -> [String] {
        customReviewPromptsText
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func appendRunEvent(level: ReviewQueueRunEventLevel, message: String) {
        let event = ReviewQueueRunEvent(
            id: UUID(),
            timestamp: Date(),
            level: level,
            message: message
        )
        runEvents.append(event)
        let overflow = runEvents.count - ReviewQueueLimits.maxRunEvents
        if overflow > 0 {
            runEvents.removeFirst(overflow)
        }
    }

    private func workerStatusEventMessage(worker: ReviewWorkerResult) -> String {
        switch worker.status {
        case .pending:
            return "Worker \(worker.id) pending."
        case .running:
            return "Worker \(worker.id) started."
        case .completed:
            return "Worker \(worker.id) completed."
        case .failed:
            let details = worker.error?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if details.isEmpty {
                return "Worker \(worker.id) failed."
            }
            return "Worker \(worker.id) failed: \(details)"
        }
    }

    private func handle(event: ReviewQueueEvent) {
        switch event {
        case .phaseChanged(let next):
            if phase != next {
                appendRunEvent(level: .info, message: "Phase -> \(next.rawValue)")
            }
            phase = next
        case .workerUpdated(let worker):
            if let index = workers.firstIndex(where: { $0.id == worker.id }) {
                let previous = workers[index]
                workers[index] = worker
                if previous.status != worker.status {
                    appendRunEvent(level: worker.status == .failed ? .warning : .info, message: workerStatusEventMessage(worker: worker))
                } else if previous.error != worker.error,
                          let error = worker.error,
                          !error.isEmpty {
                    appendRunEvent(level: .warning, message: "Worker \(worker.id) error updated: \(error)")
                }
            } else {
                workers.append(worker)
                workers.sort { $0.id < $1.id }
                appendRunEvent(level: .info, message: workerStatusEventMessage(worker: worker))
            }
        case .aggregateReady(let path):
            aggregateOutputPath = path
            appendRunEvent(level: .info, message: "Aggregate output ready: \(path)")
        case .fixReady(let path):
            fixOutputPath = path
            appendRunEvent(level: .info, message: "Fix output ready: \(path)")
        case .failed(let message):
            phase = .failed
            errorMessage = message
            appendRunEvent(level: .error, message: "Queue failure event: \(message)")
        }
    }

    private func renderError(_ error: Error) -> String {
        if let queueError = error as? CodexReviewQueueError {
            switch queueError {
            case .invalidWorkspace:
                return "工作区路径无效。"
            case .codexNotInstalled:
                return "未检测到 Codex CLI。"
            case .emptyPrompts:
                return "Review Prompt 为空。"
            case .invalidStageConfiguration:
                return "阶段配置无效：请先汇总再修复。"
            case .cancelled:
                return "任务已取消。"
            case .executionFailed(let output):
                return output.isEmpty ? "Codex 执行失败。" : output
            }
        }
        return error.localizedDescription
    }
}
