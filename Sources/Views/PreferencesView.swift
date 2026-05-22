import SwiftUI
import ServiceManagement

final class PreferencesViewModel: ObservableObject {
    @Published var selectedTab: Int = 0
}

struct PreferencesView: View {
    @ObservedObject var manager: NetworkDriveManager
    @ObservedObject var viewModel: PreferencesViewModel

    var body: some View {
        TabView(selection: $viewModel.selectedTab) {
            NetworkDrivesTab(manager: manager)
                .tabItem {
                    Label("Network Drives", systemImage: "externaldrive.connected.to.line.below")
                }
                .tag(0)
            AppearanceTab()
                .tabItem {
                    Label("Appearance", systemImage: "paintbrush")
                }
                .tag(1)
            GeneralTab()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
                .tag(2)
            MaintenanceTab()
                .tabItem {
                    Label("Maintenance", systemImage: "wrench.and.screwdriver")
                }
                .tag(3)
            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
                .tag(4)
        }
        .frame(width: 620, height: 490)
    }
}

// MARK: - Network Drives Tab

private struct NetworkDrivesTab: View {
    @ObservedObject var manager: NetworkDriveManager
    @State private var showAddSheet = false
    @State private var editingDrive: NetworkDrive?
    @State private var selection: UUID?
    @State private var eventMonitor: Any?

    private var groupedDrives: [(host: String, drives: [NetworkDrive])] {
        var groups: [String: [NetworkDrive]] = [:]
        for drive in manager.drives {
            groups[drive.hostGroupKey, default: []].append(drive)
        }
        return groups
            .map { key, drives in
                let host = URL(string: key)?.host ?? key
                let sorted = drives.sorted {
                    $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
                }
                return (host, sorted)
            }
            .sorted { $0.host.localizedStandardCompare($1.host) == .orderedAscending }
    }

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(groupedDrives, id: \.host) { group in
                    Section(group.host) {
                        ForEach(group.drives) { drive in
                            driveRow(drive)
                        }
                    }
                }
            }

            Divider()

            HStack(spacing: 8) {
                Button(action: { showAddSheet = true }) {
                    Image(systemName: "plus")
                }
                Button(action: removeSelected) {
                    Image(systemName: "minus")
                }
                .disabled(selection == nil)

                Spacer()

                Button("Edit") {
                    if let id = selection,
                       let drive = manager.drives.first(where: { $0.id == id }) {
                        editingDrive = drive
                    }
                }
                .disabled(selection == nil)
            }
            .padding(8)
        }
        .onAppear {
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
                guard event.clickCount == 2,
                      let id = selection,
                      let drive = manager.drives.first(where: { $0.id == id })
                else { return event }
                DispatchQueue.main.async { editingDrive = drive }
                return event
            }
        }
        .onDisappear {
            if let m = eventMonitor { NSEvent.removeMonitor(m) }
            eventMonitor = nil
        }
        .sheet(isPresented: $showAddSheet) {
            DriveFormView(manager: manager, drive: nil)
        }
        .sheet(item: $editingDrive) { drive in
            DriveFormView(manager: manager, drive: drive)
        }
    }

    @ViewBuilder
    private func driveRow(_ drive: NetworkDrive) -> some View {
        HStack(spacing: 10) {
            Text(drive.schemeLabel)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .fixedSize()
            VStack(alignment: .leading, spacing: 2) {
                Text(drive.displayName)
                    .fontWeight(.medium)
                Text(drive.url)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .tag(drive.id)
        .contextMenu {
            Button("Edit") { editingDrive = drive }
            Button("Remove") { manager.remove(drive) }
        }
    }

    private func removeSelected() {
        guard let id = selection,
              let drive = manager.drives.first(where: { $0.id == id }) else { return }
        manager.remove(drive)
        selection = nil
    }
}

// MARK: - Appearance Tab

private struct AppearanceTab: View {
    @AppStorage("showCapacityLine")        private var showCapacityLine        = true
    @AppStorage("showCapacityStats")       private var showCapacityStats       = true
    @AppStorage("useBinaryUnits")          private var useBinaryUnits          = false
    @AppStorage("hideCapacityForReadOnly") private var hideCapacityForReadOnly = true

    var body: some View {
        Form {
            Section("Capacity Bar") {
                Toggle("Show capacity bar", isOn: $showCapacityLine)
                Toggle("Show capacity stats", isOn: $showCapacityStats)
                    .disabled(!showCapacityLine)
                Toggle("Hide for read-only volumes", isOn: $hideCapacityForReadOnly)
            }
            Section("Units") {
                Picker("Capacity units", selection: $useBinaryUnits) {
                    Text("Decimal (KB, MB, GB, TB)").tag(false)
                    Text("Binary (KiB, MiB, GiB, TiB)").tag(true)
                }
                .pickerStyle(.radioGroup)
            }
        }
        .formStyle(.grouped)
        .padding(.top, 8)
    }
}

// MARK: - General Tab

private struct GeneralTab: View {
    @AppStorage("groupDrivesByHost")            private var groupDrivesByHost            = true
    @AppStorage("hideConnectedFromAvailable")  private var hideConnectedFromAvailable  = true
    @AppStorage("showHoverInfo")               private var showHoverInfo               = false
    @AppStorage("hideLocalDrives")             private var hideLocalDrives             = false
    @AppStorage("clickGroupToConnectAll")      private var clickGroupToConnectAll      = true
    @AppStorage("clickVolumeToOpenInFinder")   private var clickVolumeToOpenInFinder   = true

    var body: some View {
        Form {
            Section("Network Drive List") {
                Toggle("Group drives by host", isOn: $groupDrivesByHost)
                Toggle("Click group header to connect all", isOn: $clickGroupToConnectAll)
                    .disabled(!groupDrivesByHost)
                Toggle("Hide connected drives from available list", isOn: $hideConnectedFromAvailable)
                Toggle("Hide local drives from connected list", isOn: $hideLocalDrives)
            }
            Section("Connected Drives") {
                Toggle("Click to open in Finder", isOn: $clickVolumeToOpenInFinder)
            }
            Section("Hover") {
                Toggle("Show drive info on hover", isOn: $showHoverInfo)
            }
        }
        .formStyle(.grouped)
        .padding(.top, 8)
    }
}

// MARK: - Maintenance Tab

private struct MaintenanceTab: View {
    @State private var loginItemEnabled: Bool = false
    @State private var showingResetConfirmation = false

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $loginItemEnabled)
                    .onChange(of: loginItemEnabled) { _, enabled in
                        if enabled {
                            try? SMAppService.mainApp.register()
                        } else {
                            try? SMAppService.mainApp.unregister()
                        }
                    }
            } header: {
                Text("Startup")
            } footer: {
                Text("Automatically start MenuBarFS when you log in. You can also manage this in System Settings → General → Login Items.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Button(role: .destructive, action: { showingResetConfirmation = true }) {
                    Label("Reset All Settings", systemImage: "trash")
                }
            } header: {
                Text("Data Management")
            } footer: {
                Text("Removes all preferences and saved drives. The app will quit immediately.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.top, 8)
        .onAppear {
            loginItemEnabled = SMAppService.mainApp.status == .enabled
        }
        .confirmationDialog(
            "Reset All Settings",
            isPresented: $showingResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset and Quit", role: .destructive) {
                if let bundleID = Bundle.main.bundleIdentifier {
                    UserDefaults.standard.removePersistentDomain(forName: bundleID)
                }
                NSApp.terminate(nil)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All settings and saved drives will be permanently deleted. This cannot be undone.")
        }
    }
}
