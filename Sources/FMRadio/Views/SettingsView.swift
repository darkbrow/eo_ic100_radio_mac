import SwiftUI
import AppKit

/// 삼성 "라디오 설정"에 해당: 자동 끄기 타이머, 권한, 라디오 정보 + 맥용 오디오 설정
struct SettingsView: View {
    @EnvironmentObject private var radio: RadioModel

    var body: some View {
        Form {
            Section("화면") {
                Picker("화면 모드", selection: $radio.appearance) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                Text("기본은 다크입니다. \"시스템\"을 고르면 macOS의 모드를 따릅니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("자동 끄기 타이머") {
                Picker("라디오를 자동으로 끕니다", selection: $radio.autoOffMinutes) {
                    Text("사용 안 함").tag(0)
                    Text("15분").tag(15)
                    Text("30분").tag(30)
                    Text("1시간").tag(60)
                    Text("2시간").tag(120)
                }
            }

            Section("오디오") {
                Picker("출력 장치", selection: $radio.outputUID) {
                    Text("시스템 기본 출력").tag("")
                    ForEach(radio.outputDevices) { device in
                        Text(device.name).tag(device.uid)
                    }
                }
                Toggle("Mac 스피커로 재생", isOn: $radio.speakerMode)
                Toggle("볼륨 키가 재생 중인 장치를 조절하도록 시스템 출력 맞춤", isOn: $radio.syncSystemOutputEnabled)
                Text("맥의 볼륨 키와 이어폰의 볼륨 버튼은 시스템 출력 장치만 조절합니다. 켜 두면 라디오가 켜져 있는 동안 시스템 출력이 재생 중인 장치로 바뀝니다(다른 앱의 소리도 그 장치로 나옵니다). 라디오를 끄거나 이 설정을 끄면 원래 장치로 돌아갑니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("입력 장치 (이어폰)", selection: $radio.inputUID) {
                    Text("자동 (EO-IC100)").tag("")
                    ForEach(radio.inputDevices) { device in
                        Text(device.name).tag(device.uid)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Slider(value: $radio.gainDB, in: 0...24, step: 1) {
                        Text("음량 보정")
                    } minimumValueLabel: {
                        Text("0")
                    } maximumValueLabel: {
                        Text("24dB")
                    }
                    Text("현재 +\(Int(radio.gainDB))dB. 소리가 작으면 올리세요. 너무 높이면 소리가 깨질 수 있습니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("타임머신") {
                Picker("버퍼 길이", selection: $radio.timeMachineMinutes) {
                    Text("사용 안 함").tag(0)
                    Text("5분").tag(5)
                    Text("15분").tag(15)
                    Text("30분").tag(30)
                    Text("60분").tag(60)
                }
                Text(timeMachineNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("녹음") {
                LabeledContent("저장 폴더") {
                    Text(radio.recordingFolder)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                HStack {
                    Button("폴더 선택…") { chooseFolder() }
                    Button("폴더 열기") { radio.openRecordingFolder() }
                }
                Text("형식: AAC(m4a) 192kbps, 스테레오")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("RDS") {
                Toggle("방송 정보(RDS) 표시", isOn: $radio.rdsEnabled)
                Toggle("AF(대체 주파수) 자동 전환", isOn: $radio.afAutoEnabled)
                Button("RDS 데모 보기 (가짜 방송 정보)") { radio.startRDSDemo() }
                    .disabled(!radio.isOn)
                Button("저장된 RDS 정보 지우기") { radio.clearRDSCache() }
                Text("방송국이 RDS를 송출하지 않으면 정보가 표시되지 않습니다. AF 자동 전환은 RDS 수신이 4초 넘게 끊길 때, 같은 방송국(PI가 같은)의 대체 주파수 중 수신이 가장 센 곳으로 옮깁니다. 확인하는 동안 잠깐 소리가 끊깁니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("FM 대역") {
                Picker("대역", selection: $radio.bandChoice) {
                    ForEach(BandChoice.allCases) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
                Text("변경은 다음에 라디오를 켤 때 적용됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("권한") {
                LabeledContent("마이크 (이어폰 오디오 입력)", value: radio.micStatusText)
                Button("시스템 설정 열기") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }

            Section("진단") {
                DisclosureGroup("인식 상태 자세히 보기") {
                    // 모델 값을 갱신하지 않고, 이 글이 화면에 보이는 동안만 1초마다 다시 읽는다.
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text(radio.diagnosticReport())
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Button("진단 정보 복사") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(radio.diagnosticReport(), forType: .string)
                }
            }

            Section("라디오 정보") {
                LabeledContent("EO-IC100", value: radio.deviceConnected ? "연결됨" : "연결 안 됨")
                if radio.deviceConnected {
                    LabeledContent("제품 ID", value: String(format: "0x%04x", radio.productID))
                }
                if let band = radio.chipBand {
                    LabeledContent("칩 대역", value: "\(mhz(band.range.lowerBound))–\(mhz(band.range.upperBound)) MHz")
                }
                LabeledContent("버전", value: "1.0")
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 800)
    }

    private var timeMachineNote: String {
        if radio.timeMachineMinutes == 0 {
            return "일시정지와 되감기를 쓰지 않습니다. (녹음은 따로 쓸 수 있습니다)"
        }
        let megabytes = Int((Double(radio.timeMachineMinutes) * 11.5).rounded())
        return "임시 디스크를 약 \(megabytes)MB 쓰며, 라디오를 끄면 지워집니다. 방송국을 바꾸면 이전 방송의 기록은 버려집니다. 변경은 다음에 라디오를 켤 때 적용됩니다."
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
