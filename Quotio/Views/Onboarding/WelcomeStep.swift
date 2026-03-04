//
//  WelcomeStep.swift
//  Quotio - CLIProxyAPI GUI Wrapper
//

import SwiftUI

struct WelcomeStep: View {
    @Bindable var viewModel: OnboardingViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    private var welcomeRevealDelay: Duration {
        .milliseconds(max(1, TopFeedbackRhythm.pulseMilliseconds(reduceMotion: reduceMotion) / 4))
    }
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            if let appIcon = NSApp.applicationIconImage {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .shadow(color: Color.primary.opacity(0.1), radius: 8, y: 4)
                    .opacity(hasAppeared ? 1 : 0)
                    .scaleEffect(hasAppeared ? 1 : 0.96)
                    .offset(y: hasAppeared ? 0 : 10)
            }
            
            VStack(spacing: 12) {
                Text("onboarding.welcome.title".localized())
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("onboarding.welcome.subtitle".localized())
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared ? 0 : 8)
            
            Spacer()
            
            Button {
                viewModel.goNext()
            } label: {
                Text("onboarding.button.getStarted".localized())
                    .frame(minWidth: 160)
                    .padding(.horizontal, 20)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared ? 0 : 8)
        }
        .padding(32)
        .motionAwareAnimation(QuotioMotion.pageEnter, value: hasAppeared)
        .onAppear {
            if reduceMotion {
                hasAppeared = true
            } else {
                hasAppeared = false
                Task {
                    try? await Task.sleep(for: welcomeRevealDelay)
                    hasAppeared = true
                }
            }
        }
    }
}

#Preview {
    WelcomeStep(viewModel: OnboardingViewModel())
}
