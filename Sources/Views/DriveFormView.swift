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
    @State private var advancedExpanded = false

    private var isEditing: Bool { drive != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(isEditing ? "Edit Network Drive" : "Add Network Drive")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 4)

            Form {
                Section("Protocol") {
                    Picker("Protocol", selection: $driveType) {
                        ForEach(DriveType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .disabled(isEditing)
                    .onChange(of: driveType) { _, _ in
                        if !isEditing { clearTypeSpecificFields() }
                    }
                }

                Section("Connection") {
                    typeSpecificFields
                }

                Section("Display") {
                    TextField("Display Name", text: $label,
                              prompt: Text("Optional — defaults to host/share"))
                }

                Section(
                    content: {
                        if advancedExpanded {
                            Text("Autoconnect")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text("Autoconnect coming soon.")
                                .foregroundStyle(.tertiary)
                                .italic()
                            Text("Availability Checks")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Toggle("Check host reachability", isOn: $checkHostReachability)
                            Toggle("Check DNS resolution", isOn: $checkDNSResolution)
                            Toggle("Check port availability", isOn: $checkPortAvailability)
                        }
                    },
                    header: {
                        Button {
                            withAnimation { advancedExpanded.toggle() }
                        } label: {
                            HStack {
                                Text("Advanced")
                                Spacer()
                                Image(systemName: advancedExpanded ? "chevron.down" : "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                )
            }

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
        .frame(width: 440)
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
            TextField("Export Path", text: $exportPath, prompt: Text("/exports/data"))
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
            TextField("URI", text: $rawURL, prompt: Text("smb://server/share"))
        }
    }

    private var isValid: Bool {
        switch driveType {
        case .smb:          return !host.isEmpty && !share.isEmpty
        case .nfs:          return !host.isEmpty && !exportPath.isEmpty
        case .ftp, .afp:    return !host.isEmpty
        case .other:        return !rawURL.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private var assembledURL: String {
        switch driveType {
        case .smb:
            let portPart  = port.isEmpty ? "" : ":\(port)"
            let cleanShare = share.hasPrefix("/") ? String(share.dropFirst()) : share
            return "smb://\(host)\(portPart)/\(cleanShare)"
        case .nfs:
            let portPart = port.isEmpty ? "" : ":\(port)"
            let path = exportPath.hasPrefix("/") ? exportPath : "/\(exportPath)"
            return "nfs://\(host)\(portPart)\(path)"
        case .ftp:
            let userPart = ftpUser.isEmpty ? "" : "\(ftpUser)@"
            let portPart = port.isEmpty ? "" : ":\(port)"
            let pathPart = ftpPath.isEmpty ? "" : (ftpPath.hasPrefix("/") ? ftpPath : "/\(ftpPath)")
            return "ftp://\(userPart)\(host)\(portPart)\(pathPart)"
        case .afp:
            let portPart  = port.isEmpty ? "" : ":\(port)"
            let sharePart = share.isEmpty ? "" : "/\(share)"
            return "afp://\(host)\(portPart)\(sharePart)"
        case .other:
            return rawURL.trimmingCharacters(in: .whitespaces)
        }
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
        if drive.checkHostReachability || drive.checkDNSResolution || drive.checkPortAvailability {
            advancedExpanded = true
        }

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
        let finalURL    = assembledURL
        let trimmedLabel = label.trimmingCharacters(in: .whitespaces)

        if var existing = drive {
            existing.url       = finalURL
            existing.driveType = driveType
            existing.label     = trimmedLabel.isEmpty ? nil : trimmedLabel
            existing.checkHostReachability  = checkHostReachability
            existing.checkDNSResolution     = checkDNSResolution
            existing.checkPortAvailability  = checkPortAvailability
            manager.update(existing)
        } else {
            manager.add(NetworkDrive(
                id: UUID(),
                url: finalURL,
                driveType: driveType,
                label: trimmedLabel.isEmpty ? nil : trimmedLabel,
                checkHostReachability: checkHostReachability,
                checkDNSResolution: checkDNSResolution,
                checkPortAvailability: checkPortAvailability
            ))
        }
        dismiss()
    }
}
