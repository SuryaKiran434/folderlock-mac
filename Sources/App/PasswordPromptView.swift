import SwiftUI
import FolderLockCore

struct PasswordPromptView: View {
    let pending: OperationCoordinator.Pending
    let onConfirm: (String) -> Void
    let onCancel: () -> Void

    @State private var password = ""
    @State private var confirm = ""
    @State private var showPassword = false
    @State private var localError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.headline)
            Text(subtitle).font(.callout).foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(pending.urls, id: \.self) { url in
                    HStack(spacing: 6) {
                        Image(systemName: iconName(for: url))
                            .foregroundStyle(.secondary)
                        Text(url.lastPathComponent)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .font(.callout)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))

            passwordField(placeholder: "Password", text: $password)
            if pending.mode == .lock {
                passwordField(placeholder: "Confirm password", text: $confirm)
            }

            Toggle("Show password", isOn: $showPassword)
                .toggleStyle(.checkbox)
                .controlSize(.small)

            if let err = localError {
                Text(err).foregroundStyle(.red).font(.callout)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button(pending.mode == .lock ? "Lock" : "Unlock") {
                    if validate() { onConfirm(password) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(password.isEmpty || (pending.mode == .lock && confirm.isEmpty))
            }
        }
        .padding(22)
        .frame(width: 440)
    }

    private var title: String {
        let n = pending.urls.count
        let suffix = n == 1 ? "" : "s"
        return pending.mode == .lock ? "Lock \(n) item\(suffix)" : "Unlock \(n) item\(suffix)"
    }

    private var subtitle: String {
        switch pending.mode {
        case .lock:
            return "Set a password to encrypt these items. Remember it — there is no recovery."
        case .unlock:
            return "Enter the password used to lock these items."
        }
    }

    @ViewBuilder
    private func passwordField(placeholder: String, text: Binding<String>) -> some View {
        if showPassword {
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
        } else {
            SecureField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func iconName(for url: URL) -> String {
        if Locker.isLocked(url: url) { return "lock.doc.fill" }
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        return isDir.boolValue ? "folder.fill" : "doc.fill"
    }

    private func validate() -> Bool {
        if pending.mode == .lock {
            if password != confirm {
                localError = "Passwords do not match."
                return false
            }
            if password.count < 4 {
                localError = "Password must be at least 4 characters."
                return false
            }
        }
        localError = nil
        return true
    }
}
