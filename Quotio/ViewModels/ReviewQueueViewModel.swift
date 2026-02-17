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

    @ObservationIgnored private var runTask: Task<Void, Never>?

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
        let workspace = workspacePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !workspace.isEmpty else {
            historyItems = []
            return
        }
        let base = URL(fileURLWithPath: workspace)
            .appendingPathComponent(".runtime-cache")
            .appendingPathComponent("review-queue")
        guard let directories = try? FileManager.default.contentsOfDirectory(
            at: base,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            historyItems = []
            return
        }

        let items: [ReviewQueueHistoryItem] = directories.compactMap { url in
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory == true else { return nil }

            let jobId = url.lastPathComponent
            let summaryPath = url.appendingPathComponent("summary.json").path
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let summary: ReviewQueueJobSummary? = {
                guard let data = try? Data(contentsOf: URL(fileURLWithPath: summaryPath)) else { return nil }
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
                let allFiles = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
                let workerPaths = (allFiles ?? []).filter {
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

                let configPath = url.appendingPathComponent("config.json").path
                if let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
                   let cfg = try? JSONDecoder().decode(ReviewQueueConfig.self, from: data) {
                    model = cfg.model
                } else {
                    model = nil
                }
                createdAt = parseJobDate(jobId)
                if FileManager.default.fileExists(atPath: fixFilePath) {
                    phase = .completed
                } else if workerCount > 0 && failedCount == workerCount {
                    phase = .failed
                } else if FileManager.default.fileExists(atPath: aggregateFilePath) {
                    phase = .aggregating
                } else {
                    phase = .reviewing
                }
                aggregatePath = FileManager.default.fileExists(atPath: aggregateFilePath) ? aggregateFilePath : nil
                fixPath = FileManager.default.fileExists(atPath: fixFilePath) ? fixFilePath : nil
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

        historyItems = items.sorted {
            switch ($0.createdAt, $1.createdAt) {
            case let (lhs?, rhs?):
                return lhs > rhs
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return $0.jobId > $1.jobId
            }
        }
    }

    private func executeRun(withPrompts prompts: [String]) {
        guard !isRunning else { return }
        clearRuntimeState()
        isRunning = true
        phase = .preparing

        guard !prompts.isEmpty else {
            isRunning = false
            phase = .failed
            errorMessage = "请至少提供一条 Review Prompt。"
            return
        }
        guard !workspacePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            isRunning = false
            phase = .failed
            errorMessage = "请选择工作区目录。"
            return
        }
        if runFix && !runAggregate {
            isRunning = false
            phase = .failed
            errorMessage = "启用修复前必须先启用汇总阶段。"
            return
        }
        if runAggregate && aggregatePrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            isRunning = false
            phase = .failed
            errorMessage = "汇总 Prompt 不能为空。"
            return
        }
        if runFix && fixPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            isRunning = false
            phase = .failed
            errorMessage = "修复 Prompt 不能为空。"
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
                    self.phase = .completed
                    self.jobPath = result.jobPath
                    self.aggregateOutputPath = result.aggregateOutputPath
                    self.fixOutputPath = result.fixOutputPath
                    self.lastRunSummary = "Worker: \(result.workers.count) (ok: \(result.completedWorkerCount), failed: \(result.failedWorkerCount)) | Job: \(result.jobId)"
                    self.refreshHistory()
                }
            } catch {
                await MainActor.run {
                    self.isRunning = false
                    self.runTask = nil
                    if case CodexReviewQueueError.cancelled = error {
                        self.phase = .cancelled
                        self.errorMessage = "任务已取消。"
                    } else if Task.isCancelled {
                        self.phase = .cancelled
                        self.errorMessage = "任务已取消。"
                    } else {
                        self.phase = .failed
                        self.errorMessage = self.renderError(error)
                    }
                    self.refreshHistory()
                }
            }
        }
    }

    func cancelRun() {
        runTask?.cancel()
        runTask = nil
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
    }

    private func resolvedReviewPrompts() -> [String] {
        if useCustomPrompts {
            return customReviewPromptsText
                .split(separator: "\n")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        let prompt = sharedReviewPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return [] }
        return Array(repeating: prompt, count: max(1, workerCount))
    }

    private func normalizedModel() -> String? {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func parseJobDate(_ jobId: String) -> Date? {
        let prefix = jobId.split(separator: "-").prefix(2).joined(separator: "-")
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.date(from: prefix)
    }

    private func handle(event: ReviewQueueEvent) {
        switch event {
        case .phaseChanged(let next):
            phase = next
        case .workerUpdated(let worker):
            if let index = workers.firstIndex(where: { $0.id == worker.id }) {
                workers[index] = worker
            } else {
                workers.append(worker)
                workers.sort { $0.id < $1.id }
            }
        case .aggregateReady(let path):
            aggregateOutputPath = path
        case .fixReady(let path):
            fixOutputPath = path
        case .failed(let message):
            phase = .failed
            errorMessage = message
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
