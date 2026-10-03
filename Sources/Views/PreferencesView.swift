import SwiftUI
import ServiceManagement

enum SettingsTab: Int {
    case general, servers, volumes, about
}

/// Toolbar-style settings window: each pane is a SwiftUI view hosted in its own tab item,
/// and the window title follows the selected pane.
final class SettingsTabViewController: NSTabViewController {
    private static let paneWidth: CGFloat = 520

    init(manager: NetworkDriveManager) {
        super.init(nibName: nil, bundle: nil)
        tabStyle = .toolbar
        addPane(GeneralSettingsView(), label: "General", symbol: "gearshape", height: 400)
        addPane(ServersSettingsView(manager: manager), label: "Servers", symbol: "externaldrive.connected.to.line.below", height: 420)
        addPane(VolumesSettingsView(), label: "Volumes", symbol: "internaldrive", height: 340)
        addPane(AboutView(), label: "About", symbol: "info.circle", height: 320)
    }

    required init?(coder: NSCoder) { fatalError() }

    func select(_ tab: SettingsTab) {
        selectedTabViewItemIndex = tab.rawValue
    }

    private func addPane<Content: View>(_ content: Content, label: String, symbol: String, height: CGFloat) {
        let controller = NSHostingController(rootView: content.frame(width: Self.paneWidth, height: height))
        controller.sizingOptions = .preferredContentSize
        // NSTabViewController propagates the selected child's title to the window.
        controller.title = label
        let item = NSTabViewItem(viewController: controller)
        item.label = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        addTabViewItem(item)
    }
}

private extension Binding where Value == Bool {
    /// Presents a stored "hide" flag as a positive "show" toggle without changing the stored key.
    var inverted: Binding<Bool> {
        Binding(get: { !wrappedValue }, set: { wrappedValue = !$0 })
    }
}

// MARK: - General

private struct GeneralSettingsView: View {
    @AppStorage("groupDrivesByHost")          private var groupDrivesByHost          = true
    @AppStorage("clickGroupToConnectAll")     private var clickGroupToConnectAll     = true
    @AppStorage("hideConnectedFromAvailable") private var hideConnectedFromAvailable = true
    @AppStorage("showHoverInfo")              private var showHoverInfo              = false

    @State private var loginItemEnabled = false
    @State private var showingResetConfirmation = false

    var body: some View {
        Form {
            Section {
                Toggle("Open at login", isOn: $loginItemEnabled)
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
                Text("You can also manage this in System Settings > General > Login Items.")
                    .foregroundStyle(.secondary)
            }

            Section("Menu") {
                Toggle("Group by host", isOn: $groupDrivesByHost.animation())
                if groupDrivesByHost {
                    Toggle("Connect all servers when clicking a host header", isOn: $clickGroupToConnectAll)
                }
                Toggle("Show connected servers in the server list", isOn: $hideConnectedFromAvailable.inverted)
                Toggle("Show details when hovering over an item", isOn: $showHoverInfo)
            }

            Section {
                Button("Reset…", role: .destructive) { showingResetConfirmation = true }
            } header: {
                Text("Reset")
            } footer: {
                Text("Deletes all settings and saved servers, removes the login item and quits MenuBarFS.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            loginItemEnabled = SMAppService.mainApp.status == .enabled
        }
        .confirmationDialog(
            "Reset MenuBarFS?",
            isPresented: $showingResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset and Quit", role: .destructive, action: resetAndQuit)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All settings and saved servers will be permanently deleted. This cannot be undone.")
        }
    }

    private func resetAndQuit() {
        try? SMAppService.mainApp.unregister()
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
        NSApp.terminate(nil)
    }
}

// MARK: - Servers

private struct ServersSettingsView: View {
    @ObservedObject var manager: NetworkDriveManager
    @State private var showAddSheet = false
    @State private var editingDrive: NetworkDrive?
    @State private var selection: UUID?

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
            .contextMenu(forSelectionType: UUID.self) { ids in
                if let drive = drive(for: ids) {
                    Button("Edit") { editingDrive = drive }
                    Button("Remove") { remove(drive) }
                }
            } primaryAction: { ids in
                editingDrive = drive(for: ids)
            }
            .overlay {
                if manager.drives.isEmpty {
                    ContentUnavailableView(
                        "No Servers",
                        systemImage: "externaldrive.connected.to.line.below",
                        description: Text("Click + to add a server.")
                    )
                }
            }

            Divider()

            HStack(spacing: 8) {
                Button(action: { showAddSheet = true }) {
                    Image(systemName: "plus")
                }
                Button(action: { if let drive = selectedDrive { remove(drive) } }) {
                    Image(systemName: "minus")
                }
                .disabled(selection == nil)

                Spacer()

                Button("Edit") { editingDrive = selectedDrive }
                .disabled(selection == nil)
            }
            .padding(8)
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
    }

    private var selectedDrive: NetworkDrive? {
        selection.flatMap { id in manager.drives.first { $0.id == id } }
    }

    private func drive(for ids: Set<UUID>) -> NetworkDrive? {
        guard ids.count == 1, let id = ids.first else { return nil }
        return manager.drives.first { $0.id == id }
    }

    private func remove(_ drive: NetworkDrive) {
        manager.remove(drive)
        if selection == drive.id { selection = nil }
    }
}

// MARK: - Volumes

private struct VolumesSettingsView: View {
    @AppStorage("hideLocalDrives")           private var hideLocalDrives           = false
    @AppStorage("clickVolumeToOpenInFinder") private var clickVolumeToOpenInFinder = true
    @AppStorage("showCapacityLine")          private var showCapacityLine          = true
    @AppStorage("showCapacityStats")         private var showCapacityStats         = true
    @AppStorage("hideCapacityForReadOnly")   private var hideCapacityForReadOnly   = true
    @AppStorage("useBinaryUnits")            private var useBinaryUnits            = false

    var body: some View {
        Form {
            Section("List") {
                Toggle("Show local volumes", isOn: $hideLocalDrives.inverted)
                Toggle("Open volumes in Finder when clicked", isOn: $clickVolumeToOpenInFinder)
            }
            Section("Capacity") {
                Toggle("Show capacity bar", isOn: $showCapacityLine.animation())
                if showCapacityLine {
                    Toggle("Show used and total capacity", isOn: $showCapacityStats)
                }
                Toggle("Show capacity for read-only volumes", isOn: $hideCapacityForReadOnly.inverted)
                Picker("Units", selection: $useBinaryUnits) {
                    Text("Decimal (KB, MB, GB, TB)").tag(false)
                    Text("Binary (KiB, MiB, GiB, TiB)").tag(true)
                }
                .pickerStyle(.radioGroup)
            }
        }
        .formStyle(.grouped)
    }
}
