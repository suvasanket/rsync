//
//  ProcessRunner.swift
//  rsync
//
//  Created by saihgupr on 2024-12-11.
//  Optimized for low RAM usage on 2026-09-25.
//

import Foundation

struct ProcessResult {
    let stdout: String
    let stderr: String
    let exitCode: Int32
    let wasCancelled: Bool
    
    var isSuccess: Bool { exitCode == 0 && !wasCancelled }
    
    init(stdout: String, stderr: String, exitCode: Int32, wasCancelled: Bool = false) {
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
        self.wasCancelled = wasCancelled
    }
}

/// Thread-safe capped buffer that retains the most recent output bytes to prevent RAM leaks during long operations.
private final class TailBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = ""
    private let maxCapacity: Int
    
    init(maxCapacity: Int = 16384) {
        self.maxCapacity = maxCapacity
    }
    
    func append(_ string: String) {
        lock.lock()
        defer { lock.unlock() }
        buffer.append(string)
        if buffer.count > maxCapacity {
            let overflow = buffer.count - maxCapacity
            buffer.removeFirst(overflow)
        }
    }
    
    var content: String {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }
}

actor ProcessRunner {
    static let shared = ProcessRunner()
    
    private var currentProcess: Process?
    
    private init() {}
    
    /// Terminate the currently running process
    func terminateCurrentProcess() {
        if let process = currentProcess, process.isRunning {
            process.terminate()
        }
    }
    
    func run(
        _ executablePath: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        currentDirectory: String? = nil
    ) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executablePath)
                process.arguments = arguments
                
                if let env = environment {
                    var processEnv = ProcessInfo.processInfo.environment
                    for (key, value) in env {
                        processEnv[key] = value
                    }
                    process.environment = processEnv
                }
                
                if let dir = currentDirectory {
                    process.currentDirectoryURL = URL(fileURLWithPath: dir)
                }
                
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe
                
                do {
                    try process.run()
                    process.waitUntilExit()
                    
                    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    
                    let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                    let stderr = String(data: stderrData, encoding: .utf8) ?? ""
                    
                    let result = ProcessResult(
                        stdout: stdout.trimmingCharacters(in: .whitespacesAndNewlines),
                        stderr: stderr.trimmingCharacters(in: .whitespacesAndNewlines),
                        exitCode: process.terminationStatus
                    )
                    
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Run a command with real-time output streaming (cancellable and memory-capped)
    func runWithProgress(
        _ executablePath: String,
        arguments: [String] = [],
        onOutput: @escaping @Sendable (String) -> Void
    ) async throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        
        // Store reference for cancellation
        currentProcess = process
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe
                
                // Memory-capped tail buffers (16KB max each)
                let stdoutBuffer = TailBuffer(maxCapacity: 16384)
                let stderrBuffer = TailBuffer(maxCapacity: 16384)
                
                var lastOutputTime = Date.distantPast
                var lastStreamedString = ""
                let outputLock = NSLock()
                
                stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty else { return }
                    if let str = String(data: data, encoding: .utf8), !str.isEmpty {
                        stdoutBuffer.append(str)
                        
                        // Throttle streaming callbacks to avoid flooding the main actor / UI run loop
                        outputLock.lock()
                        let now = Date()
                        lastStreamedString = str
                        if now.timeIntervalSince(lastOutputTime) >= 0.15 {
                            lastOutputTime = now
                            outputLock.unlock()
                            onOutput(str)
                        } else {
                            outputLock.unlock()
                        }
                    }
                }
                
                stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty else { return }
                    if let str = String(data: data, encoding: .utf8), !str.isEmpty {
                        stderrBuffer.append(str)
                    }
                }
                
                do {
                    try process.run()
                    process.waitUntilExit()
                    
                    // Clean up handlers
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                    
                    // Emit last piece of output if any so final percentage is received
                    outputLock.lock()
                    let finalStr = lastStreamedString
                    outputLock.unlock()
                    if !finalStr.isEmpty {
                        onOutput(finalStr)
                    }
                    
                    let wasCancelled = process.terminationReason == .uncaughtSignal
                    
                    let result = ProcessResult(
                        stdout: stdoutBuffer.content.trimmingCharacters(in: .whitespacesAndNewlines),
                        stderr: stderrBuffer.content.trimmingCharacters(in: .whitespacesAndNewlines),
                        exitCode: process.terminationStatus,
                        wasCancelled: wasCancelled
                    )
                    
                    Task {
                        await self?.clearCurrentProcess()
                    }
                    
                    continuation.resume(returning: result)
                } catch {
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                    Task {
                        await self?.clearCurrentProcess()
                    }
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func clearCurrentProcess() {
        currentProcess = nil
    }
}
