//
//  ModeSelectionStep.swift
//  Quotio - CLIProxyAPI GUI Wrapper
//

import SwiftUI

struct ModeSelectionStep: View {
    @Bindable var viewModel: OnboardingViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var continueFeedbackState: OnboardingSubmissionFeedbackState = .idle
    
    private var feedbackPulseAnimation: Animation {
        TopFeedbackRhythm.pulseAnimation(reduceMotion: reduceMotion)
    }
    
    var body: some View {
        VStack(spacing: 24) {
            headerSection
            
            VStack(spacing: 12) {
                ForEach(OperatingMode.allCases) { mode in
                    OperatingModeCard(
                        mode: mode,
                        isSelected: viewModel.selectedMode == mode,
                        onSelect: { viewModel.selectedMode = mode }
                    )
                }
            }
            .frame(maxWidth: 520)
            
            Spacer()
            
            navigationButtons
        }
        .padding(48)
    }
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            Text("onboarding.mode.title".localized())
                .font(.title2)
                .fontWeight(.bold)
            
            Text("onboarding.mode.subtitle".localized())
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
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
                    .scaleEffect(continueFeedbackState == .success && !reduceMotion ? 1.08 : 1.0)
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

struct OperatingModeCard: View {
    let mode: OperatingMode
    let isSelected: Bool
    let onSelect: () -> Void
    
    @State private var isHovered = false
    @State private var selectionPulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isFocused: Bool
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                iconView
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(mode.displayName)
                            .font(.headline)
                        
                        if let badge = mode.badge {
                            Text(badge)
                                .font(.caption2)
                                .fontWeight(.medium)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                                .background(badgeColor.opacity(0.15))
                                .foregroundStyle(badgeColor)
                                .clipShape(Capsule())
                        }
                    }
                    
                    Text(mode.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? Color.semanticInfo : .secondary.opacity(0.4))
                    .scaleEffect(isSelected ? 1.08 : 1.0)
            }
            .padding(16)
            .background(backgroundView)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(borderColor, lineWidth: isSelected ? 2 : 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.accentColor.opacity(0.55), lineWidth: isFocused ? 2 : 0)
            )
            .scaleEffect(isHovered ? 1.01 : 1.0)
            .scaleEffect(selectionPulse && !reduceMotion ? 1.01 : 1.0)
            .motionAwareAnimation(QuotioMotion.hover, value: isHovered)
            .motionAwareAnimation(QuotioMotion.successEmphasis, value: isSelected)
            .motionAwareAnimation(QuotioMotion.contentSwap, value: isFocused)
            .motionAwareAnimation(TopFeedbackRhythm.pulseAnimation(reduceMotion: reduceMotion), value: selectionPulse)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .onHover { isHovered = $0 }
        .onChange(of: isSelected) { _, selected in
            guard selected else {
                selectionPulse = false
                return
            }
            guard !reduceMotion else {
                selectionPulse = false
                return
            }
            selectionPulse = true
            Task {
                try? await Task.sleep(for: .milliseconds(TopFeedbackRhythm.pulseMilliseconds(reduceMotion: reduceMotion)))
                await MainActor.run {
                    selectionPulse = false
                }
            }
        }
    }
    
    private var iconView: some View {
        Image(systemName: mode.icon)
            .font(.title2)
            .foregroundStyle(isSelected ? Color.semanticOnAccent : mode.color)
            .frame(width: 44, height: 44)
            .background(isSelected ? mode.color : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(mode.color, lineWidth: isSelected ? 0 : 2)
            )
    }
    
    private var badgeColor: Color {
        switch mode {
        case .monitor: return .semanticSuccess
        case .remoteProxy: return .semanticAccentSecondary
        default: return .gray
        }
    }
    
    private var borderColor: Color {
        if isSelected {
            return Color.accentColor
        } else if isFocused {
            return Color.accentColor.opacity(0.7)
        } else if isHovered {
            return Color.secondary.opacity(0.5)
        } else {
            return Color.secondary.opacity(0.2)
        }
    }
    
    @ViewBuilder
    private var backgroundView: some View {
        if isSelected {
            Color.accentColor.opacity(0.08)
        } else if isHovered {
            Color.secondary.opacity(0.05)
        } else {
            Color.clear
        }
    }
}

#Preview {
    ModeSelectionStep(viewModel: OnboardingViewModel())
}
