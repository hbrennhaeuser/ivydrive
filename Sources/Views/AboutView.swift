import SwiftUI

struct AboutView: View {
    private let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    private let repositoryURL = URL(string: "https://github.com/hbrennhaeuser/menubarfs")!

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)

            Text("MenuBarFS")
                .font(.title2)
                .fontWeight(.bold)

            Text("Version v\(version)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("By HBrennhaeuser")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Keep track of your servers and reconnect them with one click.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 250)

            Text("© 2026 HBrennhaeuser · GPL-3.0-only")
                .font(.caption)
                .foregroundStyle(.secondary)

            Link("github.com/hbrennhaeuser/menubarfs", destination: repositoryURL)
                .font(.caption)
        }
        .padding(24)
        .frame(width: 300)
    }
}
