import SwiftUI

/// 튜너 카드 안의 방송 정보: 방송국 이름(PS), 프로그램 종류, 라디오 텍스트, AF 메뉴.
/// 새 정보를 받기 전에는 이 주파수에서 마지막으로 받은 정보를 흐리게 보여준다.
struct RDSPanel: View {
    @EnvironmentObject private var radio: RadioModel
    @Environment(\.palette) private var theme

    var body: some View {
        if radio.isOn && radio.rdsEnabled {
            let info = radio.displayRDS
            let stale = radio.rdsIsStale
            VStack(spacing: 4) {
                if info.pi == nil {
                    Text("RDS 수신 대기 중…")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.dim)
                } else {
                    HStack(spacing: 6) {
                        Text(info.ps.isEmpty ? "—" : info.ps)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(theme.text)
                        if stale { badge("이전 수신") }
                        if radio.rdsDemo { badge("데모", highlight: true) }
                        if let pty = info.pty, let name = RDSNames.ptyName(pty) {
                            badge(name)
                        }
                        if info.tp { badge("TP") }
                        if info.ta { badge("TA", highlight: true) }
                        if !info.afs.isEmpty { afMenu(info) }
                    }
                    if !info.rt.isEmpty {
                        Text(info.rt)
                            .font(.system(size: 11))
                            .foregroundStyle(theme.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                    if stale {
                        Text("새 정보를 기다리는 중 · 마지막으로 받은 내용입니다")
                            .font(.system(size: 10))
                            .foregroundStyle(theme.dim)
                    }
                }
                if radio.afBusy {
                    Text("대체 주파수 확인 중…")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.accent)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 40)
            .opacity(stale ? 0.6 : 1)
            .help(piHelp(info))
        } else {
            Color.clear.frame(height: 0)
        }
    }

    private func piHelp(_ info: RDSInfo) -> String {
        guard let pi = info.pi else { return "RDS 정보를 기다리는 중" }
        return String(format: "방송국 코드(PI) %04X", pi)
    }

    private func afMenu(_ info: RDSInfo) -> some View {
        Menu {
            ForEach(info.afs.filter { $0 != radio.frequency }, id: \.self) { f in
                Button("\(mhz(f)) MHz로 이동") {
                    radio.tune(f)
                }
            }
            Divider()
            Button("가장 센 대체 주파수로 이동") {
                radio.evaluateAF(manual: true)
            }
            Toggle("AF 자동 전환", isOn: $radio.afAutoEnabled)
        } label: {
            badge("AF \(info.afs.count)", highlight: radio.afAutoEnabled)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func badge(_ text: String, highlight: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(highlight ? theme.onAccent : theme.badgeText)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(highlight ? theme.accent : theme.badgeFill)
            )
    }
}
