//
//  ReviewQueueScreen.swift
//  Quotio
//
//  Automated multi-session review queue UI.
//

import SwiftUI

struct ReviewQueueScreen: View {
    @Environment(QuotaViewModel.self) private var quotaViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var codexInstalled: Bool?
    @State private var startFeedbackState: ActionFeedbackState = .idle
    @State private var rerunFeedbackState: ActionFeedbackState = .idle
    @State private var cancelFeedbackState: ActionFeedbackState = .idle
    @State private var historyRefreshFeedbackState: ActionFeedbackState = .idle

    private enum ActionFeedbackState: Equatable {
        case idle
        case busy
        case success
        case failure
    }

    private enum FeedbackChannel {
        case start
        case rerun
        case cancel
        case historyRefresh
    }

    private var viewModel: ReviewQueueViewModel {
        quotaViewModel.reviewQueueViewModel
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerCard
                workspaceCard
                promptCard
                executionCard
                progressCard
                observabilityCard
                outputCard
                historyCard
            }
            .padding(20)
        }
        .navigationTitle("nav.reviewQueue".localized(fallback: "Review Queue"))
        .task {
            codexInstalled = await viewModel.checkCodexInstalled()
            viewModel.refreshHistory()
        }
        .onChange(of: viewModel.isHistoryRefreshing) { _, isRefreshing in
            if isRefreshing {
                historyRefreshFeedbackState = .busy
            } else if historyRefreshFeedbackState == .busy {
                historyRefreshFeedbackState = latestErrorMessage == nil ? .success : .failure
                scheduleFeedbackReset(.historyRefresh)
            }
        }
        .onChange(of: viewModel.isRunning) { _, isRunning in
            if isRunning {
                if startFeedbackState == .busy {
                    startFeedbackState = .success
                    scheduleFeedbackReset(.start)
                }
                if rerunFeedbackState == .busy {
                    rerunFeedbackState = .success
                    scheduleFeedbackReset(.rerun)
                }
                if cancelFeedbackState == .busy {
                    cancelFeedbackState = .idle
                }
            } else if cancelFeedbackState == .busy {
                cancelFeedbackState = latestErrorMessage == nil ? .success : .failure
                scheduleFeedbackReset(.cancel)
            }
        }
        .onChange(of: viewModel.isCancelling) { _, isCancelling in
            if isCancelling {
                cancelFeedbackState = .busy
            }
        }
        .onChange(of: latestErrorMessage) { _, newValue in
            guard newValue != nil else { return }
            if startFeedbackState == .busy {
                startFeedbackState = .failure
                scheduleFeedbackReset(.start)
            }
            if rerunFeedbackState == .busy {
                rerunFeedbackState = .failure
                scheduleFeedbackReset(.rerun)
            }
            if cancelFeedbackState == .busy {
                cancelFeedbackState = .failure
                scheduleFeedbackReset(.cancel)
            }
            if historyRefreshFeedbackState == .busy {
                historyRefreshFeedbackState = .failure
                scheduleFeedbackReset(.historyRefresh)
            }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("queue.title".localized(fallback: "全自动 Review + 修复"), systemImage: "checklist")
                    .font(.headline)
                Spacer()
                statusBadge
            }
            Text("queue.subtitle".localized(fallback: "并发多个 Codex Session，自动汇总去重并触发修复。"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let codexInstalled {
                if codexInstalled {
                    Label("queue.codex.ready".localized(fallback: "Codex CLI 可用"), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Color.semanticSuccess)
                } else {
                    Label("queue.codex.missing".localized(fallback: "未检测到 Codex CLI"), systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.semanticDanger)
                }
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var workspaceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("queue.workspace".localized(fallback: "工作区"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                TextField("queue.workspace.placeholder".localized(fallback: "选择任意工作区目录"), text: Binding(
                    get: { viewModel.workspacePath },
                    set: {
                        viewModel.workspacePath = $0
                        viewModel.scheduleHistoryRefresh()
                    }
                ))
                .textFieldStyle(.roundedBorder)

                Button("action.browse".localized(fallback: "浏览")) {
                    viewModel.chooseWorkspace()
                }
                .buttonStyle(.bordered)
                Button("queue.history.refresh".localized()) {
                    historyRefreshFeedbackState = .busy
                    viewModel.refreshHistory()
                }
                .buttonStyle(.subtle)
                .overlay(alignment: .trailing) {
                    actionFeedbackIcon(
                        baseSystemImage: "arrow.clockwise",
                        state: historyRefreshFeedbackState
                    )
                    .padding(.trailing, 8)
                }
            }
            HStack(spacing: 8) {
                if viewModel.isHistoryRefreshing {
                    ProgressView()
                        .controlSize(.small)
                    Text("queue.history.refreshing".localized(fallback: "历史刷新中..."))
                } else {
                    let lastRefreshLabel = formatTime(viewModel.lastHistoryRefreshAt)
                    Text("queue.history.lastRefresh".localizedFormat(fallback: "最近刷新: %@", lastRefreshLabel))
                }
                Spacer()
                Text("queue.concurrency.cap".localizedFormat(fallback: "并发上限: %d", ReviewQueueLimits.maxWorkers))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var promptCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Picker("queue.preset".localized(fallback: "Prompt 模板"), selection: Binding(
                    get: { viewModel.selectedPresetId },
                    set: { viewModel.selectedPresetId = $0 }
                )) {
                    ForEach(viewModel.presets) { preset in
                        Text(preset.name).tag(preset.id)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 220)

                Button("queue.preset.apply".localized(fallback: "应用模板")) {
                    viewModel.applySelectedPreset()
                }
                .buttonStyle(.bordered)
            }

            Toggle("queue.prompt.custom".localized(fallback: "使用自定义 Prompt 列表（每行一个 Worker）"), isOn: Binding(
                get: { viewModel.useCustomPrompts },
                set: { viewModel.useCustomPrompts = $0 }
            ))

            if viewModel.useCustomPrompts {
                TextEditor(text: Binding(
                    get: { viewModel.customReviewPromptsText },
                    set: { viewModel.customReviewPromptsText = $0 }
                ))
                .frame(minHeight: 100)
                .font(.system(.body, design: .monospaced))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))
                .accessibilityLabel("queue.prompt.custom".localized(fallback: "自定义 Prompt 列表"))
                Text(
                    "queue.prompt.plan".localizedFormat(
                        fallback: "Prompt: %d | 最大并发: %d",
                        viewModel.plannedPromptCount,
                        viewModel.plannedConcurrentWorkers
                    )
                )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if viewModel.willQueueInBatches {
                    Label(
                        "queue.prompt.batchHint".localized(fallback: "Prompt 数超过并发上限，任务将自动分批执行。"),
                        systemImage: "info.circle"
                    )
                    .font(.caption2)
                    .foregroundStyle(Color.semanticInfo)
                }
            } else {
                Stepper(
                    "queue.prompt.workers".localized(fallback: "并发 Worker 数") + ": \(viewModel.workerCount)",
                    value: Binding(
                        get: { viewModel.workerCount },
                        set: { viewModel.workerCount = $0 }
                    ),
                    in: 1...ReviewQueueLimits.maxWorkers
                )

                TextEditor(text: Binding(
                    get: { viewModel.sharedReviewPrompt },
                    set: { viewModel.sharedReviewPrompt = $0 }
                ))
                .frame(minHeight: 90)
                .font(.system(.body, design: .monospaced))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))
                .accessibilityLabel("queue.prompt.shared".localized(fallback: "共享 Review Prompt"))
            }

            Text("queue.aggregatePrompt".localized(fallback: "汇总去重 Prompt"))
                .font(.caption)
                .foregroundStyle(.secondary)
            if viewModel.runAggregate {
                TextEditor(text: Binding(
                    get: { viewModel.aggregatePrompt },
                    set: { viewModel.aggregatePrompt = $0 }
                ))
                .frame(minHeight: 90)
                .font(.system(.body, design: .monospaced))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))
                .accessibilityLabel("queue.aggregatePrompt".localized(fallback: "汇总去重 Prompt"))
            } else {
                Text("queue.aggregatePrompt.disabled".localized(fallback: "已关闭汇总阶段。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("queue.fixPrompt".localized(fallback: "修复 Prompt"))
                .font(.caption)
                .foregroundStyle(.secondary)
            if viewModel.runFix {
                TextEditor(text: Binding(
                    get: { viewModel.fixPrompt },
                    set: { viewModel.fixPrompt = $0 }
                ))
                .frame(minHeight: 90)
                .font(.system(.body, design: .monospaced))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))
                .accessibilityLabel("queue.fixPrompt".localized(fallback: "修复 Prompt"))
            } else {
                Text("queue.fixPrompt.disabled".localized(fallback: "已关闭修复阶段。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var executionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("queue.model.optional".localized(fallback: "模型（可选，如 gpt-5.3-codex）"), text: Binding(
                    get: { viewModel.model },
                    set: { viewModel.model = $0 }
                ))
                .textFieldStyle(.roundedBorder)
            }
            HStack(spacing: 16) {
                Toggle("queue.runAggregate".localized(fallback: "执行汇总去重"), isOn: Binding(
                    get: { viewModel.runAggregate },
                    set: { viewModel.runAggregate = $0 }
                ))
                .onChange(of: viewModel.runAggregate) { _, isOn in
                    if !isOn {
                        viewModel.runFix = false
                    }
                }
                Toggle("queue.runFix".localized(fallback: "执行修复阶段"), isOn: Binding(
                    get: { viewModel.runFix },
                    set: { viewModel.runFix = $0 }
                ))
                .disabled(!viewModel.runAggregate)
                Toggle("queue.fullAuto".localized(fallback: "Full Auto"), isOn: Binding(
                    get: { viewModel.fullAuto },
                    set: { viewModel.fullAuto = $0 }
                ))
                Toggle("queue.skipGitCheck".localized(fallback: "跳过 Git 仓库检查"), isOn: Binding(
                    get: { viewModel.skipGitRepoCheck },
                    set: { viewModel.skipGitRepoCheck = $0 }
                ))
                Toggle("queue.ephemeral".localized(fallback: "Ephemeral 会话"), isOn: Binding(
                    get: { viewModel.ephemeral },
                    set: { viewModel.ephemeral = $0 }
                ))
            }
            Text(
                "queue.execution.plan".localizedFormat(
                    fallback: "计划执行 Prompt: %d | 最大并发: %d",
                    viewModel.plannedPromptCount,
                    viewModel.plannedConcurrentWorkers
                )
            )
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button(viewModel.isRunning ? "queue.running".localized(fallback: "运行中...") : "queue.start".localized(fallback: "启动 Queue")) {
                    startFeedbackState = .busy
                    viewModel.startRun()
                }
                .buttonStyle(.borderedProminent)
                .disabled(startDisabled)
                .overlay(alignment: .trailing) {
                    actionFeedbackIcon(
                        baseSystemImage: "play.fill",
                        state: startFeedbackState
                    )
                    .padding(.trailing, 8)
                }
                .motionAwareAnimation(QuotioMotion.contentSwap, value: startFeedbackState)

                Button("queue.rerunFailed".localized(fallback: "仅重跑失败项")) {
                    rerunFeedbackState = .busy
                    viewModel.rerunFailedWorkers()
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isRunning || failedWorkerCount == 0)
                .overlay(alignment: .trailing) {
                    actionFeedbackIcon(
                        baseSystemImage: "arrow.triangle.2.circlepath",
                        state: rerunFeedbackState
                    )
                    .padding(.trailing, 8)
                }
                .motionAwareAnimation(QuotioMotion.contentSwap, value: rerunFeedbackState)

                Button(viewModel.isCancelling ? "queue.cancelling".localized(fallback: "取消中...") : "action.cancel".localized(fallback: "取消")) {
                    cancelFeedbackState = .busy
                    viewModel.cancelRun()
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.isRunning)
                .overlay(alignment: .trailing) {
                    actionFeedbackIcon(
                        baseSystemImage: "xmark.circle",
                        state: cancelFeedbackState
                    )
                    .padding(.trailing, 8)
                }
                .motionAwareAnimation(QuotioMotion.contentSwap, value: cancelFeedbackState)
            }
            if let message = viewModel.errorMessage, !message.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(Color.semanticDanger)
                    .textSelection(.enabled)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("queue.history".localized())
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if viewModel.historyItems.isEmpty {
                Text("queue.history.empty".localized())
                    .foregroundStyle(.secondary)
                    .font(.caption)
            } else {
                ForEach(viewModel.historyItems.prefix(10)) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(historyTitle(item))
                                .font(.caption.weight(.semibold))
                            historyPhaseBadge(item.phase)
                        }
                        Text(
                            "queue.history.statusLine".localizedFormat(
                                fallback: "Worker 数: %d | 失败: %d | 模型: %@",
                                item.workerCount,
                                item.failedWorkerCount,
                                item.model ?? "-"
                            )
                        )
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            Button("queue.outputs.openJob".localized()) {
                                viewModel.openPathInFinder(item.jobPath)
                            }
                            .buttonStyle(.borderless)
                            if let path = item.aggregateOutputPath {
                                Button("queue.outputs.openAggregate".localized()) {
                                    viewModel.openPathInFinder(path)
                                }
                                .buttonStyle(.borderless)
                            }
                            if let path = item.fixOutputPath {
                                Button("queue.outputs.openFix".localized()) {
                                    viewModel.openPathInFinder(path)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("queue.progress".localized(fallback: "进度"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if viewModel.workers.isEmpty {
                Text("queue.progress.empty".localized(fallback: "尚未开始任务。"))
                    .foregroundStyle(.secondary)
                    .font(.caption)
            } else {
                ProgressView(value: Double(finishedWorkerCount), total: Double(max(1, viewModel.workers.count)))
                Text(
                    "queue.progress.summary".localizedFormat(
                        fallback: "已完成: %d/%d | 运行中: %d | 失败: %d",
                        finishedWorkerCount,
                        viewModel.workers.count,
                        runningWorkerCount,
                        failedWorkerCount
                    )
                )
                .font(.caption2)
                .foregroundStyle(.secondary)

                ForEach(viewModel.workers) { worker in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(statusColor(worker.status))
                            .frame(width: 8, height: 8)
                            .padding(.top, 5)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(
                                "queue.worker.statusLine".localizedFormat(
                                    fallback: "Worker %d · %@",
                                    worker.id,
                                    workerStatusText(worker.status)
                                )
                            )
                                .font(.caption.weight(.semibold))
                            Text(worker.prompt)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            if let error = worker.error, !error.isEmpty {
                                Text(error)
                                    .font(.caption2)
                                    .foregroundStyle(Color.semanticDanger)
                                    .lineLimit(2)
                            }
                            HStack(spacing: 8) {
                                if let path = worker.outputPath {
                                    Button("queue.outputs.openWorker".localized(fallback: "查看 worker 输出")) {
                                        viewModel.openPathInFinder(path)
                                    }
                                    .buttonStyle(.borderless)
                                }
                                if let path = worker.stdoutPath {
                                    Button("queue.outputs.openStdout".localized(fallback: "stdout")) {
                                        viewModel.openPathInFinder(path)
                                    }
                                    .buttonStyle(.borderless)
                                }
                                if let path = worker.stderrPath {
                                    Button("queue.outputs.openStderr".localized(fallback: "stderr")) {
                                        viewModel.openPathInFinder(path)
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                            .font(.caption2)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var observabilityCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("queue.observability".localized(fallback: "观测性"))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Text(
                    "queue.observability.phase".localizedFormat(
                        fallback: "阶段: %@",
                        phaseText(viewModel.phase)
                    )
                )
                if let startedAt = viewModel.runStartedAt {
                    Text(
                        "queue.observability.started".localizedFormat(
                            fallback: "开始: %@",
                            formatTime(startedAt)
                        )
                    )
                }
                if viewModel.isRunning {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        if let elapsed = elapsedText(referenceDate: context.date) {
                            Text(
                                "queue.observability.elapsed".localizedFormat(
                                    fallback: "耗时: %@",
                                    elapsed
                                )
                            )
                        }
                    }
                } else if let elapsed = elapsedText(referenceDate: viewModel.runFinishedAt ?? Date()) {
                    Text(
                        "queue.observability.elapsed".localizedFormat(
                            fallback: "耗时: %@",
                            elapsed
                        )
                    )
                }
                Spacer()
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            if viewModel.runEvents.isEmpty {
                Text("queue.observability.empty".localized(fallback: "暂无运行事件。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(viewModel.runEvents.suffix(60))) { event in
                            HStack(alignment: .top, spacing: 8) {
                                Text(formatEventTime(event.timestamp))
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                Text(event.message)
                                    .font(.caption2)
                                    .foregroundStyle(eventLevelColor(event.level))
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }
                .frame(minHeight: 80, maxHeight: 180)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var outputCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("queue.outputs".localized(fallback: "输出"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let jobPath = viewModel.jobPath {
                outputRow(
                    label: "queue.outputs.job".localized(fallback: "Job 目录"),
                    value: jobPath
                ) { viewModel.openPathInFinder(jobPath) }
            }
            if let aggregatePath = viewModel.aggregateOutputPath {
                outputRow(
                    label: "queue.outputs.aggregate".localized(fallback: "汇总清单"),
                    value: aggregatePath
                ) { viewModel.openPathInFinder(aggregatePath) }
            }
            if let fixPath = viewModel.fixOutputPath {
                outputRow(
                    label: "queue.outputs.fix".localized(fallback: "修复报告"),
                    value: fixPath
                ) { viewModel.openPathInFinder(fixPath) }
            }
            if let summary = viewModel.lastRunSummary {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var statusBadge: some View {
        Text(phaseText(viewModel.phase))
            .font(.caption.monospaced())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.15), in: Capsule())
    }

    private var startDisabled: Bool {
        viewModel.isRunning ||
        (codexInstalled == false) ||
        viewModel.workspacePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var failedWorkerCount: Int {
        viewModel.workers.filter { $0.status == .failed }.count
    }

    private var runningWorkerCount: Int {
        viewModel.workers.filter { $0.status == .running }.count
    }

    private var finishedWorkerCount: Int {
        viewModel.workers.filter { $0.status == .completed || $0.status == .failed }.count
    }

    private func outputRow(label: String, value: String, action: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label + ":")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .lineLimit(2)
            Button("queue.outputs.open".localized(fallback: "打开")) {
                action()
            }
            .buttonStyle(.rowAction)
            Spacer()
        }
    }

    @ViewBuilder
    private func actionFeedbackIcon(baseSystemImage: String, state: ActionFeedbackState) -> some View {
        ZStack {
            SmallProgressView()
                .opacity(state == .busy ? 1 : 0)
            Image(systemName: "checkmark")
                .foregroundStyle(Color.semanticSuccess)
                .scaleEffect((state == .success && !reduceMotion) ? 1.08 : 1.0)
                .opacity(state == .success ? 1 : 0)
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.semanticDanger)
                .scaleEffect((state == .failure && !reduceMotion) ? 1.06 : 1.0)
                .opacity(state == .failure ? 1 : 0)
            Image(systemName: baseSystemImage)
                .opacity(state == .idle ? 1 : 0)
        }
        .frame(width: 14, height: 14)
        .motionAwareAnimation(QuotioMotion.contentSwap, value: state)
    }

    private var latestErrorMessage: String? {
        let trimmed = viewModel.errorMessage?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func scheduleFeedbackReset(_ channel: FeedbackChannel) {
        Task {
            try? await Task.sleep(for: .milliseconds(TopFeedbackRhythm.pulseMilliseconds(reduceMotion: reduceMotion)))
            await MainActor.run {
                switch channel {
                case .start:
                    if startFeedbackState != .busy {
                        startFeedbackState = .idle
                    }
                case .rerun:
                    if rerunFeedbackState != .busy {
                        rerunFeedbackState = .idle
                    }
                case .cancel:
                    if cancelFeedbackState != .busy {
                        cancelFeedbackState = .idle
                    }
                case .historyRefresh:
                    if historyRefreshFeedbackState != .busy {
                        historyRefreshFeedbackState = .idle
                    }
                }
            }
        }
    }

    private func statusColor(_ status: ReviewWorkerStatus) -> Color {
        switch status {
        case .pending:
            return .secondary
        case .running:
            return Color.semanticInfo
        case .completed:
            return Color.semanticSuccess
        case .failed:
            return Color.semanticDanger
        }
    }

    private func historyTitle(_ item: ReviewQueueHistoryItem) -> String {
        guard let createdAt = item.createdAt else {
            return item.jobId
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return "\(item.jobId) · \(formatter.string(from: createdAt))"
    }

    private func formatTime(_ date: Date?) -> String {
        guard let date else { return "-" }
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    private func formatEventTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    private func elapsedText(referenceDate: Date) -> String? {
        guard let started = viewModel.runStartedAt else { return nil }
        let end = viewModel.runFinishedAt ?? referenceDate
        let total = max(0, Int(end.timeIntervalSince(started)))
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func historyPhaseBadge(_ phase: ReviewQueuePhase) -> some View {
        Text(phaseText(phase))
            .font(.caption2.monospaced())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(historyPhaseColor(phase).opacity(0.16), in: Capsule())
            .foregroundStyle(historyPhaseColor(phase))
    }

    private func phaseText(_ phase: ReviewQueuePhase) -> String {
        "queue.phase.\(phase.rawValue)".localized()
    }

    private func workerStatusText(_ status: ReviewWorkerStatus) -> String {
        "queue.worker.status.\(status.rawValue)".localized(fallback: workerStatusFallback(status))
    }

    private func workerStatusFallback(_ status: ReviewWorkerStatus) -> String {
        switch status {
        case .pending:
            return "待执行"
        case .running:
            return "运行中"
        case .completed:
            return "已完成"
        case .failed:
            return "失败"
        }
    }

    private func historyPhaseColor(_ phase: ReviewQueuePhase) -> Color {
        switch phase {
        case .completed:
            return Color.semanticSuccess
        case .failed:
            return Color.semanticDanger
        case .cancelled:
            return .secondary
        case .fixing, .aggregating, .reviewing, .preparing:
            return Color.semanticInfo
        case .idle:
            return .secondary
        }
    }

    private func eventLevelColor(_ level: ReviewQueueRunEventLevel) -> Color {
        switch level {
        case .info:
            return .secondary
        case .warning:
            return Color.semanticInfo
        case .error:
            return Color.semanticDanger
        }
    }
}

#Preview {
    ReviewQueueScreen()
        .environment(QuotaViewModel())
        .frame(width: 900, height: 700)
}
