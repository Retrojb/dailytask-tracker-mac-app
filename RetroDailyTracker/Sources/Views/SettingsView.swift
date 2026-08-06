import SwiftUI
import SwiftData

struct SettingsView: View {

    // MARK: - Environment

    @Environment(\.modelContext) private var modelContext
    @Query private var configs: [SpreadsheetConfig]

    // MARK: - State

    @State private var selectedProvider: SpreadsheetProvider = .googleSheets
    @State private var spreadsheetURL: String = ""
    @State private var connectionStatus: ConnectionStatus = .disconnected
    @State private var isConnecting: Bool = false
    @State private var errorMessage: String?

    // MARK: - Dependencies

    private let spreadsheetService: SpreadsheetServiceProtocol

    // MARK: - Init

    init(spreadsheetService: SpreadsheetServiceProtocol = SpreadsheetService()) {
        self.spreadsheetService = spreadsheetService
    }

    // MARK: - Computed

    private var config: SpreadsheetConfig? {
        configs.first
    }

    private var lastSyncDateFormatted: String? {
        guard let date = config?.lastSyncDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private var providerDisplayName: String {
        switch selectedProvider {
        case .googleSheets:
            return "Google Sheets"
        case .microsoftExcel:
            return "Microsoft Excel"
        }
    }

    // MARK: - Body

    var body: some View {
        Form {
            spreadsheetProviderSection
            connectionSection
            statusSection
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .onAppear {
            loadExistingConfig()
        }
    }

    // MARK: - Sections

    private var spreadsheetProviderSection: some View {
        Section("Spreadsheet Provider") {
            Picker("Provider", selection: $selectedProvider) {
                Text("Google Sheets").tag(SpreadsheetProvider.googleSheets)
                Text("Microsoft Excel").tag(SpreadsheetProvider.microsoftExcel)
            }
            .pickerStyle(.segmented)

            TextField("Spreadsheet URL or Name", text: $spreadsheetURL)
                .textFieldStyle(.roundedBorder)
                .help("Enter the full URL or name of your \(providerDisplayName) spreadsheet")
        }
    }

    private var connectionSection: some View {
        Section("Connection") {
            HStack {
                Button(action: connect) {
                    if isConnecting {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.trailing, 4)
                        Text("Connecting...")
                    } else {
                        Text("Connect")
                    }
                }
                .disabled(spreadsheetURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isConnecting)

                Spacer()

                connectionStatusBadge
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
    }

    private var statusSection: some View {
        Section("Sync Status") {
            LabeledContent("Status") {
                Text(connectionStatus.displayText)
                    .foregroundStyle(connectionStatus.color)
            }

            if let lastSync = lastSyncDateFormatted {
                LabeledContent("Last Sync") {
                    Text(lastSync)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Subviews

    private var connectionStatusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(connectionStatus.color)
                .frame(width: 8, height: 8)
            Text(connectionStatus.displayText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions

    private func connect() {
        guard let url = URL(string: spreadsheetURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              !spreadsheetURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Please enter a valid spreadsheet URL."
            return
        }

        isConnecting = true
        errorMessage = nil
        connectionStatus = .disconnected

        Task {
            do {
                try await spreadsheetService.configure(provider: selectedProvider, spreadsheetURL: url)
                try await spreadsheetService.authenticate()

                await MainActor.run {
                    connectionStatus = .connected
                    isConnecting = false
                    saveConfig()
                }
            } catch {
                await MainActor.run {
                    connectionStatus = .error
                    errorMessage = "Connection failed: \(error.localizedDescription)"
                    isConnecting = false
                }
            }
        }
    }

    // MARK: - Persistence

    private func loadExistingConfig() {
        guard let existing = config else { return }

        if existing.provider == "googleSheets" {
            selectedProvider = .googleSheets
        } else if existing.provider == "microsoftExcel" {
            selectedProvider = .microsoftExcel
        }

        spreadsheetURL = existing.spreadsheetURL

        if existing.lastSyncDate != nil {
            connectionStatus = .connected
        }
    }

    private func saveConfig() {
        let providerString: String
        switch selectedProvider {
        case .googleSheets:
            providerString = "googleSheets"
        case .microsoftExcel:
            providerString = "microsoftExcel"
        }

        if let existing = config {
            existing.provider = providerString
            existing.spreadsheetURL = spreadsheetURL.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            let newConfig = SpreadsheetConfig(
                provider: providerString,
                spreadsheetURL: spreadsheetURL.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            modelContext.insert(newConfig)
        }

        do {
            try modelContext.save()
        } catch {
            errorMessage = "Failed to save settings: \(error.localizedDescription)"
        }
    }
}

// MARK: - Connection Status

enum ConnectionStatus {
    case connected
    case disconnected
    case error

    var displayText: String {
        switch self {
        case .connected:
            return "Connected"
        case .disconnected:
            return "Disconnected"
        case .error:
            return "Error"
        }
    }

    var color: Color {
        switch self {
        case .connected:
            return .green
        case .disconnected:
            return .secondary
        case .error:
            return .red
        }
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
        .modelContainer(for: SpreadsheetConfig.self, inMemory: true)
}
