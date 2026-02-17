//
//  ReviewQueueScreen.swift
//  Quotio
//
//  Automated multi-session review queue UI.
//

import SwiftUI

struct ReviewQueueScreen: View {
    @Environment(QuotaViewModel.self) private var quotaViewModel
    @State private var codexInstalled: Bool?

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
                        viewModel.refreshHistory()
                    }
                ))
                .textFieldStyle(.roundedBorder)

                Button("action.browse".localized(fallback: "浏览")) {
                    viewModel.chooseWorkspace()
                }
                .buttonStyle(.bordered)
                Button("queue.history.refresh".localized(fallback: "刷新历史")) {
                    viewModel.refreshHistory()
                }
                .buttonStyle(.bordered)
            }
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
            } else {
                Stepper(
                    "queue.prompt.workers".localized(fallback: "并发 Worker 数") + ": \(viewModel.workerCount)",
                    value: Binding(
                        get: { viewModel.workerCount },
                        set: { viewModel.workerCount = $0 }
                    ),
                    in: 1...8
                )

                TextEditor(text: Binding(
                    get: { viewModel.sharedReviewPrompt },
                    set: { viewModel.sharedReviewPrompt = $0 }
                ))
                .frame(minHeight: 90)
                .font(.system(.body, design: .monospaced))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))
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
            HStack(spacing: 10) {
                Button(viewModel.isRunning ? "queue.running".localized(fallback: "运行中...") : "queue.start".localized(fallback: "启动 Queue")) {
                    viewModel.startRun()
                }
                .buttonStyle(.borderedProminent)
                .disabled(startDisabled)

                Button("queue.rerunFailed".localized(fallback: "仅重跑失败项")) {
                    viewModel.rerunFailedWorkers()
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isRunning || failedWorkerCount == 0)

                Button("action.cancel".localized(fallback: "取消")) {
                    viewModel.cancelRun()
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.isRunning)
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
            Text("queue.history".localized(fallback: "历史任务"))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if viewModel.historyItems.isEmpty {
                Text("queue.history.empty".localized(fallback: "当前工作区暂无历史任务。"))
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
                        Text("Worker: \(item.workerCount) | Failed: \(item.failedWorkerCount) | Model: \(item.model ?? "-")")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            Button("queue.outputs.openJob".localized(fallback: "打开 Job")) {
                                viewModel.openPathInFinder(item.jobPath)
                            }
                            .buttonStyle(.borderless)
                            if let path = item.aggregateOutputPath {
                                Button("queue.outputs.openAggregate".localized(fallback: "打开汇总")) {
                                    viewModel.openPathInFinder(path)
                                }
                                .buttonStyle(.borderless)
                            }
                            if let path = item.fixOutputPath {
                                Button("queue.outputs.openFix".localized(fallback: "打开修复")) {
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
                ForEach(viewModel.workers) { worker in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(statusColor(worker.status))
                            .frame(width: 8, height: 8)
                            .padding(.top, 5)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Worker \(worker.id) · \(worker.status.rawValue)")
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
                        }
                    }
                    .padding(.vertical, 2)
                }
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
        Text(viewModel.phase.rawValue)
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
            .buttonStyle(.borderless)
            Spacer()
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

    private func historyPhaseBadge(_ phase: ReviewQueuePhase) -> some View {
        Text(phase.rawValue)
            .font(.caption2.monospaced())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(historyPhaseColor(phase).opacity(0.16), in: Capsule())
            .foregroundStyle(historyPhaseColor(phase))
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
}

#Preview {
    ReviewQueueScreen()
        .environment(QuotaViewModel())
        .frame(width: 900, height: 700)
}
