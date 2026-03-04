//
//  OnboardingFlow.swift
//  Quotio - CLIProxyAPI GUI Wrapper
//
//  Multi-step onboarding wizard for new users
//

import SwiftUI

private nonisolated func localizedStepTitle(_ key: String, fallback: String) -> String {
    let value = key.localizedStatic()
    return value == key ? fallback : value
}

enum OnboardingStep: Int, CaseIterable {
    case welcome = 0
    case modeSelection = 1
    case remoteSetup = 2
    case providers = 3
    case completion = 4
    
    var title: String {
        switch self {
        case .welcome: return localizedStepTitle("onboarding.step.welcome", fallback: "欢迎")
        case .modeSelection: return localizedStepTitle("onboarding.step.mode", fallback: "模式")
        case .remoteSetup: return localizedStepTitle("onboarding.step.remote", fallback: "远程")
        case .providers: return localizedStepTitle("onboarding.step.providers", fallback: "提供商")
        case .completion: return localizedStepTitle("onboarding.step.completion", fallback: "完成")
        }
    }
}

@MainActor
@Observable
final class OnboardingViewModel {
    var currentStep: OnboardingStep = .welcome
    var selectedMode: OperatingMode = .monitor
    var remoteEndpoint: String = ""
    var remoteManagementKey: String = ""
    var remoteSetupErrorMessage: String?
    var completionErrorMessage: String?
    var isCompleting = false
    var direction: SlideDirection = .forward
    @ObservationIgnored private let modeManager = OperatingModeManager.shared
    
    var visibleSteps: [OnboardingStep] {
        if selectedMode == .remoteProxy {
            return [.welcome, .modeSelection, .remoteSetup, .providers, .completion]
        } else {
            return [.welcome, .modeSelection, .providers, .completion]
        }
    }
    
    var currentStepIndex: Int {
        visibleSteps.firstIndex(of: currentStep) ?? 0
    }
    
    var totalSteps: Int {
        visibleSteps.count
    }
    
    var canGoBack: Bool {
        currentStepIndex > 0
    }
    
    var canGoNext: Bool {
        switch currentStep {
        case .welcome:
            return true
        case .modeSelection:
            return true
        case .remoteSetup:
            return isRemoteConfigValid
        case .providers:
            return true
        case .completion:
            return true
        }
    }
    
    var isRemoteConfigValid: Bool {
        let validation = RemoteURLValidator.validate(remoteEndpoint)
        return validation.isValid && !remoteManagementKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    func goNext() {
        if currentStep == .remoteSetup {
            let trimmedKey = remoteManagementKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedKey.isEmpty {
                remoteSetupErrorMessage = "onboarding.remote.managementKey.required".localized(
                    fallback: "请输入 Management Key。"
                )
                return
            }
            remoteManagementKey = trimmedKey
            remoteEndpoint = RemoteURLValidator.sanitize(remoteEndpoint)
            remoteSetupErrorMessage = nil
        }

        direction = .forward
        let currentIndex = currentStepIndex
        if currentIndex < visibleSteps.count - 1 {
            currentStep = visibleSteps[currentIndex + 1]
        }
    }
    
    func goBack() {
        direction = .backward
        let currentIndex = currentStepIndex
        if currentIndex > 0 {
            currentStep = visibleSteps[currentIndex - 1]
        }
    }
    
    func completeOnboarding() {
        if selectedMode == .remoteProxy {
            let config = RemoteConnectionConfig(
                endpointURL: remoteEndpoint,
                displayName: "Remote Server"
            )
            modeManager.switchToRemote(config: config, managementKey: remoteManagementKey, fromOnboarding: true)
        } else {
            modeManager.completeOnboarding(mode: selectedMode)
        }
    }

    func completeOnboardingWithValidation() async -> Bool {
        completionErrorMessage = nil
        guard selectedMode == .remoteProxy else {
            completeOnboarding()
            return true
        }

        let sanitizedEndpoint = RemoteURLValidator.sanitize(remoteEndpoint)
        let endpointValidation = RemoteURLValidator.validate(sanitizedEndpoint)
        guard endpointValidation.isValid else {
            completionErrorMessage = endpointValidation.errorMessage
                ?? "remote.test.cannotConnect".localized(fallback: "连接验证失败")
            return false
        }

        let trimmedKey = remoteManagementKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            completionErrorMessage = "onboarding.remote.managementKey.required".localized(
                fallback: "请输入 Management Key。"
            )
            return false
        }

        isCompleting = true
        defer { isCompleting = false }

        let config = RemoteConnectionConfig(
            endpointURL: sanitizedEndpoint,
            displayName: "Remote Server"
        )
        let client = ManagementAPIClient(config: config, managementKey: trimmedKey)
        defer {
            Task { await client.invalidate() }
        }

        let isConnected = await client.checkProxyResponding()
        guard isConnected else {
            completionErrorMessage = "remote.test.cannotConnect".localized(
                fallback: "连接验证失败，请检查地址或 Management Key。"
            )
            return false
        }

        remoteEndpoint = sanitizedEndpoint
        remoteManagementKey = trimmedKey
        completeOnboarding()
        return true
    }
}

enum SlideDirection {
    case forward
    case backward
}

enum OnboardingSubmissionFeedbackState: Equatable {
    case idle
    case busy
    case success
    case failure
}

struct OnboardingFlow: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var viewModel = OnboardingViewModel()
    
    var onComplete: (() -> Void)?
    
    var body: some View {
        VStack(spacing: 0) {
            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(viewModel.currentStep)
                .transition(slideTransition)
                .motionAwareAnimation(QuotioMotion.contentSwap, value: viewModel.currentStep)
            
            progressIndicator
                .padding(.bottom, 24)
        }
        .frame(minWidth: 640, idealWidth: 640, minHeight: 560, idealHeight: 560)
    }
    
    @ViewBuilder
    private var stepContent: some View {
        switch viewModel.currentStep {
        case .welcome:
            WelcomeStep(viewModel: viewModel)
        case .modeSelection:
            ModeSelectionStep(viewModel: viewModel)
        case .remoteSetup:
            RemoteSetupStep(viewModel: viewModel)
        case .providers:
            ProviderStep(viewModel: viewModel)
        case .completion:
            CompletionStep(viewModel: viewModel) {
                let didComplete = await viewModel.completeOnboardingWithValidation()
                guard didComplete else { return }
                onComplete?()
                dismiss()
            }
        }
    }
    
    private var slideTransition: AnyTransition {
        let insertionOffset: CGFloat = reduceMotion ? 0 : 32
        let removalOffset: CGFloat = reduceMotion ? 0 : 24
        let insertionScale: CGFloat = reduceMotion ? 1.0 : 0.98
        let removalScale: CGFloat = reduceMotion ? 1.0 : 1.02

        switch viewModel.direction {
        case .forward:
            return .asymmetric(
                insertion: .modifier(
                    active: StepTransitionModifier(
                        opacity: 0,
                        scale: insertionScale,
                        xOffset: insertionOffset
                    ),
                    identity: StepTransitionModifier(opacity: 1, scale: 1, xOffset: 0)
                ),
                removal: .modifier(
                    active: StepTransitionModifier(
                        opacity: 0,
                        scale: removalScale,
                        xOffset: -removalOffset
                    ),
                    identity: StepTransitionModifier(opacity: 1, scale: 1, xOffset: 0)
                )
            )
        case .backward:
            return .asymmetric(
                insertion: .modifier(
                    active: StepTransitionModifier(
                        opacity: 0,
                        scale: insertionScale,
                        xOffset: -insertionOffset
                    ),
                    identity: StepTransitionModifier(opacity: 1, scale: 1, xOffset: 0)
                ),
                removal: .modifier(
                    active: StepTransitionModifier(
                        opacity: 0,
                        scale: removalScale,
                        xOffset: removalOffset
                    ),
                    identity: StepTransitionModifier(opacity: 1, scale: 1, xOffset: 0)
                )
            )
        }
    }
    
    private var progressIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<viewModel.totalSteps, id: \.self) { index in
                Circle()
                    .fill(index <= viewModel.currentStepIndex ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)
                    .scaleEffect(index == viewModel.currentStepIndex ? 1.25 : 1.0)
                    .opacity(index == viewModel.currentStepIndex ? 1.0 : 0.75)
                    .motionAwareAnimation(QuotioMotion.contentSwap, value: viewModel.currentStepIndex)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("onboarding.progress".localized(fallback: "引导进度"))
        .accessibilityValue(
            String(
                format: "onboarding.progress.stepOfTotal".localized(fallback: "第 %d 步，共 %d 步"),
                viewModel.currentStepIndex + 1,
                viewModel.totalSteps
            )
        )
    }
}

private struct StepTransitionModifier: ViewModifier {
    let opacity: Double
    let scale: CGFloat
    let xOffset: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .scaleEffect(scale)
            .offset(x: xOffset)
    }
}

#Preview {
    OnboardingFlow()
}
