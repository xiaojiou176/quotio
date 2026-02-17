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

    @ObservationIgnored private var runTask: Task<Void, Never>?

    func chooseWorkspace() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            workspacePath = url.path
        }
    }

    func startRun() {
        guard !isRunning else { return }
        clearRuntimeState()
        isRunning = true
        phase = .preparing

        let prompts = resolvedReviewPrompts()
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
