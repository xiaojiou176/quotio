//
//  RemoteSetupStep.swift
//  Quotio - CLIProxyAPI GUI Wrapper
//

import SwiftUI
import AppKit

struct RemoteSetupStep: View {
    @Bindable var viewModel: OnboardingViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showPassword = false
    @State private var copyKeyFeedbackState: OnboardingSubmissionFeedbackState = .idle
    @State private var continueFeedbackState: OnboardingSubmissionFeedbackState = .idle
    @State private var testFeedbackState: OnboardingSubmissionFeedbackState = .idle
    @State private var testFeedbackMessage: String?
    @State private var showInvalidContinueHint = false
    
    private var urlValidation: RemoteURLValidationResult {
        RemoteURLValidator.validate(viewModel.remoteEndpoint)
    }
    
    private var feedbackPulseAnimation: Animation {
        TopFeedbackRhythm.pulseAnimation(reduceMotion: reduceMotion)
    }
    
    var body: some View {
        VStack(spacing: 24) {
            headerSection
            
            formSection
                .frame(maxWidth: 460)

            if viewModel.isRemoteConfigValid {
                configReadyFeedback
                    .frame(maxWidth: 460)
                    .transition(.opacity.combined(with: .offset(y: 6)))
            }

            if let testFeedbackMessage, !testFeedbackMessage.isEmpty {
                testFeedbackBanner(testFeedbackMessage)
                    .frame(maxWidth: 460)
                    .transition(.opacity.combined(with: .offset(y: 6)))
            }
            
            Spacer()
            
            navigationButtons
        }
        .padding(32)
        .motionAwareAnimation(QuotioMotion.contentSwap, value: viewModel.isRemoteConfigValid)
        .motionAwareAnimation(feedbackPulseAnimation, value: testFeedbackState)
        .motionAwareAnimation(feedbackPulseAnimation, value: continueFeedbackState)
    }

    private var configReadyFeedback: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.semanticSuccess)
                .scaleEffect(1.04)
            Text("onboarding.remote.ready".localized(fallback: "配置有效，可继续下一步。"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(12)
        .background(Color.semanticSuccess.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "network")
                .font(.system(size: 40))
                .foregroundStyle(Color.semanticAccentSecondary)
            
            Text("onboarding.remote.title".localized())
                .font(.title2)
                .fontWeight(.bold)
            
            Text("onboarding.remote.subtitle".localized())
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
    
    private var formSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("onboarding.remote.endpoint".localized())
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                TextField(
                    "onboarding.remote.endpoint.placeholder".localized(fallback: "https://proxy.example.com:8317"),
                    text: $viewModel.remoteEndpoint
                )
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: viewModel.remoteEndpoint) { _, _ in
                        clearInlineErrors()
                    }
                
                if !viewModel.remoteEndpoint.isEmpty, let errorKey = urlValidation.localizationKey {
                    Text(errorKey.localized())
                        .font(.caption)
                        .foregroundStyle(Color.semanticDanger)
                }
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text("onboarding.remote.managementKey".localized())
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                HStack {
                    if showPassword {
                        TextField("onboarding.remote.managementKey.placeholder".localized(), text: $viewModel.remoteManagementKey)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: viewModel.remoteManagementKey) { _, _ in
                                clearInlineErrors()
                            }
                    } else {
                        SecureField("onboarding.remote.managementKey.placeholder".localized(), text: $viewModel.remoteManagementKey)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: viewModel.remoteManagementKey) { _, _ in
                                clearInlineErrors()
                            }
                    }
                    
                    Button {
                        showPassword.toggle()
                    } label: {
                        Image(systemName: showPassword ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("onboarding.remote.managementKey.toggleVisibility".localized(fallback: "切换密钥可见性"))
                    .help("onboarding.remote.managementKey.toggleVisibility".localized(fallback: "显示或隐藏管理密钥"))

                    Button {
                        let key = viewModel.remoteManagementKey.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !key.isEmpty else { return }
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(key, forType: .string)
                        copyKeyFeedbackState = .success
                        Task {
                            try? await Task.sleep(for: .milliseconds(TopFeedbackRhythm.pulseMilliseconds(reduceMotion: reduceMotion)))
                            await MainActor.run {
                                copyKeyFeedbackState = .idle
                            }
                        }
                    } label: {
                        Image(systemName: copyKeyFeedbackState == .success ? "checkmark.circle.fill" : "doc.on.doc")
                            .foregroundStyle(copyKeyFeedbackState == .success ? Color.semanticSuccess : .secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.remoteManagementKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("action.copy".localized(fallback: "复制"))
                    .help("action.copy".localized(fallback: "复制"))
                    .motionAwareAnimation(feedbackPulseAnimation, value: copyKeyFeedbackState)
                }
                
                if viewModel.remoteManagementKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("onboarding.remote.managementKey.required".localized(fallback: "请输入 Management Key。"))
                        .font(.caption)
                        .foregroundStyle(Color.semanticDanger)
                } else if let setupError = viewModel.remoteSetupErrorMessage, !setupError.isEmpty {
                    Text(setupError)
                        .font(.caption)
                        .foregroundStyle(Color.semanticDanger)
                } else {
                    Text("onboarding.remote.managementKey.hint".localized())
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            
            Button {
                Task { await testConnection() }
            } label: {
                HStack(spacing: 8) {
                    if testFeedbackState == .busy {
                        ProgressView()
                            .controlSize(.small)
                    } else if testFeedbackState == .success {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.semanticSuccess)
                    } else if testFeedbackState == .failure {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.semanticDanger)
                    } else {
                        Image(systemName: "network")
                    }
                    Text(
                        testFeedbackState == .busy
                        ? "remote.test.inProgress".localized(fallback: "正在测试连接…")
                        : "remote.test".localized(fallback: "测试连接")
                    )
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(testFeedbackState == .busy || !viewModel.isRemoteConfigValid)
            .motionAwareAnimation(feedbackPulseAnimation, value: testFeedbackState)
        }
    }
    
    private var navigationButtons: some View {
        VStack(alignment: .trailing, spacing: 8) {
            HStack(spacing: 12) {
                Button {
                    viewModel.goBack()
                } label: {
                    Text("onboarding.button.back".localized())
                        .frame(minWidth: 96)
                        .padding(.horizontal, 10)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                
                Button {
                    guard viewModel.isRemoteConfigValid else {
                        continueFeedbackState = .failure
                        showInvalidContinueHint = true
                        Task {
                            try? await Task.sleep(for: .milliseconds(TopFeedbackRhythm.pulseMilliseconds(reduceMotion: reduceMotion)))
                            await MainActor.run {
                                continueFeedbackState = .idle
                            }
                        }
                        return
                    }
                    continueFeedbackState = .success
                    viewModel.goNext()
                } label: {
                    HStack(spacing: 8) {
                        Text("onboarding.button.continue".localized())
                        ZStack {
                            Image(systemName: "arrow.right")
                                .opacity(continueFeedbackState == .success ? 0 : 1)
                            Image(systemName: continueFeedbackState == .failure ? "exclamationmark.triangle.fill" : "checkmark")
                                .foregroundStyle(continueFeedbackState == .failure ? Color.semanticDanger : Color.semanticSuccess)
                                .opacity(continueFeedbackState == .idle ? 0 : 1)
                        }
                        .frame(width: 12, height: 12)
                    }
                    .frame(minWidth: 128)
                    .padding(.horizontal, 14)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .motionAwareAnimation(feedbackPulseAnimation, value: continueFeedbackState)
            }

            if showInvalidContinueHint && !viewModel.isRemoteConfigValid {
                Label(
                    "onboarding.remote.continue.invalidHint".localized(
                        fallback: "请先填写有效地址与 Management Key，再继续。"
                    ),
                    systemImage: "exclamationmark.circle.fill"
                )
                .font(.caption)
                .foregroundStyle(Color.semanticDanger)
                .transition(.opacity)
            }
        }
    }

    private func clearInlineErrors() {
        viewModel.remoteSetupErrorMessage = nil
        viewModel.completionErrorMessage = nil
        if !viewModel.isRemoteConfigValid {
            showInvalidContinueHint = false
        }
    }
    
    @ViewBuilder
    private func testFeedbackBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: testFeedbackState == .success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(testFeedbackState == .success ? Color.semanticSuccess : Color.semanticDanger)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(12)
        .background(
            (testFeedbackState == .success ? Color.semanticSuccess : Color.semanticDanger)
                .opacity(0.1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    private func testConnection() async {
        guard viewModel.isRemoteConfigValid else { return }
        testFeedbackState = .busy
        testFeedbackMessage = nil

        let sanitizedEndpoint = RemoteURLValidator.sanitize(viewModel.remoteEndpoint)
        let trimmedKey = viewModel.remoteManagementKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let config = RemoteConnectionConfig(
            endpointURL: sanitizedEndpoint,
            displayName: "Remote Server"
        )
        let client = ManagementAPIClient(config: config, managementKey: trimmedKey)
        defer {
            Task { await client.invalidate() }
        }

        let isConnected = await client.checkProxyResponding()
        if isConnected {
            testFeedbackState = .success
            testFeedbackMessage = "remote.test.success".localized(fallback: "连接成功")
        } else {
            testFeedbackState = .failure
            testFeedbackMessage = "remote.test.cannotConnect".localized(fallback: "连接验证失败，请检查地址或 Management Key。")
        }
    }
}

#Preview {
    RemoteSetupStep(viewModel: OnboardingViewModel())
}
