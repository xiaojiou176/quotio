//
//  UIExperienceSettings.swift
//  Quotio
//
//  UI density and accessibility preference settings.
//

import Foundation
import SwiftUI

enum InformationDensity: String, CaseIterable, Identifiable, Codable {
    case comfortable = "comfortable"
    case compact = "compact"

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .comfortable: return "settings.density.comfortable"
        case .compact: return "settings.density.compact"
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .comfortable: return 24
        case .compact: return 16
        }
    }

    var verticalSpacing: CGFloat {
        switch self {
        case .comfortable: return 16
        case .compact: return 10
        }
    }
}

@MainActor
@Observable
final class UIExperienceSettingsManager {
    static let shared = UIExperienceSettingsManager()

    private let defaults = UserDefaults.standard
    private let highContrastKey = "ui.highContrastEnabled"
    private let largerTextKey = "ui.largerTextEnabled"
    private let visibleFocusRingKey = "ui.visibleFocusRingEnabled"
    private let informationDensityKey = "ui.informationDensity"
    private let capturePayloadEvidenceKey = "ui.captureRequestPayloadEvidence"

    var highContrastEnabled: Bool {
        didSet { defaults.set(highContrastEnabled, forKey: highContrastKey) }
    }

    var largerTextEnabled: Bool {
        didSet { defaults.set(largerTextEnabled, forKey: largerTextKey) }
    }

    var visibleFocusRingEnabled: Bool {
        didSet { defaults.set(visibleFocusRingEnabled, forKey: visibleFocusRingKey) }
    }

    var informationDensity: InformationDensity {
        didSet { defaults.set(informationDensity.rawValue, forKey: informationDensityKey) }
    }

    var captureRequestPayloadEvidence: Bool {
        didSet { defaults.set(captureRequestPayloadEvidence, forKey: capturePayloadEvidenceKey) }
    }

    var recommendedMinimumRowHeight: CGFloat {
        largerTextEnabled ? 36 : 28
    }

    private init() {
        self.highContrastEnabled = defaults.bool(forKey: highContrastKey)

        if defaults.object(forKey: largerTextKey) == nil {
            defaults.set(false, forKey: largerTextKey)
        }
        self.largerTextEnabled = defaults.bool(forKey: largerTextKey)

        if defaults.object(forKey: visibleFocusRingKey) == nil {
            defaults.set(true, forKey: visibleFocusRingKey)
        }
        self.visibleFocusRingEnabled = defaults.bool(forKey: visibleFocusRingKey)

        let savedDensity = defaults.string(forKey: informationDensityKey) ?? InformationDensity.comfortable.rawValue
        self.informationDensity = InformationDensity(rawValue: savedDensity) ?? .comfortable

        if defaults.object(forKey: capturePayloadEvidenceKey) == nil {
            defaults.set(true, forKey: capturePayloadEvidenceKey)
        }
        self.captureRequestPayloadEvidence = defaults.bool(forKey: capturePayloadEvidenceKey)
    }
}
