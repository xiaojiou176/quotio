//
//  MotionAwareAnimation.swift
//  Quotio
//
//  Respect system reduce-motion preference for implicit SwiftUI animations.
//

import SwiftUI

enum QuotioMotionProfile: String, CaseIterable, Identifiable {
    case calm
    case crisp

    static let `default`: QuotioMotionProfile = .calm

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .calm:
            return "settings.motion.profile.calm"
        case .crisp:
            return "settings.motion.profile.crisp"
        }
    }
}

enum QuotioMotionProfileStorage {
    static let key = "ui.motion.profile"

    static var current: QuotioMotionProfile {
        get {
            guard
                let rawValue = UserDefaults.standard.string(forKey: key),
                let profile = QuotioMotionProfile(rawValue: rawValue)
            else {
                return .default
            }
            return profile
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
        }
    }
}

enum QuotioMotion {
    enum Duration {
        static var snappy: Double { QuotioMotion.duration(calm: 0.12, crisp: 0.1) }
        static var standard: Double { QuotioMotion.duration(calm: 0.2, crisp: 0.16) }
        static var smooth: Double { QuotioMotion.duration(calm: 0.28, crisp: 0.22) }
        static var pageEnter: Double { QuotioMotion.duration(calm: 0.34, crisp: 0.26) }
        static var pageExit: Double { QuotioMotion.duration(calm: 0.2, crisp: 0.15) }
        static var contentSwap: Double { QuotioMotion.duration(calm: 0.24, crisp: 0.18) }
        static var successEmphasis: Double { QuotioMotion.duration(calm: 0.34, crisp: 0.26) }
        static var gentleSpring: Double { QuotioMotion.duration(calm: 0.42, crisp: 0.3) }
        static var looping: Double { QuotioMotion.duration(calm: 0.5, crisp: 0.4) }
    }

    enum Scale {
        static let pressed: CGFloat = 0.98
        static let hovered: CGFloat = 1.01
    }

    enum Opacity {
        static let pressed: Double = 0.9
        static let hovered: Double = 0.98
    }

    static var currentProfile: QuotioMotionProfile {
        QuotioMotionProfileStorage.current
    }

    static var press: Animation { .easeInOut(duration: Duration.snappy) }
    static var hover: Animation { .easeInOut(duration: Duration.snappy) }
    static var appear: Animation {
        .spring(
            response: Duration.smooth,
            dampingFraction: currentProfile == .crisp ? 0.9 : 0.86,
            blendDuration: 0.1
        )
    }
    static var dismiss: Animation { .easeInOut(duration: Duration.standard) }
    static var pageEnter: Animation {
        if currentProfile == .crisp {
            return .timingCurve(0.2, 0.95, 0.25, 1.0, duration: Duration.pageEnter)
        }
        return .timingCurve(0.22, 1.0, 0.36, 1.0, duration: Duration.pageEnter)
    }
    static var pageExit: Animation {
        if currentProfile == .crisp {
            return .timingCurve(0.32, 0.02, 0.86, 0.94, duration: Duration.pageExit)
        }
        return .timingCurve(0.4, 0.0, 1.0, 1.0, duration: Duration.pageExit)
    }
    static var contentSwap: Animation { .easeInOut(duration: Duration.contentSwap) }
    static var looping: Animation { .easeInOut(duration: Duration.looping).repeatForever(autoreverses: true) }
    static var continuousLoop: Animation { .linear(duration: Duration.looping).repeatForever(autoreverses: false) }
    static var successEmphasis: Animation {
        .spring(
            response: Duration.successEmphasis,
            dampingFraction: currentProfile == .crisp ? 0.8 : 0.74,
            blendDuration: 0.12
        )
    }
    static var gentleSpring: Animation {
        .spring(
            response: Duration.gentleSpring,
            dampingFraction: currentProfile == .crisp ? 0.9 : 0.86,
            blendDuration: 0.12
        )
    }

    enum Transition {
        static func pageEnter(reduceMotion: Bool) -> AnyTransition {
            .opacity.combined(with: .offset(y: QuotioMotion.displacement(calm: 12, crisp: 8, reduceMotion: reduceMotion)))
        }

        static func pageExit(reduceMotion: Bool) -> AnyTransition {
            .opacity.combined(with: .offset(y: QuotioMotion.displacement(calm: 8, crisp: 6, reduceMotion: reduceMotion)))
        }

        static func contentSwap(reduceMotion: Bool) -> AnyTransition {
            .opacity.combined(with: .offset(y: QuotioMotion.displacement(calm: 10, crisp: 7, reduceMotion: reduceMotion)))
        }

        static func successEmphasis(reduceMotion: Bool) -> AnyTransition {
            let scale = reduceMotion ? 1 : (QuotioMotion.currentProfile == .crisp ? 0.992 : 0.985)
            return .opacity.combined(with: .scale(scale: scale))
        }

        static func gentleSpring(reduceMotion: Bool) -> AnyTransition {
            .opacity.combined(with: .offset(y: QuotioMotion.displacement(calm: 6, crisp: 4, reduceMotion: reduceMotion)))
        }
    }

    private static func duration(calm: Double, crisp: Double) -> Double {
        currentProfile == .crisp ? crisp : calm
    }

    private static func displacement(calm: CGFloat, crisp: CGFloat, reduceMotion: Bool) -> CGFloat {
        guard !reduceMotion else { return 0 }
        return currentProfile == .crisp ? crisp : calm
    }
}

private struct MotionAwareAnimationModifier<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let animation: Animation?
    let value: Value

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

private struct QuotioHoverFeedbackModifier: ViewModifier {
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let scale: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovered ? scale : 1)
            .opacity(isHovered ? opacity : 1)
            .onHover { hovering in
                withMotionAwareAnimation(QuotioMotion.hover, reduceMotion: reduceMotion) {
                    isHovered = hovering
                }
            }
    }
}

private struct QuotioAppearFeedbackModifier: ViewModifier {
    @State private var isVisible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let offsetY: CGFloat
    let initialOpacity: Double

    func body(content: Content) -> some View {
        content
            .offset(y: reduceMotion ? 0 : (isVisible ? 0 : offsetY))
            .opacity(reduceMotion ? 1 : (isVisible ? 1 : initialOpacity))
            .onAppear {
                guard !reduceMotion else {
                    isVisible = true
                    return
                }
                withMotionAwareAnimation(QuotioMotion.appear, reduceMotion: reduceMotion) {
                    isVisible = true
                }
            }
    }
}

extension View {
    /// Applies animation only when "Reduce Motion" is disabled in system accessibility settings.
    func motionAwareAnimation<Value: Equatable>(_ animation: Animation?, value: Value) -> some View {
        modifier(MotionAwareAnimationModifier(animation: animation, value: value))
    }

    /// Adds a subtle transform-only hover feedback for macOS pointer interactions.
    func quotioHoverFeedback(
        scale: CGFloat = QuotioMotion.Scale.hovered,
        opacity: Double = QuotioMotion.Opacity.hovered
    ) -> some View {
        modifier(QuotioHoverFeedbackModifier(scale: scale, opacity: opacity))
    }

    /// Adds transform-only press feedback while respecting Reduce Motion.
    func quotioPressFeedback(
        isPressed: Bool,
        pressedScale: CGFloat = QuotioMotion.Scale.pressed,
        pressedOpacity: Double = QuotioMotion.Opacity.pressed
    ) -> some View {
        self
            .scaleEffect(isPressed ? pressedScale : 1)
            .opacity(isPressed ? pressedOpacity : 1)
            .motionAwareAnimation(QuotioMotion.press, value: isPressed)
    }

    /// Adds a subtle reveal animation on first appearance.
    func quotioAppearFeedback(
        offsetY: CGFloat = -8,
        initialOpacity: Double = 0.2
    ) -> some View {
        modifier(QuotioAppearFeedbackModifier(offsetY: offsetY, initialOpacity: initialOpacity))
    }

    /// Applies a unified state-swap transition used by page-level loading/error/content switches.
    func quotioStateSwapTransition(reduceMotion: Bool) -> some View {
        transition(QuotioMotion.Transition.contentSwap(reduceMotion: reduceMotion))
    }
}

@MainActor
func withMotionAwareAnimation<Result>(
    _ animation: Animation,
    reduceMotion: Bool,
    _ updates: () -> Result
) -> Result {
    withAnimation(reduceMotion ? nil : animation, updates)
}
