//
//  ProviderStep.swift
//  Quotio - CLIProxyAPI GUI Wrapper
//

import SwiftUI
import AppKit

struct ProviderStep: View {
    @Bindable var viewModel: OnboardingViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var copyFeedbackState: OnboardingSubmissionFeedbackState = .idle
    @State private var continueFeedbackState: OnboardingSubmissionFeedbackState = .idle
    
    private var feedbackPulseAnimation: Animation {
        TopFeedbackRhythm.pulseAnimation(reduceMotion: reduceMotion)
    }
    
    var body: some View {
        VStack(spacing: 24) {
            headerSection
            
            providersGrid
                .frame(maxWidth: 520)
            
            hintSection
            
            Spacer()
            
            navigationButtons
        }
        .padding(32)
    }
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            Text("onboarding.providers.title".localized())
                .font(.title2)
                .fontWeight(.bold)
            
            Text("onboarding.providers.subtitle".localized())
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
    
    private var providersGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 12) {
            ForEach(featuredProviders) { provider in
                ProviderPreviewCard(provider: provider)
            }
        }
    }
    
    private var featuredProviders: [AIProvider] {
        [.gemini, .claude, .codex, .copilot, .antigravity, .qwen]
    }
    
    private var hintSection: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundStyle(Color.semanticInfo)
                
                Text("onboarding.providers.hint".localized())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()

            Button {
                let names = featuredProviders.map(\.displayName).joined(separator: ", ")
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(names, forType: .string)
                copyFeedbackState = .success
                Task {
                    try? await Task.sleep(for: .milliseconds(TopFeedbackRhythm.pulseMilliseconds(reduceMotion: reduceMotion)))
                    await MainActor.run {
                        copyFeedbackState = .idle
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: copyFeedbackState == .success ? "checkmark.circle.fill" : "doc.on.doc")
                        .foregroundStyle(copyFeedbackState == .success ? Color.semanticSuccess : .secondary)
                    Text(
                        copyFeedbackState == .success
                        ? "status.copied".localized(fallback: "已复制")
                        : "action.copy".localized(fallback: "复制")
                    )
                }
                .font(.caption.weight(.medium))
            }
            .buttonStyle(.plain)
            .motionAwareAnimation(feedbackPulseAnimation, value: copyFeedbackState)
        }
        .padding(12)
        .background(Color.semanticSelectionFill)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    private var navigationButtons: some View {
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
                viewModel.goNext()
                guard !reduceMotion else {
                    continueFeedbackState = .idle
                    return
                }
                continueFeedbackState = .success
                Task {
                    try? await Task.sleep(for: .milliseconds(TopFeedbackRhythm.pulseMilliseconds(reduceMotion: reduceMotion)))
                    await MainActor.run {
                        continueFeedbackState = .idle
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text("onboarding.button.continue".localized())
                    ZStack {
                        Image(systemName: "arrow.right")
                            .opacity(continueFeedbackState == .success ? 0 : 1)
                        Image(systemName: "checkmark")
                            .opacity(continueFeedbackState == .success ? 1 : 0)
                            .foregroundStyle(Color.semanticSuccess)
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
    }
}

struct ProviderPreviewCard: View {
    let provider: AIProvider
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false
    
    var body: some View {
        VStack(spacing: 8) {
            ProviderIcon(provider: provider, size: 40)
            
            Text(provider.displayName)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .scaleEffect(isHovered && !reduceMotion ? QuotioMotion.Scale.hovered : 1.0)
        .motionAwareAnimation(QuotioMotion.hover, value: isHovered)
        .onHover { isHovered = $0 }
    }
}

#Preview {
    ProviderStep(viewModel: OnboardingViewModel())
}
