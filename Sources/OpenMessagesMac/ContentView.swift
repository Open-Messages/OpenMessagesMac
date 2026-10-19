import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            switch model.phase {
            case .missingConfig(let message):
                Message(
                    symbol: "gearshape.2",
                    title: "Firebase isn't configured",
                    text: message
                )
            case .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .signedOut:
                SignInView()
            case .noKeyOnAccount:
                Message(
                    symbol: "iphone.and.arrow.forward",
                    title: "Set up sync on your phone first",
                    text: "In Messages on your Android phone, open Settings › OTP sync, sign in with \(model.email ?? "this account") and create a sync key. Then come back here.",
                    action: ("Check again", model.refresh)
                )
            case .needsKey:
                UnlockView()
            case .ready:
                CodeListView()
            }
        }
        .toolbar {
            if model.busy {
                ToolbarItem { ProgressView().controlSize(.small) }
            }
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } }),
            presenting: model.errorMessage
        ) { _ in
            Button("OK") {}
        } message: { Text($0) }
    }
}

private struct Message: View {
    let symbol: String
    let title: String
    let text: String
    var action: (String, () -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 44)).foregroundStyle(.secondary)
            Text(title).font(.title2.weight(.semibold))
            Text(text).multilineTextAlignment(.center).foregroundStyle(.secondary).textSelection(.enabled)
            if let action { Button(action.0, action: action.1) }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SignInView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "key.viewfinder").font(.system(size: 52)).foregroundStyle(.tint)
            Text("Verification codes from your phone").font(.title2.weight(.semibold))
            Text("Sign in with the same Google account you use for OTP sync in Messages on your Android phone.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button {
                model.signIn()
            } label: {
                Text("Sign in with Google").frame(minWidth: 180)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .disabled(model.busy)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct UnlockView: View {
    @Environment(AppModel.self) private var model
    @State private var passphrase = ""

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill").font(.system(size: 44)).foregroundStyle(.secondary)
            Text("Enter your sync key").font(.title2.weight(.semibold))
            Text("Find it on your phone in Messages › Settings › OTP sync › Show sync key. Codes are decrypted only on this Mac.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            SecureField("XXXX-XXXX-XXXX-XXXX-XXXX", text: $passphrase)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: 300)
                .onSubmit(unlock)
            HStack {
                Button("Sign out", action: model.signOut)
                Button("Unlock", action: unlock)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(passphrase.trimmingCharacters(in: .whitespaces).isEmpty || model.busy)
            }
            Text("Signed in as \(model.email ?? "unknown")").font(.footnote).foregroundStyle(.tertiary)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func unlock() {
        model.unlock(passphrase: passphrase)
    }
}

struct CodeListView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmDeleteAll = false

    var body: some View {
        Group {
            if model.codes.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tray").font(.system(size: 40)).foregroundStyle(.secondary)
                    Text("No codes yet").font(.title3.weight(.semibold))
                    Text("New verification codes from your phone appear here within a few seconds.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .padding(32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(model.codes) { item in
                    CodeRow(item: item)
                        .contextMenu {
                            Button("Copy code") { model.copy(item) }
                            Button("Copy message") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(item.body, forType: .string)
                            }
                            Divider()
                            Button("Delete", role: .destructive) { model.delete(item) }
                        }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Text(model.email ?? "").lineLimit(1)
                Spacer()
                if let last = model.lastSync {
                    Text("Updated \(last.formatted(date: .omitted, time: .standard))")
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.horizontal)
            .padding(.vertical, 6)
            .background(.bar)
        }
        .toolbar {
            ToolbarItemGroup {
                Button { model.refresh() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    .keyboardShortcut("r")
                Button { confirmDeleteAll = true } label: { Label("Delete all", systemImage: "trash") }
                    .disabled(model.codes.isEmpty)
            }
        }
        .confirmationDialog("Delete all synced codes?", isPresented: $confirmDeleteAll) {
            Button("Delete all", role: .destructive, action: model.deleteAll)
        } message: {
            Text("They'll be removed from the server for every device.")
        }
    }
}

struct CodeRow: View {
    @Environment(AppModel.self) private var model
    let item: OtpItem
    @State private var copied = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.code)
                    .font(.system(size: 24, weight: .semibold, design: .monospaced))
                    .textSelection(.enabled)
                Text(item.sender).font(.subheadline.weight(.medium))
                Text(item.body).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Text(item.receivedAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(copied ? "Copied" : "Copy") {
                    model.copy(item)
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        copied = false
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }
}
