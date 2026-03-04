//
//  RemoteConnectionSheet.swift
//  Quotio - Remote CLIProxyAPI connection configuration
//

import SwiftUI

struct RemoteConnectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(QuotaViewModel.self) private var viewModel
    
    let existingConfig: RemoteConnectionConfig?
    let onSave: (RemoteConnectionConfig, String) -> Void
    
    @State private var displayName: String = ""
    @State private var endpointURL: String = ""
    @State private var managementKey: String = ""
    @State private var verifySSL: Bool = true
    @State private var timeoutSeconds: Int = 30
    @State private var isTestingConnection = false
    @State private var testResult: RemoteTestResult?
    @State private var emphasizeTestSuccess = false
    @State private var showTestCompletionBadge = false
    @State private var testResultPulse = false
    @State private var showSSLWarning = false
    @State private var pendingSSLValue = false
    
    private var isEditing: Bool { existingConfig != nil }

    private var trimmedEndpointURL: String {
        endpointURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedManagementKey: String {
        managementKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private var urlValidation: RemoteURLValidationResult {
        RemoteURLValidator.validate(trimmedEndpointURL)
    }
    
    /// Check if URL uses HTTP (not HTTPS) - security warning needed
    private var isInsecureHTTP: Bool {
        let trimmed = trimmedEndpointURL.lowercased()
        return trimmed.hasPrefix("http://") && urlValidation == .valid
    }
    
    private var canSave: Bool {
        urlValidation == .valid && !trimmedManagementKey.isEmpty && !displayName.isEmpty
    }

    private var feedbackPulseMilliseconds: Int {
        TopFeedbackRhythm.pulseMilliseconds(reduceMotion: reduceMotion)
    }

    private var successEmphasisMilliseconds: Int {
        feedbackPulseMilliseconds * 6
    }

    private var completionBadgeMilliseconds: Int {
        feedbackPulseMilliseconds * 2
    }
    
    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    connectionSection
                    authenticationSection
                    advancedSection

                    if isTestingConnection {
                        testingConnectionSection
                            .transition(.opacity.combined(with: .offset(y: 8)))
                    }
                    
                    if let result = testResult {
                        testResultSection(result)
                            .transition(.opacity.combined(with: .offset(y: 8)))
                    }
                }
                .padding(24)
                .motionAwareAnimation(QuotioMotion.contentSwap, value: isTestingConnection)
                .motionAwareAnimation(QuotioMotion.contentSwap, value: testResult?.success)
            }
            
            Divider()
            footerView
        }
        .frame(width: 500, height: 550)
        .onAppear {
            loadExistingConfig()
        }
        .alert("remote.sslWarning.title".localized(), isPresented: $showSSLWarning) {
            Button("action.cancel".localized(), role: .cancel) {
                // Do nothing - keep SSL enabled
            }
            Button("remote.sslWarning.confirm".localized(), role: .destructive) {
                verifySSL = pendingSSLValue
            }
        } message: {
            Text("remote.sslWarning.message".localized())
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack(spacing: 16) {
            Image(systemName: "network")
                .font(.title2)
                .foregroundStyle(Color.semanticInfo)
                .frame(width: 32, height: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(isEditing ? "remote.edit".localized() : "remote.configure".localized())
                    .font(.headline)
                
                Text("remote.description".localized())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("action.close".localized())
            .help("action.close".localized())
        }
        .padding(24)
    }
    
    // MARK: - Connection Section
    
    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("remote.connection".localized())
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("remote.displayName".localized())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                TextField("remote.displayName.placeholder".localized(), text: $displayName)
                    .textFieldStyle(.roundedBorder)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("remote.endpointURL".localized())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                TextField("remote.endpointURL.placeholder".localized(fallback: "请输入远程 CLIProxyAPI 地址"), text: $endpointURL)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                
                if let errorMessage = urlValidation.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.semanticDanger)
                } else if isInsecureHTTP {
                    Label("remote.httpWarning".localized(), systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.semanticWarning)
                }
            }
        }
        .padding()
        .background(Color.semanticSurfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    // MARK: - Authentication Section
    
    private var authenticationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("remote.authentication".localized())
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("remote.managementKey".localized())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                SecureField("remote.managementKey.placeholder".localized(), text: $managementKey)
                    .textFieldStyle(.roundedBorder)
                
                Text("remote.managementKey.hint".localized())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color.semanticSurfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    // MARK: - Advanced Section
    
    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("remote.advanced".localized())
                .font(.headline)
            
            Toggle("remote.verifySSL".localized(), isOn: Binding(
                get: { verifySSL },
                set: { newValue in
                    if !newValue {
                        // User is trying to disable SSL - show warning first
                        pendingSSLValue = newValue
                        showSSLWarning = true
                    } else {
                        verifySSL = newValue
                    }
                }
            ))
            
            if !verifySSL {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.semanticWarning)
                    Text("remote.verifySSL.warning".localized())
                        .font(.caption)
                        .foregroundStyle(Color.semanticWarning)
                    Spacer()
                }
                .padding(10)
                .background(Color.semanticWarning.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.semanticWarning.opacity(0.35), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .transition(.opacity.combined(with: .offset(y: -4)))
            }
            
            HStack {
                Text("remote.timeout".localized())
                Spacer()
                Picker("", selection: $timeoutSeconds) {
                    Text(timeoutOptionLabel(15)).tag(15)
                    Text(timeoutOptionLabel(30)).tag(30)
                    Text(timeoutOptionLabel(60)).tag(60)
                    Text(timeoutOptionLabel(120)).tag(120)
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
                .accessibilityLabel("remote.timeout".localized())
                .help("remote.timeout".localized())
            }
        }
        .padding()
        .background(Color.semanticSurfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .motionAwareAnimation(QuotioMotion.contentSwap, value: verifySSL)
    }
    
    // MARK: - Test Result Section
    
    private func testResultSection(_ result: RemoteTestResult) -> some View {
        HStack(spacing: 12) {
            Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(result.success ? Color.semanticSuccess : Color.semanticDanger)
                .scaleEffect(result.success && emphasizeTestSuccess ? 1.08 : 1.0)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(result.success ? "remote.test.success".localized() : "remote.test.failed".localized())
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                if let message = result.message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
        }
        .padding()
        .background(result.success ? Color.semanticSuccess.opacity(0.1) : Color.semanticDanger.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            if testResultPulse {
                RoundedRectangle(cornerRadius: 8)
                    .stroke((result.success ? Color.semanticSuccess : Color.semanticDanger).opacity(0.5), lineWidth: 1)
                    .transition(.opacity)
            }
        }
        .scaleEffect(testResultPulse ? (result.success ? 1.01 : 0.995) : 1.0)
        .motionAwareAnimation(TopFeedbackRhythm.pulseAnimation(reduceMotion: reduceMotion), value: testResultPulse)
    }

    private var testingConnectionSection: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)

            VStack(alignment: .leading, spacing: 2) {
                Text("remote.test.inProgress".localized(fallback: "正在测试连接…"))
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("remote.test.inProgress.hint".localized(fallback: "请稍候，完成后将显示测试结果。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(Color.semanticInfo.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("remote.test.inProgress".localized(fallback: "正在测试连接"))
    }
    
    // MARK: - Footer
    
    private var footerView: some View {
        HStack(spacing: 12) {
            Button {
                Task {
                    await testConnection()
                }
            } label: {
                HStack(spacing: 8) {
                    ZStack {
                        if isTestingConnection {
                            ProgressView()
                                .controlSize(.small)
                        } else if showTestCompletionBadge {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.semanticSuccess)
                                .scaleEffect(reduceMotion ? 1.0 : 1.08)
                        } else {
                            Image(systemName: "network")
                        }
                    }
                    .frame(width: 14, height: 14)
                    Text(isTestingConnection
                         ? "remote.test.inProgress".localized(fallback: "正在测试连接…")
                         : (showTestCompletionBadge
                            ? "remote.test.success".localized(fallback: "连接成功")
                            : "remote.test".localized()))
                }
            }
            .disabled(!canSave || isTestingConnection)
            .buttonStyle(.borderedProminent)
            .tint(testResult?.success == true ? Color.semanticSuccess : Color.semanticInfo)
            .motionAwareAnimation(QuotioMotion.contentSwap, value: isTestingConnection)
            .motionAwareAnimation(QuotioMotion.contentSwap, value: showTestCompletionBadge)
            
            Spacer()
            
            Button("action.cancel".localized()) {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            
            Button("action.save".localized()) {
                saveConfiguration()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!canSave)
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
    }
    
    // MARK: - Actions
    
    private func loadExistingConfig() {
        guard let config = existingConfig else { return }
        
        displayName = config.displayName
        endpointURL = config.endpointURL
        verifySSL = config.verifySSL
        timeoutSeconds = config.timeoutSeconds
        
        if let key = KeychainHelper.getManagementKey(for: config.id) {
            managementKey = key
        }
    }
    
    private func testConnection() async {
        isTestingConnection = true
        testResult = nil
        emphasizeTestSuccess = false
        showTestCompletionBadge = false
        testResultPulse = false

        let sanitizedEndpoint = RemoteURLValidator.sanitize(trimmedEndpointURL)
        let trimmedKey = trimmedManagementKey

        let config = RemoteConnectionConfig(
            endpointURL: sanitizedEndpoint,
            displayName: displayName,
            verifySSL: verifySSL,
            timeoutSeconds: timeoutSeconds
        )

        let client = ManagementAPIClient(config: config, managementKey: trimmedKey)
        defer {
            Task { await client.invalidate() }
        }
        
        let success = await client.checkProxyResponding()
        
        testResult = RemoteTestResult(
            success: success,
            message: success ? nil : "remote.test.cannotConnect".localized()
        )
        testResultPulse = true
        Task {
            try? await Task.sleep(for: .milliseconds(feedbackPulseMilliseconds))
            await MainActor.run {
                testResultPulse = false
            }
        }
        
        isTestingConnection = false
        if success {
            showTestCompletionBadge = true
            if reduceMotion {
                emphasizeTestSuccess = true
            } else {
                withMotionAwareAnimation(QuotioMotion.successEmphasis, reduceMotion: reduceMotion) {
                    emphasizeTestSuccess = true
                }
                Task {
                    try? await Task.sleep(for: .milliseconds(successEmphasisMilliseconds))
                    withMotionAwareAnimation(QuotioMotion.dismiss, reduceMotion: reduceMotion) {
                        emphasizeTestSuccess = false
                    }
                }
            }
            Task {
                try? await Task.sleep(for: .milliseconds(completionBadgeMilliseconds))
                await MainActor.run {
                    showTestCompletionBadge = false
                }
            }
        }
    }

    private func timeoutOptionLabel(_ seconds: Int) -> String {
        "remote.timeout.seconds".localizedFormat(fallback: "%d秒", seconds)
    }
    
    private func saveConfiguration() {
        let sanitizedEndpoint = RemoteURLValidator.sanitize(trimmedEndpointURL)
        let trimmedKey = trimmedManagementKey

        let config = RemoteConnectionConfig(
            endpointURL: sanitizedEndpoint,
            displayName: displayName,
            verifySSL: verifySSL,
            timeoutSeconds: timeoutSeconds,
            id: existingConfig?.id ?? UUID().uuidString
        )

        onSave(config, trimmedKey)
        dismiss()
    }
}

struct RemoteTestResult {
    let success: Bool
    let message: String?
}
