import SwiftUI

struct AboutView: View {
    private let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "externaldrive.connected.to.line.below")
                .font(.system(size: 48))
                .foregroundStyle(.primary)

            Text("MenuBarFS")
                .font(.title2)
                .fontWeight(.bold)

            Text("Version \(version)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Manage network drives and removable volumes from your menu bar.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 250)
        }
        .padding(24)
        .frame(width: 300)
    }
}
