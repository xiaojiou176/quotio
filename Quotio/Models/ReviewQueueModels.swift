//
//  ReviewQueueModels.swift
//  Quotio
//
//  Models for automated multi-session Codex review queue.
//

import Foundation

nonisolated enum ReviewQueuePhase: String, Codable, Sendable {
    case idle
    case preparing
    case reviewing
    case aggregating
    case fixing
    case completed
    case failed
    case cancelled
}

nonisolated enum ReviewWorkerStatus: String, Codable, Sendable {
    case pending
    case running
    case completed
    case failed
}

nonisolated struct ReviewWorkerResult: Codable, Identifiable, Sendable {
    let id: Int
    let prompt: String
    var status: ReviewWorkerStatus
    var outputPath: String?
    var stdoutPath: String?
    var stderrPath: String?
    var error: String?
}

nonisolated struct ReviewQueueConfig: Codable, Sendable {
    var workspacePath: String
    var reviewPrompts: [String]
    var aggregatePrompt: String
    var fixPrompt: String
    var runAggregate: Bool
    var runFix: Bool
    var model: String?
    var fullAuto: Bool
    var skipGitRepoCheck: Bool
    var ephemeral: Bool

    init(
        workspacePath: String,
        reviewPrompts: [String],
        aggregatePrompt: String,
        fixPrompt: String,
        runAggregate: Bool = true,
        runFix: Bool = true,
        model: String? = nil,
        fullAuto: Bool = true,
        skipGitRepoCheck: Bool = false,
        ephemeral: Bool = false
    ) {
        self.workspacePath = workspacePath
        self.reviewPrompts = reviewPrompts
        self.aggregatePrompt = aggregatePrompt
        self.fixPrompt = fixPrompt
        self.runAggregate = runAggregate
        self.runFix = runFix
        self.model = model
        self.fullAuto = fullAuto
        self.skipGitRepoCheck = skipGitRepoCheck
        self.ephemeral = ephemeral
    }
}

nonisolated enum ReviewQueueEvent: Sendable {
    case phaseChanged(ReviewQueuePhase)
    case workerUpdated(ReviewWorkerResult)
    case aggregateReady(path: String)
    case fixReady(path: String)
    case failed(message: String)
}

nonisolated struct ReviewQueueResult: Sendable {
    let jobId: String
    let jobPath: String
    let workers: [ReviewWorkerResult]
    let aggregateOutputPath: String?
    let fixOutputPath: String?
    let completedWorkerCount: Int
    let failedWorkerCount: Int
}

nonisolated struct ReviewQueuePreset: Identifiable, Sendable {
    let id: String
    let name: String
    let reviewPrompt: String
    let aggregatePrompt: String
    let fixPrompt: String

    static let builtIn: [ReviewQueuePreset] = [
        ReviewQueuePreset(
            id: "deep-comprehensive",
            name: "深度全面审查",
            reviewPrompt: "请进行深度、全面的 Code Review。重点覆盖正确性、并发安全、边界条件、错误处理、回归风险与测试缺口。",
            aggregatePrompt: "请帮我 Review 并验证这些问题是否存在，如果存在，完成去重，按严重度排序，给我一个最完整的问题清单。",
            fixPrompt: "请全部修复这些问题，并补齐必要测试。先修高风险问题，再修中低风险问题。"
        ),
        ReviewQueuePreset(
            id: "security-focused",
            name: "安全专项审查",
            reviewPrompt: "请以安全审计模式进行 Code Review。重点检查鉴权/授权、输入校验、命令执行、敏感信息泄露、依赖风险与供应链安全。",
            aggregatePrompt: "请验证并去重所有安全问题，按影响面和可利用性排序，给出最终安全问题清单。",
            fixPrompt: "请修复所有已验证的安全问题，优先修复高危项，并确保不引入行为回归。"
        ),
        ReviewQueuePreset(
            id: "performance-stability",
            name: "性能稳定性审查",
            reviewPrompt: "请重点审查性能与稳定性。覆盖热点路径、并发瓶颈、内存/资源泄漏、阻塞调用、超时与重试策略。",
            aggregatePrompt: "请验证并去重性能与稳定性问题，按收益/成本排序，形成最终问题清单。",
            fixPrompt: "请优先修复高收益性能与稳定性问题，并保持现有功能行为一致。"
        )
    ]
}

nonisolated struct ReviewQueueHistoryItem: Identifiable, Sendable {
    let id: String
    let jobId: String
    let jobPath: String
    let createdAt: Date?
    let phase: ReviewQueuePhase
    let workerCount: Int
    let failedWorkerCount: Int
    let aggregateOutputPath: String?
    let fixOutputPath: String?
    let model: String?
}

nonisolated struct ReviewQueueJobSummary: Codable, Sendable {
    let version: Int
    let jobId: String
    let jobPath: String
    let phase: ReviewQueuePhase
    let createdAt: Date
    let updatedAt: Date
    let workerCount: Int
    let completedWorkerCount: Int
    let failedWorkerCount: Int
    let workers: [ReviewWorkerResult]
    let aggregateOutputPath: String?
    let fixOutputPath: String?
    let runAggregate: Bool
    let runFix: Bool
    let model: String?
}
