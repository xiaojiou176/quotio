//
//  MotionAwareAnimation.swift
//  Quotio
//
//  Respect system reduce-motion preference for implicit SwiftUI animations.
//

import SwiftUI

private struct MotionAwareAnimationModifier<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let animation: Animation
    let value: Value

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

extension View {
    /// Applies animation only when "Reduce Motion" is disabled in system accessibility settings.
    func motionAwareAnimation<Value: Equatable>(_ animation: Animation, value: Value) -> some View {
        modifier(MotionAwareAnimationModifier(animation: animation, value: value))
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
