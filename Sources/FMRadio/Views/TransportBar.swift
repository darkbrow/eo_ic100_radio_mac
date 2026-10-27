import SwiftUI

/// 아래쪽 막대: 타임머신(일시정지/되감기/LIVE)과 녹음
struct TransportBar: View {
    @EnvironmentObject private var radio: RadioModel
    @EnvironmentObject private var timeline: TimelineState
    @Environment(\.palette) private var theme
    @State private var dragging = false
    @State private var dragPosition: Double = 0

    private var status: TimeShiftStatus { timeline.timeShift }
    private var timeMachineReady: Bool { radio.isOn && status.isActive }

    var body: some View {
        HStack(spacing: 10) {
            transportButton("gobackward.15", help: "15초 뒤로 (⌥←)") {
                radio.skip(-15)
            }
            transportButton(status.isPaused ? "play.fill" : "pause.fill",
                            help: status.isPaused ? "재생 (Space)" : "일시정지 (Space)") {
                radio.togglePause()
            }
            transportButton("goforward.15", help: "15초 앞으로 (⌥→)") {
                radio.skip(15)
            }
            liveButton

            Slider(value: position, in: 0...max(status.buffered, 1)) { editing in
                dragging = editing
                if !editing {
                    radio.seekTimeline(delay: max(0, status.buffered - dragPosition))
                }
            }
            .controlSize(.small)
            .disabled(!timeMachineReady)

            Text(timeLabel)
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(theme.dim)
                .frame(width: 45, alignment: .trailing)

            Divider().frame(height: 20)

            recordButton
            saveMenu
        }
        .padding(.horizontal, 14)
        .frame(height: 45)
        .background(RoundedRectangle(cornerRadius: 15).fill(theme.card))
    }

    // MARK: 부품

    private var position: Binding<Double> {
        Binding(
            get: { dragging ? dragPosition : max(0, status.buffered - status.delay) },
            set: { dragPosition = $0 }
        )
    }

    private var timeLabel: String {
        guard timeMachineReady else { return radio.timeMachineMinutes == 0 ? "꺼짐" : "—" }
        if status.isLive { return "LIVE" }
        return "−" + clock(status.delay)
    }

    private func clock(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func transportButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .foregroundStyle(theme.text.opacity(timeMachineReady ? 0.9 : 0.3))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!timeMachineReady)
        .help(help)
    }

    private var liveButton: some View {
        Button {
            radio.goLive()
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(status.isLive && timeMachineReady ? Color.red : theme.dim)
                    .frame(width: 6, height: 6)
                Text("LIVE")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(status.isLive ? theme.text : theme.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().stroke(status.isLive ? theme.line : theme.secondary, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!timeMachineReady || status.isLive)
        .help("라이브로 돌아가기 (L)")
    }

    private var recordButton: some View {
        Button {
            radio.toggleRecording()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: radio.isRecording ? "stop.circle.fill" : "record.circle")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.red)
                Text(radio.isRecording ? clock(timeline.recordingElapsed) : "녹음")
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(theme.text)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!radio.isOn)
        .opacity(radio.isOn ? 1 : 0.4)
        .help(radio.isRecording ? "녹음 끝내고 저장 (R)" : "지금부터 녹음 (R)")
    }

    private var saveMenu: some View {
        Menu {
            ForEach(saveOptions, id: \.self) { minutes in
                Button("지난 \(minutes)분 저장") {
                    radio.saveRecent(minutes: minutes)
                }
                .disabled(!timeMachineReady)
            }
            Divider()
            Button("녹음 폴더 열기") {
                radio.openRecordingFolder()
            }
        } label: {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 13))
                .foregroundStyle(theme.text)
                .frame(width: 21, height: 21)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("타임머신 버퍼에서 저장")
    }

    /// 설정한 버퍼 길이 안에서 고를 수 있는 저장 길이
    private var saveOptions: [Int] {
        let limit = max(radio.timeMachineMinutes, 1)
        return [1, 5, 15, 30, 60].filter { $0 <= limit }
    }
}
