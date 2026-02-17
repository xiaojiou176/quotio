//
//  CodexReviewQueueService.swift
//  Quotio
//
//  Orchestrates multi-session Codex review + aggregate + fix pipeline.
//

import Foundation

enum CodexReviewQueueError: Error {
    case invalidWorkspace
    case codexNotInstalled
    case emptyPrompts
    case invalidStageConfiguration
    case cancelled
    case executionFailed(String)
}

actor CodexReviewQueueService {
    static let shared = CodexReviewQueueService()

    private let executor = CLIExecutor.shared

    private init() {}

    func runQueue(
        config: ReviewQueueConfig,
        onEvent: @escaping @Sendable (ReviewQueueEvent) -> Void
    ) async throws -> ReviewQueueResult {
        guard FileManager.default.fileExists(atPath: config.workspacePath) else {
            throw CodexReviewQueueError.invalidWorkspace
        }
        guard await executor.isCLIInstalled(name: "codex") else {
            throw CodexReviewQueueError.codexNotInstalled
        }

        let prompts = config.reviewPrompts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !prompts.isEmpty else {
            throw CodexReviewQueueError.emptyPrompts
        }

        onEvent(.phaseChanged(.preparing))
        let jobId = Self.makeJobID()
        let jobURL = try prepareJobDirectory(workspacePath: config.workspacePath, jobId: jobId, config: config)

        if Task.isCancelled { throw CodexReviewQueueError.cancelled }

        onEvent(.phaseChanged(.reviewing))
        var workers: [ReviewWorkerResult] = []
        for index in prompts.indices {
            workers.append(
                ReviewWorkerResult(
                    id: index + 1,
                    prompt: prompts[index],
                    status: .pending,
                    outputPath: nil,
                    stdoutPath: nil,
                    stderrPath: nil,
                    error: nil
                )
            )
        }
        workers.forEach { onEvent(.workerUpdated($0)) }

        workers = try await runReviewWorkers(
            prompts: prompts,
            workspacePath: config.workspacePath,
            jobURL: jobURL,
            config: config,
            onEvent: onEvent
        )

        if Task.isCancelled { throw CodexReviewQueueError.cancelled }

        let completedWorkers = workers.filter { $0.status == .completed }.count
        let failedWorkers = workers.filter { $0.status == .failed }.count
        if completedWorkers == 0 && (config.runAggregate || config.runFix) {
            let failures = workers
                .compactMap { worker in
                    guard let error = worker.error, !error.isEmpty else { return nil }
                    return "Worker \(worker.id): \(error)"
                }
                .joined(separator: "\n")
            let message = failures.isEmpty ? "All review workers failed." : "All review workers failed:\n\(failures)"
            throw CodexReviewQueueError.executionFailed(message)
        }

        var aggregateOutputURL: URL?
        if config.runAggregate {
            onEvent(.phaseChanged(.aggregating))
            let path = jobURL.appendingPathComponent("aggregate.md")
            try await runAggregateStage(
                workers: workers,
                config: config,
                workspacePath: config.workspacePath,
                outputPath: path.path
            )
            onEvent(.aggregateReady(path: path.path))
            aggregateOutputURL = path
        }

        if Task.isCancelled { throw CodexReviewQueueError.cancelled }

        var fixOutputURL: URL?
        if config.runFix {
            guard config.runAggregate, let aggregateOutputURL else {
                throw CodexReviewQueueError.invalidStageConfiguration
            }
            onEvent(.phaseChanged(.fixing))
            let path = jobURL.appendingPathComponent("fix.md")
            try await runFixStage(
                aggregateOutputPath: aggregateOutputURL.path,
                config: config,
                workspacePath: config.workspacePath,
                outputPath: path.path
            )
            onEvent(.fixReady(path: path.path))
            fixOutputURL = path
        }

        onEvent(.phaseChanged(.completed))
        return ReviewQueueResult(
            jobId: jobId,
            jobPath: jobURL.path,
            workers: workers,
            aggregateOutputPath: aggregateOutputURL?.path,
            fixOutputPath: fixOutputURL?.path,
            completedWorkerCount: completedWorkers,
            failedWorkerCount: failedWorkers
        )
    }

    private func runReviewWorkers(
        prompts: [String],
        workspacePath: String,
        jobURL: URL,
        config: ReviewQueueConfig,
        onEvent: @escaping @Sendable (ReviewQueueEvent) -> Void
    ) async throws -> [ReviewWorkerResult] {
        try await withThrowingTaskGroup(of: (Int, ReviewWorkerResult).self) { group in
            for index in prompts.indices {
                let prompt = prompts[index]
                group.addTask { [self] in
                    let workerId = index + 1
                    var state = ReviewWorkerResult(
                        id: workerId,
                        prompt: prompt,
                        status: .running,
                        outputPath: nil,
                        stdoutPath: nil,
                        stderrPath: nil,
                        error: nil
                    )
                    onEvent(.workerUpdated(state))
                    let result = await self.executeReviewWorker(
                        workerId: workerId,
                        prompt: prompt,
                        workspacePath: workspacePath,
                        jobURL: jobURL,
                        config: config
                    )
                    state = result
                    onEvent(.workerUpdated(state))
                    return (index, state)
                }
            }

            var ordered = Array(
                repeating: ReviewWorkerResult(
                    id: 0,
                    prompt: "",
                    status: .pending,
                    outputPath: nil,
                    stdoutPath: nil,
                    stderrPath: nil,
                    error: nil
                ),
                count: prompts.count
            )
            for try await (index, worker) in group {
                ordered[index] = worker
            }
            return ordered
        }
    }

    private func executeReviewWorker(
        workerId: Int,
        prompt: String,
        workspacePath: String,
        jobURL: URL,
        config: ReviewQueueConfig
    ) async -> ReviewWorkerResult {
        let outputPath = jobURL.appendingPathComponent(String(format: "worker-%02d.md", workerId)).path
        let stdoutPath = jobURL.appendingPathComponent(String(format: "worker-%02d.stdout.log", workerId)).path
        let stderrPath = jobURL.appendingPathComponent(String(format: "worker-%02d.stderr.log", workerId)).path

        var arguments = baseExecArguments(config: config)
        arguments.append("review")
        arguments.append("--json")
        arguments.append("--output-last-message")
        arguments.append(outputPath)
        arguments.append("-")

        let result = await executor.executeCLIWithInput(
            name: "codex",
            arguments: arguments,
            input: prompt,
            workingDirectory: workspacePath,
            timeout: 60 * 20
        )

        try? result.output.write(toFile: stdoutPath, atomically: true, encoding: .utf8)
        try? result.errorOutput.write(toFile: stderrPath, atomically: true, encoding: .utf8)

        if !FileManager.default.fileExists(atPath: outputPath) {
            let fallback = parseLastAgentMessage(from: result.output) ?? result.combinedOutput
            try? fallback.write(toFile: outputPath, atomically: true, encoding: .utf8)
        }

        if result.success {
            return ReviewWorkerResult(
                id: workerId,
                prompt: prompt,
                status: .completed,
                outputPath: outputPath,
                stdoutPath: stdoutPath,
                stderrPath: stderrPath,
                error: nil
            )
        }

        let errorMessage = result.errorOutput.isEmpty ? result.output : result.errorOutput
        return ReviewWorkerResult(
            id: workerId,
            prompt: prompt,
            status: .failed,
            outputPath: outputPath,
            stdoutPath: stdoutPath,
            stderrPath: stderrPath,
            error: errorMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func runAggregateStage(
        workers: [ReviewWorkerResult],
        config: ReviewQueueConfig,
        workspacePath: String,
        outputPath: String
    ) async throws {
        let workerSections = workers.map { worker in
            let body: String
            if let outputPath = worker.outputPath,
               let content = try? String(contentsOfFile: outputPath, encoding: .utf8) {
                body = content
            } else if let error = worker.error {
                body = "ERROR: \(error)"
            } else {
                body = "No output captured."
            }
            return """
            ## Worker \(worker.id) (\(worker.status.rawValue))
            Prompt:
            \(worker.prompt)

            Output:
            \(body)
            """
        }.joined(separator: "\n\n")

        let aggregateInput = """
        \(config.aggregatePrompt)

        Please validate, deduplicate, and provide one complete issue list.

        \(workerSections)
        """

        var arguments = baseExecArguments(config: config)
        arguments.append("--json")
        arguments.append("--output-last-message")
        arguments.append(outputPath)
        arguments.append("-")

        let result = await executor.executeCLIWithInput(
            name: "codex",
            arguments: arguments,
            input: aggregateInput,
            workingDirectory: workspacePath,
            timeout: 60 * 30
        )
        if !result.success {
            throw CodexReviewQueueError.executionFailed(result.combinedOutput)
        }
    }

    private func runFixStage(
        aggregateOutputPath: String,
        config: ReviewQueueConfig,
        workspacePath: String,
        outputPath: String
    ) async throws {
        let aggregate = (try? String(contentsOfFile: aggregateOutputPath, encoding: .utf8)) ?? ""
        let fixInput = """
        \(config.fixPrompt)

        Use this validated issue list as the source of truth:
        \(aggregate)
        """

        var arguments = baseExecArguments(config: config)
        arguments.append("--json")
        arguments.append("--output-last-message")
        arguments.append(outputPath)
        arguments.append("-")

        let result = await executor.executeCLIWithInput(
            name: "codex",
            arguments: arguments,
            input: fixInput,
            workingDirectory: workspacePath,
            timeout: 60 * 45
        )
        if !result.success {
            throw CodexReviewQueueError.executionFailed(result.combinedOutput)
        }
    }

    private func baseExecArguments(config: ReviewQueueConfig) -> [String] {
        var arguments = ["exec"]
        if let model = config.model?.trimmingCharacters(in: .whitespacesAndNewlines), !model.isEmpty {
            arguments.append("--model")
            arguments.append(model)
        }
        if config.fullAuto {
            arguments.append("--full-auto")
        }
        if config.skipGitRepoCheck {
            arguments.append("--skip-git-repo-check")
        }
        if config.ephemeral {
            arguments.append("--ephemeral")
        }
        return arguments
    }

    private func prepareJobDirectory(
        workspacePath: String,
        jobId: String,
        config: ReviewQueueConfig
    ) throws -> URL {
        let base = URL(fileURLWithPath: workspacePath)
            .appendingPathComponent(".runtime-cache")
            .appendingPathComponent("review-queue")
            .appendingPathComponent(jobId)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true, attributes: nil)

        let configURL = base.appendingPathComponent("config.json")
        let encoded = try JSONEncoder().encode(config)
        try encoded.write(to: configURL)
        return base
    }

    private func parseLastAgentMessage(from output: String) -> String? {
        let lines = output.split(separator: "\n")
        var lastMessage: String?
        for line in lines {
            guard line.first == "{",
                  let data = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = object["type"] as? String,
                  type == "item.completed",
                  let item = object["item"] as? [String: Any],
                  let itemType = item["type"] as? String,
                  itemType == "agent_message",
                  let text = item["text"] as? String else {
                continue
            }
            lastMessage = text
        }
        return lastMessage
    }

    private static func makeJobID() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "\(formatter.string(from: Date()))-\(String(UUID().uuidString.prefix(8)).lowercased())"
    }
}
