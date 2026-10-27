import SwiftUI

/// 채널 찾기 진행 대화상자
struct ScanDialog: View {
    @EnvironmentObject private var radio: RadioModel
    @Environment(\.palette) private var theme

    var body: some View {
        ZStack {
            theme.scrim.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 11) {
                Text("자동 찾기")
                    .font(.system(size: 17, weight: .bold))

                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        if let current = radio.scan.current {
                            Text("\(mhz(current))MHz에서 채널을 찾았습니다.")
                        } else {
                            Text("채널을 찾는 중입니다.")
                        }
                        Text("지금까지 채널 \(radio.scan.found)개를 찾았습니다.")
                    }
                    .font(.system(size: 12))
                    Spacer()
                    ProgressView()
                        .controlSize(.regular)
                }

                Button {
                    radio.cancelScan()
                } label: {
                    Text("취소")
                        .font(.system(size: 12, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(theme.text)
            .padding(20)
            .frame(width: 322)
            .background(RoundedRectangle(cornerRadius: 20).fill(theme.dialogFill))
        }
    }
}

/// 화면 아래에 잠깐 나타나는 안내 문구 (밝은 화면에서도 어두운 알약 모양을 쓴다)
struct ToastOverlay: View {
    @EnvironmentObject private var radio: RadioModel

    var body: some View {
        VStack {
            Spacer()
            if let text = radio.toast {
                Text(text)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color(white: 0.28)))
                    .padding(.bottom, 20)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: radio.toast)
        .allowsHitTesting(false)
    }
}
