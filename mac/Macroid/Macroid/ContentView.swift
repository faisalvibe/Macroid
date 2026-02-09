import SwiftUI

struct ContentView: View {
    @ObservedObject var syncManager: SyncManager
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            editorArea
            Divider()
            statusBar
        }
        .background(colorScheme == .dark ? Color(hex: "1C1C1E") : Color(hex: "FAFAFA"))
    }

    private var topBar: some View {
        HStack {
            Text("Macroid")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1C1C1E"))

            Spacer()

            Circle()
                .fill(syncManager.connectedDevice != nil ? Color.green : Color.red)
                .frame(width: 10, height: 10)
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
    }

    private var editorArea: some View {
        ZStack(alignment: .topLeading) {
            if syncManager.clipboardText.isEmpty {
                Text("Copy something on either device...")
                    .foregroundColor(
                        colorScheme == .dark
                            ? Color(hex: "98989D").opacity(0.5)
                            : Color(hex: "8E8E93").opacity(0.5)
                    )
                    .font(.system(size: 15))
                    .padding(.top, 8)
                    .padding(.leading, 5)
            }

            TextEditor(text: $syncManager.clipboardText)
                .font(.system(size: 15))
                .lineSpacing(6)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .foregroundColor(colorScheme == .dark ? Color(hex: "F2F2F7") : Color(hex: "1C1C1E"))
                .onChange(of: syncManager.clipboardText) { _, newValue in
                    syncManager.onTextEdited(newValue)
                }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(syncManager.connectedDevice != nil ? Color.green : Color.red)
                .frame(width: 8, height: 8)

            if let device = syncManager.connectedDevice {
                Text("Connected to: \(device.alias)")
                    .font(.system(size: 12))
                    .foregroundColor(colorScheme == .dark ? Color(hex: "98989D") : Color(hex: "8E8E93"))

                Spacer()

                Text(device.address)
                    .font(.system(size: 12))
                    .foregroundColor(
                        colorScheme == .dark
                            ? Color(hex: "98989D").opacity(0.6)
                            : Color(hex: "8E8E93").opacity(0.6)
                    )
            } else {
                Text("Searching for devices...")
                    .font(.system(size: 12))
                    .foregroundColor(colorScheme == .dark ? Color(hex: "98989D") : Color(hex: "8E8E93"))

                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(colorScheme == .dark ? Color(hex: "2C2C2E") : Color(hex: "F2F2F7"))
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = ((int >> 24) & 0xFF, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
