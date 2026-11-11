import SwiftUI
import AppKit

/// 삼성 "라디오 설정"에 해당: 자동 끄기 타이머, 권한, 라디오 정보 + 맥용 오디오 설정
struct SettingsView: View {
    @EnvironmentObject private var radio: RadioModel

    var body: some View {
        Form {
            Section(L("화면")) {
                Picker(L("화면 모드"), selection: $radio.appearance) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                Text(L("기본은 다크입니다. \"시스템\"을 고르면 macOS의 모드를 따릅니다."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L("자동 끄기 타이머")) {
                Picker(L("라디오를 자동으로 끕니다"), selection: $radio.autoOffMinutes) {
                    Text(L("사용 안 함")).tag(0)
                    Text(L("15분")).tag(15)
                    Text(L("30분")).tag(30)
                    Text(L("1시간")).tag(60)
                    Text(L("2시간")).tag(120)
                }
            }

            Section(L("오디오")) {
                Picker(L("출력 장치"), selection: $radio.outputUID) {
                    Text(L("이어폰 (자동)")).tag("")
                    ForEach(radio.outputDevices.filter { !$0.isBuiltIn }) { device in
                        Text(device.name).tag(device.uid)
                    }
                }
                Toggle(L("Mac 스피커로 재생"), isOn: $radio.speakerMode)
                Toggle(L("볼륨 키가 재생 중인 장치를 조절하도록 시스템 출력 맞춤"), isOn: $radio.syncSystemOutputEnabled)
                Text(L("맥의 볼륨 키와 이어폰의 볼륨 버튼은 시스템 출력 장치만 조절합니다. 켜 두면 라디오가 켜져 있는 동안 시스템 출력이 재생 중인 장치로 바뀝니다(다른 앱의 소리도 그 장치로 나옵니다). 라디오를 끄거나 이 설정을 끄면 원래 장치로 돌아갑니다."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(L("현재 재생 장치: %@", radio.effectiveOutputDescription))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(L("다른 출력 장치를 고르면 \"Mac 스피커로 재생\"을 켜지 않은 동안 그 장치로 재생됩니다. \"이어폰 (자동)\"은 EO-IC100의 출력 장치로 재생합니다. \"Mac 스피커로 재생\"은 앱을 종료하면 꺼집니다."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker(L("입력 장치 (이어폰)"), selection: $radio.inputUID) {
                    Text(L("자동 (EO-IC100)")).tag("")
                    ForEach(radio.inputDevices) { device in
                        Text(device.name).tag(device.uid)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Slider(value: $radio.gainDB, in: 0...24, step: 1) {
                        Text(L("음량 보정"))
                    } minimumValueLabel: {
                        Text("0")
                    } maximumValueLabel: {
                        Text("24dB")
                    }
                    Text(L("현재 +%llddB. 소리가 작으면 올리세요. 너무 높이면 소리가 깨질 수 있습니다.", Int(radio.gainDB)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section(L("타임머신")) {
                Picker(L("버퍼 길이"), selection: $radio.timeMachineMinutes) {
                    Text(L("사용 안 함")).tag(0)
                    Text(L("5분")).tag(5)
                    Text(L("15분")).tag(15)
                    Text(L("30분")).tag(30)
                    Text(L("60분")).tag(60)
                }
                Text(timeMachineNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L("녹음")) {
                LabeledContent(L("저장 폴더")) {
                    Text(radio.recordingFolder)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                HStack {
                    Button(L("폴더 선택…")) { chooseFolder() }
                    Button(L("폴더 열기")) { radio.openRecordingFolder() }
                }
                Text(L("형식: AAC(m4a) 192kbps, 스테레오"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("RDS") {
                Toggle(L("방송 정보(RDS) 표시"), isOn: $radio.rdsEnabled)
                Toggle(L("AF(대체 주파수) 자동 전환"), isOn: $radio.afAutoEnabled)
                Button(L("저장된 RDS 정보 지우기")) { radio.clearRDSCache() }
                Text(L("방송국이 RDS를 송출하지 않으면 정보가 표시되지 않습니다. AF 자동 전환은 RDS 수신이 4초 넘게 끊길 때, 같은 방송국(PI가 같은)의 대체 주파수 중 수신이 가장 센 곳으로 옮깁니다. 확인하는 동안 잠깐 소리가 끊깁니다."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L("FM 대역")) {
                Picker(L("대역"), selection: $radio.bandChoice) {
                    ForEach(BandChoice.allCases) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
                Text(L("라디오가 켜져 있으면 바로 적용됩니다. 칩이 대역을 바꾸는 데 잠깐 걸릴 수 있습니다."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L("권한")) {
                LabeledContent(L("마이크 (이어폰 오디오 입력)"), value: radio.micStatusText)
                Button(L("시스템 설정 열기")) {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }

            Section(L("진단")) {
                DisclosureGroup(L("인식 상태 자세히 보기")) {
                    // 모델 값을 갱신하지 않고, 이 글이 화면에 보이는 동안만 1초마다 다시 읽는다.
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text(radio.diagnosticReport())
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Button(L("진단 정보 복사")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(radio.diagnosticReport(), forType: .string)
                }
            }

            Section(L("라디오 정보")) {
                LabeledContent(L("버전"), value: appVersionString)
                Button(L("도움말 열기")) { HelpWindow.show() }
                LabeledContent("EO-IC100", value: radio.deviceConnected ? L("연결됨") : L("연결 안 됨"))
                if radio.deviceConnected {
                    LabeledContent(L("제품 ID"), value: String(format: "0x%04x", radio.productID))
                }
                if let band = radio.chipBand {
                    LabeledContent(L("칩 대역"), value: "\(mhz(band.range.lowerBound))–\(mhz(band.range.upperBound)) MHz")
                }
                LabeledContent(L("버전"), value: "1.0")
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 800)
    }

    private var timeMachineNote: String {
        if radio.timeMachineMinutes == 0 {
            return L("일시정지와 되감기를 쓰지 않습니다. (녹음은 따로 쓸 수 있습니다)")
        }
        let megabytes = Int((Double(radio.timeMachineMinutes) * 11.5).rounded())
        return L("임시 디스크를 약 %lldMB 쓰며, 라디오를 끄면 지워집니다. 방송국을 바꾸면 이전 방송의 기록은 버려집니다. 변경은 다음에 라디오를 켤 때 적용됩니다.", megabytes)
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
