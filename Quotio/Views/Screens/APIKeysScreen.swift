//
//  APIKeysScreen.swift
//  Quotio
//

import SwiftUI
import AppKit

struct APIKeysScreen: View {
    @Environment(QuotaViewModel.self) private var viewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    @State private var newAPIKey: String = ""
    @State private var editingKeyIndex: Int? = nil
    @State private var editedKeyValue: String = ""
    @State private var showingAddKey: Bool = false
    @State private var keyPendingDeletion: String?
    @State private var feedback: TopFeedbackItem?
    @State private var actionState: APIKeyActionState = .idle
    @State private var addActionFeedbackState: SubmissionFeedbackState = .idle
    @State private var recentlyCopiedKey: String?
    @State private var recentlyUpdatedKey: String?
    @State private var recentlyFailedUpdateKey: String?
    @State private var addSucceededPulse = false
    private var feedbackPulseMilliseconds: Int {
        TopFeedbackRhythm.pulseMilliseconds(reduceMotion: reduceMotion)
    }
    private var feedbackPulseAnimation: Animation {
        TopFeedbackRhythm.pulseAnimation(reduceMotion: reduceMotion)
    }
    
    var body: some View {
        Group {
            if !viewModel.proxyManager.proxyStatus.running {
                proxyNotRunningView
            } else {
                apiKeysListView
            }
        }
        .navigationTitle("nav.apiKeys".localized())
        .overlay(alignment: .top) {
            TopFeedbackBanner(item: $feedback)
        }
        .motionAwareAnimation(QuotioMotion.appear, value: contentState)
        .motionAwareAnimation(QuotioMotion.appear, value: showingAddKey)
        .onChange(of: newAPIKey) { _, _ in
            guard addActionFeedbackState == .failure else { return }
            withMotionAwareAnimation(feedbackPulseAnimation, reduceMotion: reduceMotion) {
                addActionFeedbackState = .idle
            }
        }
        .task(id: viewModel.proxyManager.proxyStatus.running) {
            guard viewModel.proxyManager.proxyStatus.running else { return }
            await viewModel.fetchAPIKeys()
        }
        .toolbar {
            if viewModel.proxyManager.proxyStatus.running {
                ToolbarItemGroup {
                    Button {
                        newAPIKey = generateRandomKey()
                        showingAddKey = true
                    } label: {
                        Label("apiKeys.generate".localized(), systemImage: "wand.and.stars")
                    }
                    .buttonStyle(.toolbarIcon)
                    .disabled(actionState.isInFlight)
                    .help("apiKeys.generateHelp".localized())
                    
                    Button {
                        showingAddKey = true
                    } label: {
                        Label("apiKeys.add".localized(), systemImage: "plus")
                    }
                    .buttonStyle(.toolbarIcon)
                    .disabled(actionState.isInFlight)
                    .help("apiKeys.addHelp".localized())
                }
            }
        }
        .confirmationDialog(
            "apiKeys.confirm.delete.title".localized(fallback: "确认删除 API Key"),
            isPresented: Binding(
                get: { keyPendingDeletion != nil },
                set: { isPresented in
                    if !isPresented {
                        keyPendingDeletion = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("action.delete".localized(fallback: "删除"), role: .destructive) {
                guard let key = keyPendingDeletion else { return }
                Task {
                    let previousError = normalizedErrorMessage(viewModel.errorMessage)
                    actionState = .deleting(key)
                    await viewModel.deleteAPIKey(key)
                    await MainActor.run {
                        actionState = .idle
                        keyPendingDeletion = nil
                        if let actionError = latestActionError(previousError: previousError) {
                            showFeedback(
                                "apiKeys.feedback.deleteFailed".localized(fallback: "删除失败") + ": " + actionError,
                                isError: true
                            )
                        } else {
                            showDestructiveFeedback("apiKeys.feedback.deleted".localized(fallback: "API Key 已删除"))
                        }
                    }
                }
            }
            Button("action.cancel".localized(fallback: "取消"), role: .cancel) {
                keyPendingDeletion = nil
            }
        } message: {
            Text("apiKeys.confirm.delete.message".localized(fallback: "删除后将立即失效，且无法恢复。"))
        }
    }
    
    private var proxyNotRunningView: some View {
        ProxyRequiredView(
            description: "apiKeys.proxyRequired".localized()
        ) {
            await viewModel.startProxy()
        }
    }
    
    private var apiKeysListView: some View {
        Group {
            if viewModel.isLoading && viewModel.apiKeys.isEmpty {
                ContentUnavailableView {
                    ProgressView()
                } description: {
                    Text("action.loading".localized(fallback: "加载中..."))
                }
            } else if let errorMessage = viewModel.errorMessage, viewModel.apiKeys.isEmpty {
                ContentUnavailableView {
                    Label("status.error".localized(fallback: "加载失败"), systemImage: "exclamationmark.triangle.fill")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("action.retry".localized(fallback: "重试")) {
                        Task { await viewModel.fetchAPIKeys() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                apiKeysListContent
            }
        }
        .transition(.opacity)
    }

    private var apiKeysListContent: some View {
        List {
            if let errorMessage = viewModel.errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.semanticWarning)
                }
            } else if !viewModel.apiKeys.isEmpty {
                Section {
                    Label("status.connected".localized(fallback: "操作成功"), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Color.semanticSuccess)
                }
            }

            Section {
                ForEach(Array(viewModel.apiKeys.enumerated()), id: \.offset) { index, key in
                    APIKeyRow(
                        key: key,
                        isEditing: editingKeyIndex == index,
                        isBusy: actionState == .updating(key) || actionState == .deleting(key),
                        isCopyConfirmed: recentlyCopiedKey == key,
                        isSaveConfirmed: recentlyUpdatedKey == key,
                        isSaveError: recentlyFailedUpdateKey == key,
                        editedValue: $editedKeyValue,
                        onEdit: {
                            editingKeyIndex = index
                            editedKeyValue = key
                        },
                        onSave: {
                            Task {
                                let previousError = normalizedErrorMessage(viewModel.errorMessage)
                                actionState = .updating(key)
                                let didSucceed = await viewModel.updateAPIKey(old: key, new: editedKeyValue)
                                await MainActor.run {
                                    actionState = .idle
                                    if let actionError = latestActionError(previousError: previousError) {
                                        recentlyFailedUpdateKey = key
                                        showFeedback(
                                            "apiKeys.feedback.updateFailed".localized(fallback: "更新失败") + ": " + actionError,
                                            isError: true
                                        )
                                        Task {
                                            try? await Task.sleep(for: .milliseconds(feedbackPulseMilliseconds))
                                            await MainActor.run {
                                                if recentlyFailedUpdateKey == key {
                                                    recentlyFailedUpdateKey = nil
                                                }
                                            }
                                        }
                                        return
                                    }
                                    recentlyFailedUpdateKey = nil
                                    if didSucceed {
                                        recentlyUpdatedKey = key
                                        showFeedback("apiKeys.feedback.updated".localized(fallback: "API Key 已更新"))
                                        Task {
                                            try? await Task.sleep(for: .milliseconds(feedbackPulseMilliseconds))
                                            await MainActor.run {
                                                if recentlyUpdatedKey == key {
                                                    recentlyUpdatedKey = nil
                                                }
                                                editingKeyIndex = nil
                                                editedKeyValue = ""
                                            }
                                        }
                                    }
                                }
                            }
                        },
                        onCancel: {
                            editingKeyIndex = nil
                            editedKeyValue = ""
                            recentlyFailedUpdateKey = nil
                        },
                        onCopy: {
                            copyToClipboard(key)
                        },
                        onDelete: {
                            keyPendingDeletion = key
                        }
                    )
                }
                
                if showingAddKey {
                    AddAPIKeyRow(
                        newKey: $newAPIKey,
                        feedbackState: addActionFeedbackState,
                        onSave: addNewKey,
                        onCancel: {
                            showingAddKey = false
                            addSucceededPulse = false
                            addActionFeedbackState = .idle
                            newAPIKey = ""
                        },
                        onGenerate: {
                            newAPIKey = generateRandomKey()
                        }
                    )
                }
            } header: {
                HStack {
                    Text("apiKeys.list".localized())
                    Spacer()
                    Text("\(viewModel.apiKeys.count)")
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("apiKeys.description".localized())
            }
        }
        .motionAwareAnimation(QuotioMotion.appear, value: viewModel.apiKeys.count)
        .overlay {
            if viewModel.apiKeys.isEmpty && !showingAddKey && !viewModel.isLoading && viewModel.errorMessage == nil {
                ContentUnavailableView {
                    Label("apiKeys.empty".localized(), systemImage: "key.slash")
                } description: {
                    Text("apiKeys.emptyDescription".localized())
                } actions: {
                    Button {
                        newAPIKey = generateRandomKey()
                        showingAddKey = true
                    } label: {
                        Text("apiKeys.generateFirst".localized())
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }
    
    private func addNewKey() {
        let trimmed = newAPIKey.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        
        Task {
            let previousError = normalizedErrorMessage(viewModel.errorMessage)
            actionState = .adding
            withMotionAwareAnimation(feedbackPulseAnimation, reduceMotion: reduceMotion) {
                addActionFeedbackState = .busy
            }
            await viewModel.addAPIKey(trimmed)
            await MainActor.run {
                actionState = .idle
                if let actionError = latestActionError(previousError: previousError) {
                    withMotionAwareAnimation(feedbackPulseAnimation, reduceMotion: reduceMotion) {
                        addActionFeedbackState = .failure
                    }
                    showFeedback(
                        "apiKeys.feedback.addFailed".localized(fallback: "添加失败") + ": " + actionError,
                        isError: true
                    )
                    return
                }
                showFeedback("apiKeys.feedback.added".localized(fallback: "API Key 已添加"))
                withMotionAwareAnimation(feedbackPulseAnimation, reduceMotion: reduceMotion) {
                    addActionFeedbackState = .success
                    addSucceededPulse = true
                }
                Task {
                    try? await Task.sleep(for: .milliseconds(feedbackPulseMilliseconds))
                    await MainActor.run {
                        withMotionAwareAnimation(feedbackPulseAnimation, reduceMotion: reduceMotion) {
                            addActionFeedbackState = .idle
                            addSucceededPulse = false
                        }
                        newAPIKey = ""
                        showingAddKey = false
                    }
                }
            }
        }
    }
    
    private func generateRandomKey() -> String {
        let prefix = "sk-"
        let characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        let randomPart = String((0..<32).map { _ in characters.randomElement()! })
        return prefix + randomPart
    }
    
    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        withMotionAwareAnimation(feedbackPulseAnimation, reduceMotion: reduceMotion) {
            recentlyCopiedKey = text
        }
        Task {
            try? await Task.sleep(for: .milliseconds(feedbackPulseMilliseconds))
            await MainActor.run {
                if recentlyCopiedKey == text {
                    withMotionAwareAnimation(feedbackPulseAnimation, reduceMotion: reduceMotion) {
                        recentlyCopiedKey = nil
                    }
                }
            }
        }
        showFeedback("apiKeys.feedback.copied".localized(fallback: "已复制到剪贴板"))
    }

    private var contentState: APIKeysContentState {
        if !viewModel.proxyManager.proxyStatus.running { return .proxyStopped }
        if viewModel.isLoading && viewModel.apiKeys.isEmpty { return .loading }
        if viewModel.errorMessage != nil && viewModel.apiKeys.isEmpty { return .error }
        if viewModel.apiKeys.isEmpty && !showingAddKey { return .empty }
        return .ready
    }

    private func latestActionError(previousError: String?) -> String? {
        guard let currentError = normalizedErrorMessage(viewModel.errorMessage) else {
            return nil
        }
        if currentError == previousError {
            return nil
        }
        return currentError
    }

    private func normalizedErrorMessage(_ message: String?) -> String? {
        guard let text = message?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        return text
    }

    private func showFeedback(_ message: String, isError: Bool = false) {
        let item = isError ? TopFeedbackItem.error(message) : TopFeedbackItem.success(message)
        withMotionAwareAnimation(QuotioMotion.appear, reduceMotion: reduceMotion) {
            feedback = item
        }
    }

    private func showDestructiveFeedback(_ message: String) {
        withMotionAwareAnimation(QuotioMotion.appear, reduceMotion: reduceMotion) {
            feedback = TopFeedbackItem.destructiveSuccess(message)
        }
    }
}

private enum APIKeysContentState: Equatable {
    case proxyStopped
    case loading
    case error
    case empty
    case ready
}

private enum APIKeyActionState: Equatable {
    case idle
    case adding
    case updating(String)
    case deleting(String)

    var isInFlight: Bool {
        if case .idle = self { return false }
        return true
    }
}

struct APIKeyRow: View {
    let key: String
    let isEditing: Bool
    let isBusy: Bool
    let isCopyConfirmed: Bool
    let isSaveConfirmed: Bool
    let isSaveError: Bool
    @Binding var editedValue: String
    let onEdit: () -> Void
    let onSave: () -> Void
    let onCancel: () -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var copyPulse = false
    private var feedbackPulseAnimation: Animation {
        TopFeedbackRhythm.pulseAnimation(reduceMotion: reduceMotion)
    }
    
    var body: some View {
        HStack {
            if isEditing {
                TextField("apiKeys.placeholder".localized(), text: $editedValue)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit(onSave)
                    .disabled(isBusy)
                
                Button(action: onSave) {
                    ZStack {
                        if isBusy {
                            ProgressView()
                                .controlSize(.small)
                        } else if isSaveError {
                            Image(systemName: "xmark.octagon.fill")
                                .foregroundStyle(Color.semanticDanger)
                                .scaleEffect(!reduceMotion ? 1.04 : 1.0)
                                .motionAwareAnimation(QuotioMotion.contentSwap, value: isSaveError)
                        } else {
                            ZStack {
                                Image(systemName: "checkmark.circle")
                                    .foregroundStyle(.secondary)
                                    .opacity(isSaveConfirmed ? 0 : 1)
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.semanticSuccess)
                                    .opacity(isSaveConfirmed ? 1 : 0)
                            }
                            .scaleEffect(isSaveConfirmed && !reduceMotion ? 1.08 : 1.0)
                            .opacity(isSaveConfirmed ? 0.94 : 1.0)
                            .motionAwareAnimation(QuotioMotion.contentSwap, value: isSaveConfirmed)
                            .motionAwareAnimation(QuotioMotion.successEmphasis, value: isSaveConfirmed)
                        }
                    }
                    .frame(width: 16, height: 16)
                    .motionAwareAnimation(TopFeedbackRhythm.pulseAnimation(reduceMotion: reduceMotion), value: isBusy)
                    .motionAwareAnimation(QuotioMotion.contentSwap, value: isSaveError)
                }
                .buttonStyle(.subtle)
                .accessibilityLabel("action.save".localized(fallback: "保存"))
                .disabled(isBusy)
                
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.subtle)
                .accessibilityLabel("action.cancel".localized())
                .disabled(isBusy)
            } else {
                Text(maskedKey)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                
                Spacer()
                
                Button(action: onCopy) {
                    ZStack {
                        Image(systemName: "doc.on.doc")
                            .foregroundStyle(.primary)
                            .opacity(isCopyConfirmed ? 0 : 1)
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.semanticSuccess)
                            .opacity(isCopyConfirmed ? 1 : 0)
                    }
                    .frame(width: 16, height: 16)
                    .scaleEffect(copyPulse && !reduceMotion ? 1.12 : (isCopyConfirmed ? 1.04 : 1.0))
                    .opacity(isCopyConfirmed ? 0.92 : 1.0)
                    .motionAwareAnimation(QuotioMotion.contentSwap, value: isCopyConfirmed)
                    .motionAwareAnimation(QuotioMotion.successEmphasis, value: copyPulse)
                }
                .buttonStyle(.subtle)
                .help("action.copy".localized())
                .accessibilityLabel("action.copy".localized())
                .disabled(isBusy)
                
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.subtle)
                .help("apiKeys.edit".localized())
                .accessibilityLabel("apiKeys.edit".localized())
                .disabled(isBusy)
                
                Button(action: onDelete) {
                    ZStack {
                        if isBusy {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "trash")
                                .foregroundStyle(Color.semanticDanger)
                        }
                    }
                    .frame(width: 16, height: 16)
                    .motionAwareAnimation(feedbackPulseAnimation, value: isBusy)
                }
                .buttonStyle(.subtle)
                .help("action.delete".localized())
                .accessibilityLabel("action.delete".localized())
                .disabled(isBusy)
            }
        }
        .padding(.vertical, 4)
        .onChange(of: isCopyConfirmed) { _, isConfirmed in
            guard isConfirmed else {
                copyPulse = false
                return
            }
            if reduceMotion {
                copyPulse = false
                return
            }
            withMotionAwareAnimation(QuotioMotion.press, reduceMotion: reduceMotion) {
                copyPulse = true
            }
            Task {
                try? await Task.sleep(for: .milliseconds(TopFeedbackRhythm.pulseMilliseconds(reduceMotion: reduceMotion)))
                await MainActor.run {
                    withMotionAwareAnimation(QuotioMotion.dismiss, reduceMotion: reduceMotion) {
                        copyPulse = false
                    }
                }
            }
        }
    }
    
    private var maskedKey: String {
        guard key.count > 8 else { return String(repeating: "•", count: key.count) }
        let prefix = String(key.prefix(6))
        let suffix = String(key.suffix(4))
        return "\(prefix)••••••••\(suffix)"
    }
}

struct AddAPIKeyRow: View {
    @Binding var newKey: String
    let feedbackState: SubmissionFeedbackState
    let onSave: () -> Void
    let onCancel: () -> Void
    let onGenerate: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    var body: some View {
        HStack {
            TextField("apiKeys.placeholder".localized(), text: $newKey)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .onSubmit(onSave)
                .disabled(feedbackState == .busy)
            
            Button(action: onGenerate) {
                Image(systemName: "wand.and.stars")
            }
            .buttonStyle(.subtle)
            .help("apiKeys.generate".localized())
            .accessibilityLabel("apiKeys.generate".localized())
            .disabled(feedbackState == .busy)
            
            Button(action: onSave) {
                ZStack {
                    if feedbackState == .busy {
                        ProgressView()
                            .controlSize(.small)
                    } else if feedbackState == .failure {
                        Image(systemName: "xmark.octagon.fill")
                            .foregroundStyle(Color.semanticDanger)
                            .scaleEffect(!reduceMotion ? 1.04 : 1.0)
                            .motionAwareAnimation(QuotioMotion.contentSwap, value: feedbackState == .failure)
                    } else {
                        ZStack {
                            Image(systemName: "checkmark.circle")
                                .foregroundStyle(.secondary)
                                .opacity(feedbackState == .success ? 0 : 1)
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.semanticSuccess)
                                .opacity(feedbackState == .success ? 1 : 0)
                        }
                        .scaleEffect(feedbackState == .success && !reduceMotion ? 1.1 : 1.0)
                        .opacity(feedbackState == .success ? 0.94 : 1.0)
                        .motionAwareAnimation(QuotioMotion.contentSwap, value: feedbackState == .success)
                        .motionAwareAnimation(QuotioMotion.successEmphasis, value: feedbackState == .success)
                    }
                }
                .frame(width: 16, height: 16)
                .motionAwareAnimation(QuotioMotion.contentSwap, value: feedbackState)
            }
            .buttonStyle(.subtle)
            .accessibilityLabel("action.save".localized(fallback: "保存"))
            .disabled(newKey.trimmingCharacters(in: .whitespaces).isEmpty || feedbackState == .busy || feedbackState == .success)
            
            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.subtle)
            .accessibilityLabel("action.cancel".localized())
            .disabled(feedbackState == .busy)
        }
        .padding(.vertical, 4)
    }
}

enum SubmissionFeedbackState: Equatable {
    case idle
    case busy
    case success
    case failure
}
