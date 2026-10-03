import SwiftUI

struct DriveFormView: View {
    @ObservedObject var manager: NetworkDriveManager
    @Environment(\.dismiss) private var dismiss

    let drive: NetworkDrive?

    @State private var driveType: DriveType = .smb

    // Structured fields (assembled into a URI on save)
    @State private var host = ""
    @State private var share = ""        // SMB, AFP
    @State private var exportPath = ""  // NFS
    @State private var ftpUser = ""     // FTP
    @State private var ftpPath = ""     // FTP
    @State private var port = ""
    @State private var rawURL = ""      // Other

    // Common fields
    @State private var label = ""
    @State private var checkHostReachability = false
    @State private var checkDNSResolution = false
    @State private var checkPortAvailability = false
    @State private var autoConnectOnStartup = false
    @State private var autoConnectOnNetworkChange = false

    private var isEditing: Bool { drive != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(isEditing ? "Edit Server" : "Add Server")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 4)

            Form {
                Section {
                    Picker("Protocol", selection: $driveType) {
                        ForEach(DriveType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .disabled(isEditing)
                    .onChange(of: driveType) { _, _ in
                        if !isEditing { clearTypeSpecificFields() }
                    }
                    typeSpecificFields
                    TextField("Display name", text: $label, prompt: Text("Optional"))
                } header: {
                    Text("Server")
                } footer: {
                    Text("The display name defaults to host/share.")
                        .foregroundStyle(.secondary)
                }

                Section("Connect Automatically") {
                    Toggle("When MenuBarFS starts", isOn: $autoConnectOnStartup)
                    Toggle("When the network changes", isOn: $autoConnectOnNetworkChange)
                }

                Section("Availability Checks") {
                    Toggle("Network is available", isOn: $checkHostReachability)
                    Toggle("Hostname resolves (DNS)", isOn: $checkDNSResolution)
                    Toggle("Port is open", isOn: $checkPortAvailability)
                }
            }
            .formStyle(.grouped)
            .frame(minHeight: 480)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(isEditing ? "Save" : "Add") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
            .padding(.top, 12)
        }
        .padding(20)
        .frame(width: 460)
        .onAppear(perform: populateFields)
    }

    @ViewBuilder
    private var typeSpecificFields: some View {
        switch driveType {
        case .smb:
            TextField("Host", text: $host, prompt: Text("server.local"))
            TextField("Share", text: $share, prompt: Text("ShareName"))
            TextField("Port", text: $port, prompt: Text("445 (optional)"))
        case .nfs:
            TextField("Host", text: $host, prompt: Text("server.local"))
            TextField("Export path", text: $exportPath, prompt: Text("/exports/data"))
            TextField("Port", text: $port, prompt: Text("2049 (optional)"))
        case .ftp:
            TextField("Host", text: $host, prompt: Text("ftp.server.com"))
            TextField("Username", text: $ftpUser, prompt: Text("anonymous (optional)"))
            TextField("Path", text: $ftpPath, prompt: Text("/pub (optional)"))
            TextField("Port", text: $port, prompt: Text("21 (optional)"))
        case .afp:
            TextField("Host", text: $host, prompt: Text("server.local"))
            TextField("Share", text: $share, prompt: Text("ShareName (optional)"))
            TextField("Port", text: $port, prompt: Text("548 (optional)"))
        case .other:
            TextField("Server Address", text: $rawURL, prompt: Text("smb://server/share"))
            if rawURLContainsPassword {
                Text("Remove the password from the server address. macOS asks for credentials when connecting and stores them in the Keychain.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        if driveType != .other {
            if !host.isEmpty && assembledURL == nil {
                validationMessage("Enter a valid host name.")
            }
            if !isPortValid {
                validationMessage("Port must be between 1 and 65535.")
            }
        }
    }

    private func validationMessage(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.red)
    }

    private var autoConnect: Bool {
        autoConnectOnStartup || autoConnectOnNetworkChange
    }

    private var isValid: Bool {
        switch driveType {
        case .smb:          return !host.isEmpty && !share.isEmpty && isPortValid && assembledURL != nil
        case .nfs:          return !host.isEmpty && !exportPath.isEmpty && isPortValid && assembledURL != nil
        case .ftp, .afp:    return !host.isEmpty && isPortValid && assembledURL != nil
        case .other:
            guard let url = URL(string: trimmedRawURL), url.scheme != nil else { return false }
            return !rawURLContainsPassword
        }
    }

    private var isPortValid: Bool {
        port.isEmpty || (Int(port).map { (1...65535).contains($0) } ?? false)
    }

    private var trimmedRawURL: String {
        rawURL.trimmingCharacters(in: .whitespaces)
    }

    // Drive URLs are persisted in plain text in UserDefaults, so embedded
    // passwords are rejected; credentials belong in the macOS Keychain.
    private var rawURLContainsPassword: Bool {
        URL(string: trimmedRawURL)?.password != nil
    }

    // URLComponents percent-encodes user, host and path, so share names with
    // spaces or special characters produce a valid URL.
    private var assembledURL: String? {
        if driveType == .other { return trimmedRawURL }

        var components = URLComponents()
        components.host = host.trimmingCharacters(in: .whitespaces)
        components.port = Int(port)
        switch driveType {
        case .smb:
            components.scheme = "smb"
            let cleanShare = share.hasPrefix("/") ? String(share.dropFirst()) : share
            components.path = "/\(cleanShare)"
        case .nfs:
            components.scheme = "nfs"
            components.path = exportPath.hasPrefix("/") ? exportPath : "/\(exportPath)"
        case .ftp:
            components.scheme = "ftp"
            components.user = ftpUser.isEmpty ? nil : ftpUser
            components.path = ftpPath.isEmpty ? "" : (ftpPath.hasPrefix("/") ? ftpPath : "/\(ftpPath)")
        case .afp:
            components.scheme = "afp"
            components.path = share.isEmpty ? "" : "/\(share)"
        case .other:
            break
        }
        return components.url?.absoluteString
    }

    private func clearTypeSpecificFields() {
        host = ""; share = ""; exportPath = ""
        ftpUser = ""; ftpPath = ""; port = ""; rawURL = ""
    }

    private func populateFields() {
        guard let drive else { return }
        driveType = drive.driveType
        label = drive.label ?? ""
        checkHostReachability = drive.checkHostReachability
        checkDNSResolution = drive.checkDNSResolution
        checkPortAvailability = drive.checkPortAvailability
        autoConnectOnStartup = drive.autoConnect && drive.autoConnectOnStartup
        autoConnectOnNetworkChange = drive.autoConnect && drive.autoConnectOnNetworkChange

        guard driveType != .other,
              let parsed = URL(string: drive.url),
              let parsedHost = parsed.host else {
            // Fall back to raw URI editing if parsing fails or type is Other.
            driveType = .other
            rawURL = drive.url
            return
        }

        host = parsedHost
        port = parsed.port.map { String($0) } ?? ""
        switch driveType {
        case .smb, .afp:
            share = parsed.pathComponents.dropFirst().first ?? ""
        case .nfs:
            exportPath = parsed.path
        case .ftp:
            ftpUser = parsed.user ?? ""
            ftpPath = parsed.path
        case .other:
            break
        }
    }

    private func save() {
        guard let finalURL = assembledURL else { return }
        let trimmedLabel = label.trimmingCharacters(in: .whitespaces)

        if var existing = drive {
            existing.url       = finalURL
            existing.driveType = driveType
            existing.label     = trimmedLabel.isEmpty ? nil : trimmedLabel
            existing.checkHostReachability  = checkHostReachability
            existing.checkDNSResolution     = checkDNSResolution
            existing.checkPortAvailability  = checkPortAvailability
            existing.autoConnect            = autoConnect
            existing.autoConnectOnStartup   = autoConnectOnStartup
            existing.autoConnectOnNetworkChange = autoConnectOnNetworkChange
            manager.update(existing)
        } else {
            manager.add(NetworkDrive(
                id: UUID(),
                url: finalURL,
                driveType: driveType,
                label: trimmedLabel.isEmpty ? nil : trimmedLabel,
                checkHostReachability: checkHostReachability,
                checkDNSResolution: checkDNSResolution,
                checkPortAvailability: checkPortAvailability,
                autoConnect: autoConnect,
                autoConnectOnStartup: autoConnectOnStartup,
                autoConnectOnNetworkChange: autoConnectOnNetworkChange
            ))
        }
        dismiss()
    }
}
