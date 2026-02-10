import SwiftUI

struct ContentView: View {
    @ObservedObject var syncManager: SyncManager
    @ObservedObject var appLog = AppLog.shared
    @Environment(\.colorScheme) var colorScheme
    @State private var showHistory = false
    @State private var showConnectSheet = false
    @State private var showLogs = false
    @State private var manualIP = ""

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            if showLogs {
                logPanel
            } else if showHistory {
                historyPanel
            } else {
                editorArea
            }
            Divider()
            statusBar
        }
        .background(colorScheme == .dark ? Color(hex: "1C1C1E") : Color(hex: "FAFAFA"))
        .sheet(isPresented: $showConnectSheet) {
            connectByIPSheet
        }
    }

    private var connectByIPSheet: some View {
        VStack(spacing: 16) {
            Text("Connect by IP")
                .font(.system(size: 16, weight: .medium))

            Text("My IP: \(syncManager.localIPAddress)")
                .font(.system(size: 13))
                .foregroundColor(colorScheme == .dark ? Color(hex: "98989D") : Color(hex: "8E8E93"))

            TextField("Enter device IP address (e.g. 192.168.1.100)", text: $manualIP)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)

            if !syncManager.connectionStatus.isEmpty {
                HStack(spacing: 6) {
                    if syncManager.connectionStatus == "Connecting..." {
                        ProgressView()
                            .scaleEffect(0.6)
                    }
                    Text(syncManager.connectionStatus)
                        .font(.system(size: 12))
                        .foregroundColor(
                            syncManager.connectionStatus.hasPrefix("Connected") ? .green :
                            syncManager.connectionStatus.hasPrefix("Failed") ? .red :
                            (colorScheme == .dark ? Color(hex: "98989D") : Color(hex: "8E8E93"))
                        )
                }
            }

            HStack(spacing: 12) {
                Button("Cancel") {
                    showConnectSheet = false
                    manualIP = ""
                    syncManager.connectionStatus = ""
                }
                Button("Connect") {
                    let ip = manualIP.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !ip.isEmpty {
                        syncManager.connectByIP(ip)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(syncManager.connectionStatus == "Connecting...")
            }
        }
        .padding(24)
        .frame(minWidth: 380)
    }

    private var topBar: some View {
        HStack {
            Text("Macroid")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1C1C1E"))

            Spacer()

            Button(action: {
                showLogs = false
                showHistory.toggle()
            }) {
                Text(showHistory ? "Editor" : "History")
                    .font(.system(size: 13))
                    .foregroundColor(Color(hex: "4A90D9"))
            }
            .buttonStyle(.plain)

            Button(action: {
                showHistory = false
                showLogs.toggle()
            }) {
                Text("Logs")
                    .font(.system(size: 13))
                    .foregroundColor(showLogs ? .orange : Color(hex: "4A90D9"))
            }
            .buttonStyle(.plain)
            .padding(.leading, 4)

            Circle()
                .fill(syncManager.connectedDevice != nil ? Color.green : Color.red)
                .frame(width: 10, height: 10)
                .padding(.leading, 8)
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
    }

    private var logPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(appLog.entries.count) log entries")
                    .font(.system(size: 12))
                    .foregroundColor(colorScheme == .dark ? Color(hex: "98989D") : Color(hex: "8E8E93"))

                Spacer()

                Button("Copy All") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(appLog.allText(), forType: .string)
                }
                .font(.system(size: 12))
                .buttonStyle(.plain)
                .foregroundColor(Color(hex: "4A90D9"))

                Button("Clear") {
                    appLog.clear()
                }
                .font(.system(size: 12))
                .foregroundColor(.red)
                .buttonStyle(.plain)
                .padding(.leading, 8)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(appLog.entries.enumerated()), id: \.offset) { idx, entry in
                            Text(entry)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(
                                    entry.contains("ERROR") || entry.contains("FAILED") || entry.contains("TIMEOUT") ? .red :
                                    entry.contains("Connected") || entry.contains("pong OK") ? .green :
                                    (colorScheme == .dark ? Color(hex: "CCCCCC") : Color(hex: "333333"))
                                )
                                .textSelection(.enabled)
                                .id(idx)
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .onChange(of: appLog.entries.count) { _ in
                    if let last = appLog.entries.indices.last {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var editorArea: some View {
        VStack(spacing: 0) {
            if let imageData = syncManager.lastReceivedImage,
               let nsImage = NSImage(data: imageData) {
                VStack(spacing: 8) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 200)
                        .cornerRadius(8)
                        .onTapGesture {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setData(imageData, forType: .png)
                            if let tiffData = nsImage.tiffRepresentation {
                                NSPasteboard.general.setData(tiffData, forType: .tiff)
                            }
                            AppLog.add("[UI] Image copied to clipboard")
                        }
                    Text("Tap image to copy")
                        .font(.system(size: 11))
                        .foregroundColor(colorScheme == .dark ? Color(hex: "98989D") : Color(hex: "8E8E93"))
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }

            ZStack(alignment: .topLeading) {
                if syncManager.clipboardText.isEmpty && syncManager.lastReceivedImage == nil {
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
                    .onChange(of: syncManager.clipboardText) { newValue in
                        syncManager.onTextEdited(newValue)
                    }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var historyPanel: some View {
        VStack(spacing: 0) {
            if syncManager.clipboardHistory.isEmpty {
                Spacer()
                Text("No clipboard history yet")
                    .font(.system(size: 14))
                    .foregroundColor(
                        colorScheme == .dark
                            ? Color(hex: "98989D").opacity(0.5)
                            : Color(hex: "8E8E93").opacity(0.5)
                    )
                Spacer()
            } else {
                HStack {
                    Text("\(syncManager.clipboardHistory.count) items")
                        .font(.system(size: 12))
                        .foregroundColor(colorScheme == .dark ? Color(hex: "98989D") : Color(hex: "8E8E93"))

                    Spacer()

                    Button("Clear") {
                        syncManager.clearHistory()
                    }
                    .font(.system(size: 12))
                    .foregroundColor(.red)
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(syncManager.clipboardHistory.enumerated()), id: \.offset) { _, item in
                            historyRow(item)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func historyRow(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text)
                .font(.system(size: 13))
                .lineLimit(3)
                .foregroundColor(colorScheme == .dark ? Color(hex: "F2F2F7") : Color(hex: "1C1C1E"))

            Text("\(text.count) characters")
                .font(.system(size: 11))
                .foregroundColor(
                    colorScheme == .dark
                        ? Color(hex: "98989D").opacity(0.5)
                        : Color(hex: "8E8E93").opacity(0.5)
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            syncManager.restoreFromHistory(text)
            showHistory = false
        }
        .overlay(alignment: .bottom) {
            Divider().padding(.horizontal, 16)
        }
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

                Button(action: { showConnectSheet = true }) {
                    Text("Connect by IP")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "4A90D9"))
                }
                .buttonStyle(.plain)
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
