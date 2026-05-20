import Foundation
import AppKit
import SwiftUI
import FolderLockCore

@MainActor
final class OperationCoordinator: ObservableObject {
    static let shared = OperationCoordinator()

    enum Mode: String { case lock, unlock }

    struct Pending: Identifiable, Equatable {
        let id = UUID()
        let mode: Mode
        let urls: [URL]
    }

    struct LogEntry: Identifiable, Equatable {
        let id = UUID()
        let timestamp: Date
        let message: String
        let isError: Bool
    }

    @Published var pending: Pending?
    @Published var log: [LogEntry] = []
    @Published var isWorking: Bool = false

    private init() {}

    // MARK: - Incoming URLs

    func handleIncoming(url: URL) {
        if url.isFileURL {
            if Locker.isLocked(url: url) {
                queueUnlock(urls: [url])
            } else {
                queueLock(urls: [url])
            }
            return
        }
        guard url.scheme == "folderlock" else { return }
        let action = url.host ?? ""
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let paths: [URL] = comps?.queryItems?
            .filter { $0.name == "path" }
            .compactMap { $0.value }
            .map { URL(fileURLWithPath: $0) } ?? []
        guard !paths.isEmpty else { return }
        switch action {
        case "lock":   queueLock(urls: paths)
        case "unlock": queueUnlock(urls: paths)
        default:       break
        }
    }

    // MARK: - Queuing

    func queueLock(urls: [URL]) {
        guard !urls.isEmpty else { return }
        if pending != nil { return }
        pending = Pending(mode: .lock, urls: urls)
    }

    func queueUnlock(urls: [URL]) {
        guard !urls.isEmpty else { return }
        if pending != nil { return }
        pending = Pending(mode: .unlock, urls: urls)
    }

    func cancelPending() {
        pending = nil
    }

    // MARK: - Execution

    func performPending(password: String) {
        guard let active = pending else { return }
        let mode = active.mode
        let urls = active.urls
        self.pending = nil
        self.isWorking = true

        Task.detached(priority: .userInitiated) { [weak self] in
            var results: [(URL, Result<URL, Error>)] = []
            for url in urls {
                do {
                    let out: URL
                    switch mode {
                    case .lock:   out = try Locker.lock(itemAt: url, password: password)
                    case .unlock: out = try Locker.unlock(itemAt: url, password: password)
                    }
                    results.append((url, .success(out)))
                } catch {
                    results.append((url, .failure(error)))
                }
            }
            await MainActor.run {
                guard let self = self else { return }
                self.isWorking = false
                for (input, result) in results {
                    switch result {
                    case .success(let out):
                        let verb = mode == .lock ? "Locked" : "Unlocked"
                        let msg = "\(verb) \(input.lastPathComponent) → \(out.lastPathComponent)"
                        self.log.append(LogEntry(timestamp: Date(), message: msg, isError: false))
                    case .failure(let err):
                        let msg = "\(input.lastPathComponent): \(err.localizedDescription)"
                        self.log.append(LogEntry(timestamp: Date(), message: msg, isError: true))
                    }
                }
            }
        }
    }

    // MARK: - Open panels

    func promptOpenForLock() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Lock"
        panel.message = "Choose files or folders to lock"
        if panel.runModal() == .OK {
            queueLock(urls: panel.urls)
        }
    }

    func promptOpenForUnlock() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Unlock"
        panel.message = "Choose .locked items to unlock"
        if panel.runModal() == .OK {
            queueUnlock(urls: panel.urls)
        }
    }
}
