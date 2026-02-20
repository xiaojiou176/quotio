//
//  CLIExecutor.swift
//  Quotio - CLIProxyAPI GUI Wrapper
//
//  Utility for executing CLI commands and parsing output
//  Used for quota-only mode to run commands like `claude /usage`, `codex /status`, etc.
//

import Foundation
import Darwin

/// Result of a CLI command execution
nonisolated struct CLIExecutionResult: Sendable {
    let output: String
    let errorOutput: String
    let exitCode: Int32
    let success: Bool
    
    var combinedOutput: String {
        if errorOutput.isEmpty {
            return output
        }
        return output + "\n" + errorOutput
    }
}

/// Utility actor for executing CLI commands
actor CLIExecutor {
    static let shared = CLIExecutor()
    
    private init() {}

    private func buildExecutionEnvironment(
        commandPath: String? = nil,
        overrides: [String: String]? = nil
    ) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let currentPathEntries = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
            .filter { !$0.isEmpty }
        let expandedSearchPaths = searchPaths.map { NSString(string: $0).expandingTildeInPath }
        let commandDirectory: [String]
        if let commandPath {
            commandDirectory = [URL(fileURLWithPath: commandPath).deletingLastPathComponent().path]
        } else {
            commandDirectory = []
        }
        let fallbackEntries = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ]

        var seen = Set<String>()
        let mergedPathEntries = (currentPathEntries + commandDirectory + expandedSearchPaths + fallbackEntries).filter { entry in
            guard !entry.isEmpty else { return false }
            if seen.contains(entry) {
                return false
            }
            seen.insert(entry)
            return true
        }
        environment["PATH"] = mergedPathEntries.joined(separator: ":")

        if let overrides {
            for (key, value) in overrides {
                environment[key] = value
            }
        }
        return environment
    }
    
    /// Common CLI binary paths to search
    /// NOTE: Only checks file existence (metadata), does NOT read file content
    private let searchPaths = [
        // System paths
        "/usr/local/bin",
        "/opt/homebrew/bin",
        "/usr/bin",
        // User local
        "~/.local/bin",
        // Package managers
        "~/.cargo/bin",          // Rust/Cargo
        "~/.bun/bin",            // Bun (gemini-cli)
        "~/.deno/bin",           // Deno
        "~/.npm-global/bin",     // npm global
        // Tool-specific
        "~/.opencode/bin",       // OpenCode
        // Version managers (static shim paths)
        "~/.volta/bin",          // Volta
        "~/.asdf/shims",         // asdf
        "~/.local/share/mise/shims", // mise
    ]
    
    // MARK: - Binary Detection
    
    /// Check if a CLI binary exists and return its path
    func findBinary(named name: String) -> String? {
        // First check if it's in PATH
        let whichResult = executeSync(command: "/usr/bin/which", arguments: [name])
        if whichResult.success, !whichResult.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return whichResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // Search common static paths
        for searchPath in searchPaths {
            let expandedPath = NSString(string: searchPath).expandingTildeInPath
            let binaryPath = (expandedPath as NSString).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: binaryPath) {
                return binaryPath
            }
        }
        
        // Search version manager paths (nvm, fnm)
        if let path = findInVersionManagerPaths(named: name) {
            return path
        }
        
        return nil
    }
    
    /// Find binary in version managers with versioned subdirectories
    private func findInVersionManagerPaths(named name: String) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let fileManager = FileManager.default
        
        // nvm: ~/.nvm/versions/node/v*/bin/
        let nvmBase = "\(home)/.nvm/versions/node"
        if let versions = try? fileManager.contentsOfDirectory(atPath: nvmBase) {
            for version in versions.sorted().reversed() {
                let binPath = "\(nvmBase)/\(version)/bin/\(name)"
                if fileManager.isExecutableFile(atPath: binPath) {
                    return binPath
                }
            }
        }
        
        // fnm: $XDG_DATA_HOME/fnm (defaults to ~/.local/share/fnm), then legacy ~/.fnm
        let xdgDataHome: String
        if let envValue = ProcessInfo.processInfo.environment["XDG_DATA_HOME"], !envValue.isEmpty {
            xdgDataHome = envValue
        } else {
            xdgDataHome = "\(home)/.local/share"
        }
        let fnmPaths = [
            "\(xdgDataHome)/fnm/node-versions",
            "\(home)/.fnm/node-versions"  // legacy path
        ]

        for fnmBase in fnmPaths {
            if let versions = try? fileManager.contentsOfDirectory(atPath: fnmBase), !versions.isEmpty {
                for version in versions.sorted().reversed() {
                    let binPath = "\(fnmBase)/\(version)/installation/bin/\(name)"
                    if fileManager.isExecutableFile(atPath: binPath) {
                        return binPath
                    }
                }
                break  // found fnm installation, skip legacy path
            }
        }
        
        return nil
    }
    
    /// Check if a CLI is installed
    func isCLIInstalled(name: String) -> Bool {
        return findBinary(named: name) != nil
    }
    
    // MARK: - Command Execution
    
    /// Execute a command synchronously with timeout
    func executeSync(
        command: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        workingDirectory: String? = nil,
        timeout: TimeInterval = 30
    ) -> CLIExecutionResult {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        process.environment = buildExecutionEnvironment(commandPath: command, overrides: environment)
        
        if let workDir = workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workDir)
        }
        
        do {
            try process.run()
            
            // Wait with timeout
            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.1)
            }
            
            if process.isRunning {
                process.terminate()
                return CLIExecutionResult(
                    output: "",
                    errorOutput: "Command timed out after \(Int(timeout)) seconds",
                    exitCode: -1,
                    success: false
                )
            }
            
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            
            let output = String(data: outputData, encoding: .utf8) ?? ""
            let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
            
            return CLIExecutionResult(
                output: output,
                errorOutput: errorOutput,
                exitCode: process.terminationStatus,
                success: process.terminationStatus == 0
            )
        } catch {
            return CLIExecutionResult(
                output: "",
                errorOutput: error.localizedDescription,
                exitCode: -1,
                success: false
            )
        }
    }
    
    /// Execute a command asynchronously
    func execute(
        command: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        workingDirectory: String? = nil,
        timeout: TimeInterval = 30
    ) async -> CLIExecutionResult {
        return await withCheckedContinuation { continuation in
            Task.detached {
                let result = await self.executeSync(
                    command: command,
                    arguments: arguments,
                    environment: environment,
                    workingDirectory: workingDirectory,
                    timeout: timeout
                )
                continuation.resume(returning: result)
            }
        }
    }
    
    /// Execute a CLI by name (auto-finds binary path)
    func executeCLI(
        name: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        timeout: TimeInterval = 30
    ) async -> CLIExecutionResult {
        guard let binaryPath = findBinary(named: name) else {
            return CLIExecutionResult(
                output: "",
                errorOutput: "CLI '\(name)' not found",
                exitCode: -1,
                success: false
            )
        }
        
        return await execute(
            command: binaryPath,
            arguments: arguments,
            environment: environment,
            timeout: timeout
        )
    }
    
    // MARK: - PTY Execution (for interactive commands)
    
    /// Execute command in a pseudo-terminal (PTY) - needed for some CLIs
    func executePTY(
        command: String,
        arguments: [String] = [],
        input: String? = nil,
        timeout: TimeInterval = 30
    ) async -> CLIExecutionResult {
        // Use script command to create a PTY
        // This is needed for CLIs that behave differently without a TTY
        let scriptArgs = ["-q", "/dev/null", command] + arguments
        
        return await execute(
            command: "/usr/bin/script",
            arguments: scriptArgs,
            timeout: timeout
        )
    }
    
    /// Execute a CLI command that expects interactive input
    func executeCLIWithInput(
        name: String,
        arguments: [String] = [],
        input: String,
        workingDirectory: String? = nil,
        timeout: TimeInterval = 30
    ) async -> CLIExecutionResult {
        guard let binaryPath = findBinary(named: name) else {
            return CLIExecutionResult(
                output: "",
                errorOutput: "CLI '\(name)' not found",
                exitCode: -1,
                success: false
            )
        }
        
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let inputPipe = Pipe()
        let outputHandle = outputPipe.fileHandleForReading
        let errorHandle = errorPipe.fileHandleForReading
        let captureQueue = DispatchQueue(label: "quotio.cliexecutor.capture")
        var outputData = Data()
        var errorData = Data()

        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.standardInput = inputPipe
        process.environment = buildExecutionEnvironment(commandPath: binaryPath)
        if let workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }

        func installReadabilityHandlers() {
            outputHandle.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else {
                    handle.readabilityHandler = nil
                    return
                }
                captureQueue.sync {
                    outputData.append(chunk)
                }
            }
            errorHandle.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else {
                    handle.readabilityHandler = nil
                    return
                }
                captureQueue.sync {
                    errorData.append(chunk)
                }
            }
        }

        func finalizeCapturedOutput() -> (String, String) {
            outputHandle.readabilityHandler = nil
            errorHandle.readabilityHandler = nil
            let remainingOutput = outputHandle.readDataToEndOfFile()
            let remainingError = errorHandle.readDataToEndOfFile()
            captureQueue.sync {
                outputData.append(remainingOutput)
                errorData.append(remainingError)
            }
            let output = String(data: outputData, encoding: .utf8) ?? ""
            let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
            return (output, errorOutput)
        }

        do {
            installReadabilityHandlers()
            try process.run()
            
            // Write input
            if let inputData = input.data(using: .utf8) {
                inputPipe.fileHandleForWriting.write(inputData)
            }
            inputPipe.fileHandleForWriting.closeFile()
            
            // Wait with timeout
            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning && Date() < deadline {
                do {
                    try await Task.sleep(nanoseconds: 100_000_000)
                } catch is CancellationError {
                    terminateProcessIfNeeded(process)
                    let (output, errorOutput) = finalizeCapturedOutput()
                    return CLIExecutionResult(
                        output: output,
                        errorOutput: errorOutput.isEmpty ? "Command cancelled" : errorOutput,
                        exitCode: -2,
                        success: false
                    )
                } catch {
                    terminateProcessIfNeeded(process)
                    let (output, errorOutput) = finalizeCapturedOutput()
                    return CLIExecutionResult(
                        output: output,
                        errorOutput: errorOutput.isEmpty ? error.localizedDescription : errorOutput,
                        exitCode: -1,
                        success: false
                    )
                }
            }
            
            if process.isRunning {
                if Task.isCancelled {
                    terminateProcessIfNeeded(process)
                    let (output, errorOutput) = finalizeCapturedOutput()
                    return CLIExecutionResult(
                        output: output,
                        errorOutput: errorOutput.isEmpty ? "Command cancelled" : errorOutput,
                        exitCode: -2,
                        success: false
                    )
                }
                terminateProcessIfNeeded(process)
                let (output, errorOutput) = finalizeCapturedOutput()
                return CLIExecutionResult(
                    output: output,
                    errorOutput: errorOutput.isEmpty ? "Command timed out" : errorOutput,
                    exitCode: -1,
                    success: false
                )
            }
            
            let (output, errorOutput) = finalizeCapturedOutput()
            
            return CLIExecutionResult(
                output: output,
                errorOutput: errorOutput,
                exitCode: process.terminationStatus,
                success: process.terminationStatus == 0
            )
        } catch {
            let (output, errorOutput) = finalizeCapturedOutput()
            return CLIExecutionResult(
                output: output,
                errorOutput: errorOutput.isEmpty ? error.localizedDescription : errorOutput,
                exitCode: -1,
                success: false
            )
        }
    }

    private func terminateProcessIfNeeded(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        let deadline = Date().addingTimeInterval(1.0)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
    }
}

// MARK: - Detected CLI Info

nonisolated struct DetectedCLI: Identifiable, Sendable {
    let id: String
    let name: String
    let displayName: String
    let binaryPath: String?
    let isInstalled: Bool
    let version: String?
    
    static let allKnownCLIs: [String: String] = [
        "claude": "Claude Code",
        "codex": "Codex",
        "cursor": "Cursor",
        "gemini": "Gemini CLI",
        "gh": "GitHub CLI",
        "copilot": "GitHub Copilot"
    ]
}

// MARK: - CLI Detection Service

actor CLIDetectionService {
    static let shared = CLIDetectionService()
    
    private let executor = CLIExecutor.shared
    
    private init() {}
    
    /// Detect all installed CLIs
    func detectInstalledCLIs() async -> [DetectedCLI] {
        var detectedCLIs: [DetectedCLI] = []
        
        for (cliName, displayName) in DetectedCLI.allKnownCLIs {
            let binaryPath = await executor.findBinary(named: cliName)
            let isInstalled = binaryPath != nil
            
            var version: String? = nil
            if isInstalled, let path = binaryPath {
                let versionResult = await executor.execute(command: path, arguments: ["--version"], timeout: 5)
                if versionResult.success {
                    version = versionResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
                        .components(separatedBy: "\n").first
                }
            }
            
            detectedCLIs.append(DetectedCLI(
                id: cliName,
                name: cliName,
                displayName: displayName,
                binaryPath: binaryPath,
                isInstalled: isInstalled,
                version: version
            ))
        }
        
        return detectedCLIs.sorted { $0.displayName < $1.displayName }
    }
    
    /// Check if Claude CLI is installed
    func isClaudeInstalled() async -> Bool {
        return await executor.isCLIInstalled(name: "claude")
    }
    
    /// Check if Codex CLI is installed
    func isCodexInstalled() async -> Bool {
        return await executor.isCLIInstalled(name: "codex")
    }
    
    /// Check if Gemini CLI is installed
    func isGeminiInstalled() async -> Bool {
        return await executor.isCLIInstalled(name: "gemini")
    }
    
    /// Check if Cursor is installed (check for app or CLI)
    func isCursorInstalled() async -> Bool {
        // Check for Cursor.app
        let appPaths = [
            "/Applications/Cursor.app",
            "~/Applications/Cursor.app"
        ]
        
        for path in appPaths {
            let expandedPath = NSString(string: path).expandingTildeInPath
            if FileManager.default.fileExists(atPath: expandedPath) {
                return true
            }
        }
        
        return false
    }
}
