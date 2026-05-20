import SwiftUI
import UniformTypeIdentifiers
import FolderLockCore

struct ContentView: View {
    @EnvironmentObject var coordinator: OperationCoordinator
    @State private var isDropTargeted = false
    @State private var mixedDropWarning: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            dropZone
                .padding(12)
            Divider()
            activity
        }
        .sheet(item: $coordinator.pending) { pending in
            PasswordPromptView(
                pending: pending,
                onConfirm: { password in
                    coordinator.performPending(password: password)
                },
                onCancel: {
                    coordinator.cancelPending()
                }
            )
        }
        .alert("Mixed selection",
               isPresented: $mixedDropWarning,
               actions: { Button("OK", role: .cancel) {} },
               message: { Text("Drop only locked items, or only unlocked items, at a time.") })
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.shield.fill")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("FolderLock").font(.headline)
                Text("Password-protect any file or folder").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if coordinator.isWorking {
                ProgressView().controlSize(.small)
            }
        }
        .padding(12)
    }

    private var dropZone: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.rectangle.stack.fill")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("Drop items here to Lock")
                .font(.title3)
            Text("Drop .locked items to Unlock")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button("Choose to Lock…") { coordinator.promptOpenForLock() }
                Button("Choose to Unlock…") { coordinator.promptOpenForUnlock() }
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                    style: StrokeStyle(lineWidth: 2, dash: [8])
                )
        )
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
            return true
        }
    }

    private var activity: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Activity").font(.subheadline).bold()
                Spacer()
                if !coordinator.log.isEmpty {
                    Button("Clear") { coordinator.log.removeAll() }
                        .controlSize(.small)
                }
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(coordinator.log.reversed()) { entry in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: entry.isError ? "xmark.octagon.fill" : "checkmark.seal.fill")
                                .foregroundStyle(entry.isError ? .red : .green)
                            Text(entry.message)
                                .font(.callout)
                                .textSelection(.enabled)
                            Spacer()
                        }
                    }
                }
            }
            .frame(maxHeight: 160)
        }
        .padding(12)
    }

    private func handleDrop(providers: [NSItemProvider]) {
        let group = DispatchGroup()
        var collected: [URL] = []
        let lock = NSLock()
        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url = url {
                    lock.lock(); collected.append(url); lock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            guard !collected.isEmpty else { return }
            let locked = collected.filter { Locker.isLocked(url: $0) }
            let unlocked = collected.filter { !Locker.isLocked(url: $0) }
            if !locked.isEmpty && !unlocked.isEmpty {
                mixedDropWarning = true
                return
            }
            if !unlocked.isEmpty { coordinator.queueLock(urls: unlocked) }
            if !locked.isEmpty { coordinator.queueUnlock(urls: locked) }
        }
    }
}
