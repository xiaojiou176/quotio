//
//  ObservabilityModels.swift
//  Quotio
//
//  Shared state for linking usage and logs surfaces.
//

import Foundation

nonisolated struct ObservabilityFocusFilter: Codable, Sendable {
    let requestId: String?
    let model: String?
    let account: String?
    let source: String?
    let timestamp: Date?
    let origin: String

    init(
        requestId: String? = nil,
        model: String? = nil,
        account: String? = nil,
        source: String? = nil,
        timestamp: Date? = nil,
        origin: String
    ) {
        self.requestId = requestId
        self.model = model
        self.account = account
        self.source = source
        self.timestamp = timestamp
        self.origin = origin
    }
}
