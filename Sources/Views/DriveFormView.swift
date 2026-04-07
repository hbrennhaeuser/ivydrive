import SwiftUI

struct DriveFormView: View {
    @ObservedObject var manager: NetworkDriveManager
    @Environment(\.dismiss) private var dismiss

    let drive: NetworkDrive?

    @State private var url = ""
    @State private var label = ""
    @State private var checkHostReachability = false
    @State private var checkDNSResolution = false
    @State private var checkPortAvailability = false

    private var isEditing: Bool { drive != nil }

    var body: some View {
        VStack(spacing: 16) {
            Text(isEditing ? "Edit Network Drive" : "Add Network Drive")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("URL")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("smb://server/share", text: $url)
                    .textFieldStyle(.roundedBorder)

                Text("Display Name")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Optional — defaults to hostname", text: $label)
                    .textFieldStyle(.roundedBorder)

            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Availability Checks")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Check host reachability (ping)", isOn: $checkHostReachability)
                Toggle("Check DNS resolution", isOn: $checkDNSResolution)
                Toggle("Check port availability", isOn: $checkPortAvailability)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(isEditing ? "Save" : "Add") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(url.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400)
        .onAppear(perform: populateFields)
    }

    private func populateFields() {
        guard let drive else { return }
        url = drive.url
        label = drive.label ?? ""
        checkHostReachability = drive.checkHostReachability
        checkDNSResolution = drive.checkDNSResolution
        checkPortAvailability = drive.checkPortAvailability
    }

    private func save() {
        let trimmedURL = url.trimmingCharacters(in: .whitespaces)
        let trimmedLabel = label.trimmingCharacters(in: .whitespaces)

        if var existing = drive {
            existing.url = trimmedURL
            existing.label = trimmedLabel.isEmpty ? nil : trimmedLabel
            existing.checkHostReachability = checkHostReachability
            existing.checkDNSResolution = checkDNSResolution
            existing.checkPortAvailability = checkPortAvailability
            manager.update(existing)
        } else {
            let newDrive = NetworkDrive(
                id: UUID(),
                url: trimmedURL,
                label: trimmedLabel.isEmpty ? nil : trimmedLabel,
                autoConnect: false,
                checkHostReachability: checkHostReachability,
                checkDNSResolution: checkDNSResolution,
                checkPortAvailability: checkPortAvailability
            )
            manager.add(newDrive)
        }
        dismiss()
    }
}
