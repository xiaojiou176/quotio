//
//  CompletionStep.swift
//  Quotio - CLIProxyAPI GUI Wrapper
//

import SwiftUI

struct CompletionStep: View {
    @Bindable var viewModel: OnboardingViewModel
    let onComplete: () async -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var successPulse = false
    @State private var submitFeedbackState: OnboardingSubmissionFeedbackState = .idle
    
    private var feedbackPulseAnimation: Animation {
        TopFeedbackRhythm.pulseAnimation(reduceMotion: reduceMotion)
    }
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            successIcon
            
            VStack(spacing: 12) {
                Text("onboarding.completion.title".localized())
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("onboarding.completion.subtitle".localized())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }
            
            selectedModeCard
            
            Spacer()
            
            VStack(spacing: 12) {
                Button {
                    Task {
                        submitFeedbackState = .busy
                        await onComplete()
                        await MainActor.run {
                            submitFeedbackState = viewModel.completionErrorMessage == nil ? .success : .failure
                        }
                        guard !reduceMotion else { return }
                        try? await Task.sleep(for: .milliseconds(TopFeedbackRhythm.pulseMilliseconds(reduceMotion: reduceMotion)))
                        await MainActor.run {
                            if submitFeedbackState != .busy {
                                submitFeedbackState = .idle
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        ZStack {
                            if viewModel.isCompleting || submitFeedbackState == .busy {
                                ProgressView()
                                    .controlSize(.small)
                            } else if submitFeedbackState == .failure {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(Color.semanticDanger)
                            } else if submitFeedbackState == .success {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.semanticSuccess)
                            } else {
                                Image(systemName: "arrow.right.circle")
                            }
                        }
                        .frame(width: 14, height: 14)

                        Text(
                            viewModel.isCompleting || submitFeedbackState == .busy
                            ? "onboarding.completion.verifying".localized(fallback: "正在验证连接…")
                            : "onboarding.button.openDashboard".localized()
                        )
                    }
                    .frame(minWidth: 180)
                    .padding(.horizontal, 20)
                    .scaleEffect(submitFeedbackState == .success && !reduceMotion ? 1.02 : 1.0)
                    .opacity(submitFeedbackState == .failure ? 0.96 : 1.0)
                }
                .disabled(viewModel.isCompleting)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .motionAwareAnimation(feedbackPulseAnimation, value: submitFeedbackState)

                if let completionError = viewModel.completionErrorMessage, !completionError.isEmpty {
                    Label(completionError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.semanticDanger)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)
                        .transition(.opacity.combined(with: .offset(y: 6)))
                } else {
                    HStack(spacing: 6) {
                        if submitFeedbackState == .success {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.semanticSuccess)
                        }
                        Text("onboarding.completion.hint".localized())
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .transition(.opacity.combined(with: .offset(y: 6)))
                }
            }
        }
        .padding(32)
        .motionAwareAnimation(QuotioMotion.contentSwap, value: viewModel.isCompleting)
        .motionAwareAnimation(QuotioMotion.contentSwap, value: viewModel.completionErrorMessage)
        .motionAwareAnimation(feedbackPulseAnimation, value: submitFeedbackState)
        .onAppear {
            guard !reduceMotion else {
                successPulse = false
                return
            }
            successPulse = true
        }
    }
    
    private var successIcon: some View {
        ZStack {
            Circle()
                .fill(Color.semanticSuccess.opacity(0.15))
                .frame(width: 80, height: 80)
                .scaleEffect(successPulse ? 1.04 : 1.0)
                .opacity(successPulse ? 1.0 : 0.85)
                .motionAwareAnimation(QuotioMotion.contentSwap.repeatForever(autoreverses: true), value: successPulse)
            
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.semanticSuccess)
        }
    }
    
    private var selectedModeCard: some View {
        HStack(spacing: 12) {
            Image(systemName: viewModel.selectedMode.icon)
                .font(.title2)
                .foregroundStyle(Color.semanticOnAccent)
                .frame(width: 44, height: 44)
                .background(viewModel.selectedMode.color)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.selectedMode.displayName)
                    .font(.headline)
                
                Text(viewModel.selectedMode.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding(16)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .frame(maxWidth: 400)
    }
}

#Preview {
    CompletionStep(viewModel: OnboardingViewModel()) {
        await Task.yield()
    }
}
