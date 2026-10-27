import SwiftUI

/// 가로 화면 배치: 왼쪽에 튜너, 오른쪽에 채널/즐겨찾기 목록, 아래에 타임머신/녹음 막대.
struct ContentView: View {
    @EnvironmentObject private var radio: RadioModel
    @Environment(\.colorScheme) private var systemScheme

    var body: some View {
        // 다크/라이트를 직접 골랐으면 그 값을, "시스템"이면 현재 시스템 모드를 따른다.
        let palette = Theme.palette(for: radio.appearance.colorScheme ?? systemScheme)
        ZStack {
            palette.background.ignoresSafeArea()

            VStack(spacing: 11) {
                HStack(alignment: .top, spacing: 17) {
                    TunerPane()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    ChannelPane()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                TransportBar()
            }
            .padding(17)

            if radio.scan.isRunning {
                ScanDialog()
            }
            ToastOverlay()
        }
        .environment(\.palette, palette)
        .environmentObject(radio.timeline)
        .sheet(item: $radio.renameTarget) { target in
            RenameSheet(target: target)
                .environmentObject(radio)
                .environment(\.palette, palette)
        }
        .frame(minWidth: 680, minHeight: 480)
    }
}
