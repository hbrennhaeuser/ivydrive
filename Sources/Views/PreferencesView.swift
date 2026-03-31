import SwiftUI

struct PreferencesView: View {
    @ObservedObject var manager: NetworkDriveManager
    @State private var showAddSheet = false
    @State private var editingDrive: NetworkDrive?
    @State private var selection: UUID?

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(manager.drives) { drive in
                    HStack {
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
        .frame(width: 500, height: 350)
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
