import SwiftUI

struct DriveFormView: View {
    @ObservedObject var manager: NetworkDriveManager
    @Environment(\.dismiss) private var dismiss

    let drive: NetworkDrive?

    @State private var url = ""
    @State private var label = ""
    @State private var username = ""
    @State private var password = ""

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

                Divider()

                Text("Credentials (optional)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("Username", text: $username)
                    .textFieldStyle(.roundedBorder)

                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
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
        if let creds = KeychainHelper.load(for: drive.id) {
            username = creds.username
            password = creds.password
        }
    }

    private func save() {
        let trimmedURL = url.trimmingCharacters(in: .whitespaces)
        let trimmedLabel = label.trimmingCharacters(in: .whitespaces)

        if var existing = drive {
            existing.url = trimmedURL
            existing.label = trimmedLabel.isEmpty ? nil : trimmedLabel
            manager.update(existing)
            saveCredentials(for: existing.id)
        } else {
            let newDrive = NetworkDrive(
                id: UUID(),
                url: trimmedURL,
                label: trimmedLabel.isEmpty ? nil : trimmedLabel,
                autoConnect: false
            )
            manager.add(newDrive)
            saveCredentials(for: newDrive.id)
        }
        dismiss()
    }

    private func saveCredentials(for id: UUID) {
        let trimmedUser = username.trimmingCharacters(in: .whitespaces)
        if !trimmedUser.isEmpty {
            KeychainHelper.save(Credentials(username: trimmedUser, password: password), for: id)
        } else {
            KeychainHelper.delete(for: id)
        }
    }
}
