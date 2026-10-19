import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section("New codes") {
                Toggle("Copy to clipboard automatically", isOn: $model.autoCopy)
                Toggle("Show a notification", isOn: $model.notify)
            }
            Section("Account") {
                LabeledContent("Signed in as", value: model.email ?? "Not signed in")
                if model.phase == .ready {
                    Button("Remove sync key from this Mac", action: model.forgetKey)
                }
                if model.email != nil {
                    Button("Sign out", role: .destructive, action: model.signOut)
                }
            }
        }
        .formStyle(.grouped)
        .padding(.vertical)
    }
}
