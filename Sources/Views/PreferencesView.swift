import SwiftUI

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
            GeneralTab()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
                .tag(1)
            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
                .tag(2)
        }
        .frame(width: 500, height: 490)
    }
}

// MARK: - Network Drives Tab

private struct NetworkDrivesTab: View {
    @ObservedObject var manager: NetworkDriveManager
    @State private var showAddSheet = false
    @State private var editingDrive: NetworkDrive?
    @State private var selection: UUID?

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(manager.drives) { drive in
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
        .sheet(isPresented: $showAddSheet) {
            DriveFormView(manager: manager, drive: nil)
        }
        .sheet(item: $editingDrive) { drive in
            DriveFormView(manager: manager, drive: drive)
        }
    }

    private func removeSelected() {
        guard let id = selection,
              let drive = manager.drives.first(where: { $0.id == id }) else { return }
        manager.remove(drive)
        selection = nil
    }
}

// MARK: - General Tab

private struct GeneralTab: View {
    @AppStorage("showCapacityLine")       private var showCapacityLine       = true
    @AppStorage("showCapacityStats")      private var showCapacityStats      = true
    @AppStorage("useBinaryUnits")         private var useBinaryUnits         = false
    @AppStorage("hideCapacityForReadOnly")  private var hideCapacityForReadOnly  = true

    var body: some View {
        Form {
            Section("Capacity Bar/Stats") {
                Toggle("Show capacity bar", isOn: $showCapacityLine)
                Toggle("Show capacity stats", isOn: $showCapacityStats)
                    .disabled(!showCapacityLine)
            }
            Section("Hide Capacity Bar/Stats For") {
                Toggle("Read-only volumes", isOn: $hideCapacityForReadOnly)
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
