import SwiftUI
import AppKit
import AVFoundation

struct SettingsView: View {
    @EnvironmentObject private var radio: RadioModel
    @Environment(\.locale) private var locale

    var body: some View {
        Form {
            Section {
                Picker(selection: $radio.appearance) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(LocalizedStringKey(mode.title)).tag(mode)
                    }
                } label: {
                    Text("settings.appearance.mode", tableName: "Settings")
                }
                Text("settings.appearance.hint", tableName: "Settings")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("settings.appearance", tableName: "Settings")
            }

            Section {
                Picker(selection: $radio.autoOffMinutes) {
                    Text("settings.never", tableName: "Settings").tag(0)
                    Text(formatted("settings.minutes", 15)).tag(15)
                    Text(formatted("settings.minutes", 30)).tag(30)
                    Text(formatted("settings.hour", 1)).tag(60)
                    Text(formatted("settings.hours", 2)).tag(120)
                } label: {
                    Text("settings.auto_off.description", tableName: "Settings")
                }
            } header: {
                Text("settings.auto_off", tableName: "Settings")
            }

            Section {
                Picker(selection: $radio.outputUID) {
                    Text("settings.output.default", tableName: "Settings").tag("")
                    ForEach(radio.outputDevices) { device in
                        Text(device.name).tag(device.uid)
                    }
                } label: {
                    Text("settings.output.device", tableName: "Settings")
                }
                Toggle(isOn: Binding(
                    get: { radio.speakerMode },
                    set: { radio.setSpeakerMode($0) }
                )) {
                    Text("settings.output.mac_speakers", tableName: "Settings")
                }
                Toggle("settings.output.sync", tableName: "Settings", isOn: $radio.syncSystemOutputEnabled)
                Text("settings.output.sync.note", tableName: "Settings")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker(selection: $radio.inputUID) {
                    Text("settings.input.automatic", tableName: "Settings").tag("")
                    ForEach(radio.inputDevices) { device in
                        Text(device.name).tag(device.uid)
                    }
                } label: {
                    Text("settings.input.device", tableName: "Settings")
                }
                VStack(alignment: .leading, spacing: 4) {
                    Slider(value: $radio.gainDB, in: 0...24, step: 1) {
                        Text("settings.gain", tableName: "Settings")
                    } minimumValueLabel: {
                        Text("0")
                    } maximumValueLabel: {
                        Text("24 dB")
                    }
                    Text(formatted("settings.gain.note", Int(radio.gainDB)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("settings.audio", tableName: "Settings")
            }

            Section {
                Picker(selection: $radio.timeMachineMinutes) {
                    Text("settings.never", tableName: "Settings").tag(0)
                    Text(formatted("settings.minutes", 5)).tag(5)
                    Text(formatted("settings.minutes", 15)).tag(15)
                    Text(formatted("settings.minutes", 30)).tag(30)
                    Text(formatted("settings.minutes", 60)).tag(60)
                } label: {
                    Text("settings.buffer.length", tableName: "Settings")
                }
                timeMachineNote
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("settings.timemachine", tableName: "Settings")
            }

            Section {
                LabeledContent {
                    Text(radio.recordingFolder)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                } label: {
                    Text("settings.recording.folder", tableName: "Settings")
                }
                HStack {
                    Button("settings.folder.choose", tableName: "Settings") { chooseFolder() }
                    Button("settings.folder.open", tableName: "Settings") { radio.openRecordingFolder() }
                }
                Text("settings.recording.format", tableName: "Settings")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("settings.recording", tableName: "Settings")
            }

            Section {
                Toggle("settings.rds.show", tableName: "Settings", isOn: $radio.rdsEnabled)
                Toggle("settings.rds.af_auto", tableName: "Settings", isOn: $radio.afAutoEnabled)
                Button("settings.rds.demo", tableName: "Settings") { radio.startRDSDemo() }
                    .disabled(!radio.isOn)
                Button("settings.rds.clear_cache", tableName: "Settings") { radio.clearRDSCache() }
                Text("settings.rds.note", tableName: "Settings")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("RDS")
            }

            Section {
                Picker(selection: $radio.bandChoice) {
                    ForEach(BandChoice.allCases) { choice in
                        Text(LocalizedStringKey(choice.title)).tag(choice)
                    }
                } label: {
                    Text("settings.band", tableName: "Settings")
                }
                Text("settings.changes_apply_next_power", tableName: "Settings")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("settings.fm_band", tableName: "Settings")
            }

            Section {
                LabeledContent {
                    microphoneStatus
                } label: {
                    Text("settings.permissions.microphone", tableName: "Settings")
                }
                Button("settings.permissions.open", tableName: "Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                        NSWorkspace.shared.open(url)
                    }
                }
            } header: {
                Text("settings.permissions", tableName: "Settings")
            }

            Section {
                DisclosureGroup("settings.diagnostics.details", tableName: "Settings") {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text(radio.diagnosticReport())
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Button("settings.diagnostics.copy", tableName: "Settings") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(radio.diagnosticReport(), forType: .string)
                }
            } header: {
                Text("settings.diagnostics", tableName: "Settings")
            }

            Section {
                LabeledContent("EO-IC100", value: localized(radio.deviceConnected ? "Connected" : "Not Connected"))
                if radio.deviceConnected {
                    LabeledContent("Product ID", value: String(format: "0x%04x", radio.productID))
                }
                if let band = radio.chipBand {
                    LabeledContent("settings.radio_info.chip_band", tableName: "Settings",
                                   value: "\(mhz(band.range.lowerBound))–\(mhz(band.range.upperBound)) MHz")
                }
                LabeledContent("settings.radio_info.version", tableName: "Settings", value: "1.0")
            } header: {
                Text("settings.radio_info", tableName: "Settings")
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 800)
        .id(locale.identifier)
    }

    private func localized(_ key: String) -> String {
        Bundle.main.localizedString(forKey: key, value: key, table: "Settings")
    }

    private func formatted(_ key: String, _ arguments: CVarArg...) -> String {
        let template = localized(key)
        return String(format: template, locale: locale, arguments: arguments)
    }

    @ViewBuilder
    private var microphoneStatus: some View {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: Text("settings.permissions.allowed", tableName: "Settings")
        case .notDetermined: Text("settings.permissions.not_requested", tableName: "Settings")
        case .denied: Text("settings.permissions.denied", tableName: "Settings")
        case .restricted: Text("settings.permissions.restricted", tableName: "Settings")
        @unknown default: Text("settings.permissions.unknown", tableName: "Settings")
        }
    }

    @ViewBuilder
    private var timeMachineNote: some View {
        if radio.timeMachineMinutes == 0 {
            Text("settings.buffer.disabled_note", tableName: "Settings")
        } else {
            let megabytes = Int((Double(radio.timeMachineMinutes) * 11.5).rounded())
            Text(formatted("settings.buffer.enabled_note", megabytes))
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath: radio.recordingFolder, isDirectory: true)
        if panel.runModal() == .OK, let url = panel.url {
            radio.recordingFolder = url.path
        }
    }
}
