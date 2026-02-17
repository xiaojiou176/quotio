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
