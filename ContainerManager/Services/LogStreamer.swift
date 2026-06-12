//
//  LogStreamer.swift
//  ContainerManager
//

import Foundation
import Observation

/// Reads a log file handle into an observable text buffer and follows new output.
@Observable
final class LogStreamer {
    private(set) var text = ""
    private var task: Task<Void, Never>?
    private var handle: FileHandle?

    func start(handle: FileHandle) {
        stop()
        text = ""
        self.handle = handle
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let handle = self.handle else { return }
                // For log files availableData returns immediately: new bytes if the
                // file grew, or empty at EOF — in which case we poll for growth.
                let data = handle.availableData
                if !data.isEmpty {
                    self.text += String(decoding: data, as: UTF8.self)
                } else {
                    try? await Task.sleep(for: .milliseconds(500))
                }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        try? handle?.close()
        handle = nil
    }
}
