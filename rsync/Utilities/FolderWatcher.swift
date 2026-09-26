//
//  FolderWatcher.swift
//  rsync
//
//  Created by Pair Programming on 2026-09-25.
//

import Foundation
import CoreServices
import Darwin

final class FolderWatcher: @unchecked Sendable {
    let folderId: UUID
    let path: String
    private let ignoredPatterns: [String]
    private let debounceDelay: TimeInterval
    private let onChange: @Sendable () -> Void
    
    private var stream: FSEventStreamRef?
    private let queue: DispatchQueue
    private let queueKey = DispatchSpecificKey<Void>()
    private var debounceWorkItem: DispatchWorkItem?
    private var isStarted = false
    
    init(
        folderId: UUID,
        path: String,
        ignoredPatterns: [String] = [],
        debounceDelay: TimeInterval = 2.0,
        onChange: @escaping @Sendable () -> Void
    ) {
        self.folderId = folderId
        self.path = path
        self.ignoredPatterns = ignoredPatterns
        self.debounceDelay = debounceDelay
        self.onChange = onChange
        self.queue = DispatchQueue(label: "com.rsync.watcher.\(folderId.uuidString)", qos: .utility)
        self.queue.setSpecific(key: queueKey, value: ())
    }
    
    deinit {
        stop()
    }
    
    func start() {
        runOnQueue { [weak self] in
            guard let self = self, !self.isStarted else { return }
            
            guard FileManager.default.fileExists(atPath: self.path) else {
                print("FolderWatcher: path does not exist: \(self.path)")
                return
            }
            
            var context = FSEventStreamContext(
                version: 0,
                info: Unmanaged.passUnretained(self).toOpaque(),
                retain: nil,
                release: nil,
                copyDescription: nil
            )
            
            let pathsToWatch = [self.path] as CFArray
            let flags = UInt32(
                kFSEventStreamCreateFlagFileEvents |
                kFSEventStreamCreateFlagNoDefer
            )
            
            let callback: FSEventStreamCallback = { streamRef, clientCallBackInfo, numEvents, eventPaths, eventFlags, eventIds in
                guard let clientCallBackInfo = clientCallBackInfo else { return }
                let watcher = Unmanaged<FolderWatcher>.fromOpaque(clientCallBackInfo).takeUnretainedValue()
                watcher.handleRawEvents(numEvents: numEvents, eventPaths: eventPaths)
            }
            
            guard let stream = FSEventStreamCreate(
                kCFAllocatorDefault,
                callback,
                &context,
                pathsToWatch,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                0.3,
                flags
            ) else {
                print("FolderWatcher: failed to create FSEventStream for \(self.path)")
                return
            }
            
            self.stream = stream
            FSEventStreamSetDispatchQueue(stream, self.queue)
            
            if FSEventStreamStart(stream) {
                self.isStarted = true
                print("FolderWatcher: started watching \(self.path)")
            } else {
                print("FolderWatcher: failed to start FSEventStream for \(self.path)")
                FSEventStreamInvalidate(stream)
                FSEventStreamRelease(stream)
                self.stream = nil
            }
        }
    }
    
    func stop() {
        runOnQueueSync { [weak self] in
            guard let self = self, self.isStarted, let stream = self.stream else { return }
            
            self.debounceWorkItem?.cancel()
            self.debounceWorkItem = nil
            
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
            self.isStarted = false
            print("FolderWatcher: stopped watching \(self.path)")
        }
    }
    
    private func runOnQueue(_ block: @escaping () -> Void) {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            block()
        } else {
            queue.async(execute: block)
        }
    }
    
    private func runOnQueueSync(_ block: () -> Void) {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            block()
        } else {
            queue.sync(execute: block)
        }
    }
    
    private func handleRawEvents(numEvents: Int, eventPaths: UnsafeMutableRawPointer) {
        let paths = eventPaths.assumingMemoryBound(to: UnsafePointer<CChar>.self)
        var hasRelevantChange = false
        
        for i in 0..<numEvents {
            let changedPath = String(cString: paths[i])
            
            // Skip the root folder itself
            if changedPath == self.path || changedPath == self.path + "/" {
                continue
            }
            
            let filename = URL(fileURLWithPath: changedPath).lastPathComponent
            
            // Skip system metadata and temporary files
            if filename == ".DS_Store" || filename.hasPrefix("._") || filename == ".localized" {
                continue
            }
            
            // Skip .git directory
            if changedPath.contains("/.git/") || changedPath.hasSuffix("/.git") {
                continue
            }
            
            // Check user ignored patterns
            let relativePath = changedPath.hasPrefix(self.path)
                ? String(changedPath.dropFirst(self.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                : changedPath
            
            if isIgnored(relativePath: relativePath, filename: filename) {
                continue
            }
            
            hasRelevantChange = true
            break
        }
        
        if hasRelevantChange {
            scheduleDebouncedTrigger()
        }
    }
    
    private func isIgnored(relativePath: String, filename: String) -> Bool {
        for pattern in ignoredPatterns {
            let clean = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
            if clean.isEmpty || clean.hasPrefix("#") { continue }
            
            let trimmedPattern = clean.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            
            if fnmatch(trimmedPattern, filename, 0) == 0 {
                return true
            }
            if fnmatch(trimmedPattern, relativePath, 0) == 0 {
                return true
            }
            if relativePath.hasPrefix(trimmedPattern) {
                return true
            }
        }
        return false
    }
    
    private func scheduleDebouncedTrigger() {
        debounceWorkItem?.cancel()
        
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self, self.isStarted else { return }
            print("FolderWatcher: debounced change trigger fired for \(self.path)")
            self.onChange()
        }
        
        self.debounceWorkItem = workItem
        queue.asyncAfter(deadline: .now() + debounceDelay, execute: workItem)
    }
}
