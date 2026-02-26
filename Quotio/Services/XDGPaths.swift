//
//  XDGPaths.swift
//  Quotio
//

import Foundation

enum XDGPaths {
    nonisolated static func dataHome(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path
    ) -> String {
        if let value = environment["XDG_DATA_HOME"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !value.isEmpty {
            return value
        }
        return "\(homeDirectory)/.local/share"
    }

    nonisolated static func fnmNodeVersionsBasePaths(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path
    ) -> [String] {
        let xdgDataHome = dataHome(environment: environment, homeDirectory: homeDirectory)
        return [
            "\(xdgDataHome)/fnm/node-versions",
            "\(homeDirectory)/.fnm/node-versions" // legacy path
        ]
    }
}
