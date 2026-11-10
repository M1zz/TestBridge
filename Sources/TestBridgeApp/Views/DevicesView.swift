import SwiftUI

struct DevicesView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        VStack(spacing: 0) {
            Table(state.devices, selection: $state.selectedDeviceID) {
                TableColumn("Platform") { Text($0.platform.displayName) }.width(80)
                TableColumn("Name") { Text($0.name) }
                TableColumn("Runtime") { Text($0.runtime) }.width(110)
                TableColumn("State") { d in
                    Text(d.state).foregroundStyle(d.isBooted ? .green : .secondary)
                }.width(90)
                TableColumn("UDID") { d in
                    Text(d.udid).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                }
            }
            .onChange(of: state.selectedDeviceID) { _, _ in
                if let dev = state.selectedDevice { state.platform = dev.platform }
                Task { await state.loadInstalledApps() }
            }

            Divider()

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Installed apps on selected simulator").font(.caption).foregroundStyle(.secondary)
                    if state.installedApps.isEmpty {
                        Text(state.selectedDevice?.isHostMac == true
                             ? "For macOS, type the bundle identifier of the app you want to test."
                             : "Boot the simulator and install your app (⌘R in Xcode) to see it here.")
                            .font(.caption)
                    } else {
                        ScrollView(.horizontal) {
                            HStack {
                                ForEach(state.installedApps, id: \.self) { bid in
                                    Button(bid) { state.bundleIdentifier = bid }
                                        .buttonStyle(.bordered)
                                        .font(.caption)
                                }
                            }
                        }
                    }
                }
                Spacer()
                Button("Boot & open Simulator") { Task { await state.bootSelectedDevice() } }
                    .disabled(state.selectedDevice == nil || state.selectedDevice?.isHostMac == true)
            }
            .padding()
        }
        .navigationTitle("Devices")
        .toolbar {
            Button {
                Task { await state.refreshDevices() }
            } label: {
                if state.isLoadingDevices { ProgressView().controlSize(.small) } else { Label("Refresh", systemImage: "arrow.clockwise") }
            }
        }
    }
}
