import SwiftUI

struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch model.phase {
            case .ready where !model.codes.isEmpty:
                Text("Recent codes").font(.headline)
                ForEach(model.codes.prefix(5)) { item in
                    Button {
                        model.copy(item)
                    } label: {
                        HStack {
                            Text(item.code).font(.system(.title3, design: .monospaced).weight(.semibold))
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text(item.sender).font(.caption).lineLimit(1)
                                Text(item.receivedAt, format: .relative(presentation: .named))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Copy \(item.code)")
                }
                Text("Click a code to copy it").font(.caption2).foregroundStyle(.tertiary)
            case .ready:
                Text("No codes yet").foregroundStyle(.secondary)
            default:
                Text("Open OpenMessages to sign in and unlock sync.").foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                Button("Open window") {
                    openWindow(id: "main")
                    NSApp.activate()
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(12)
        .frame(width: 280)
    }
}
