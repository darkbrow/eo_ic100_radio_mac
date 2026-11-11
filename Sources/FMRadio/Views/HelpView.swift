import SwiftUI
import AppKit

/// 도움말 창. 메뉴바의 도움말 메뉴(⌘?)와 설정에서 연다. 글은 모두 L()로 지역화한다.
struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text(L("FM Radio 도움말"))
                    .font(.title.bold())
                Text(L("버전") + " " + appVersionString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Group {
                section(L("시작하기")) {
                    paragraph(L("EO-IC100(삼성 USB-C 이어폰)을 맥에 연결한 뒤 앱을 실행하세요. 이어폰이 연결되어 있어야 라디오가 동작합니다."))
                    paragraph(L("처음 실행하면 이어폰 연결을 허용하라는 팝업과 마이크 권한 요청이 나타납니다. 모두 허용해 주세요. 마이크 소리는 쓰지 않고, 이어폰의 라디오 오디오를 입력 장치로 받기 위해 필요합니다."))
                    paragraph(L("전원 버튼을 누르면 라디오가 켜집니다. 켜져 있는 동안 맥 메뉴바에 마이크 사용 표시가 보일 수 있습니다. 라디오 오디오를 입력으로 받기 때문이며, 마이크 소리는 사용하지 않습니다."))
                    paragraph(L("앱을 종료하거나 이어폰을 뽑으면 라디오 전원이 꺼집니다."))
                }
                section(L("주파수와 채널")) {
                    paragraph(L("← / → 키로 0.1MHz, ⇧← / ⇧→ 키로 1.0MHz씩 주파수를 바꿉니다. ⌘← / ⌘→ 키는 채널 목록의 이전 / 다음 채널로 이동합니다."))
                    paragraph(L("채널 목록의 '채널 찾기'(⌘F)를 누르면 방송을 자동으로 찾아 목록에 추가합니다."))
                    paragraph(L("주파수 옆이나 채널 목록의 별표를 누르면 즐겨찾기에 추가됩니다."))
                    paragraph(L("채널 행, 즐겨찾기 원, 큰 주파수 숫자를 우클릭하고 '표시명 지정…'(⌘E)을 고르면 주파수에 원하는 이름(최대 24자)을 붙일 수 있습니다. 이름은 앱을 껐다 켜도 유지되며, 방송국이 보내는 RDS 이름과는 별개입니다."))
                    paragraph(L("M 키 또는 튜너 카드의 스피커 버튼으로 음소거합니다. 소리만 끊고 타임머신 기록과 녹음은 계속됩니다."))
                }
                section(L("타임머신 (일시정지와 되감기)")) {
                    paragraph(L("라디오를 켜 두는 동안 최근 5/15/30/60분(설정에서 선택, 기본 15분)의 방송을 임시로 저장합니다. 아래 막대에서 일시정지(Space), 15초 뒤로(⌥←), 15초 앞으로(⌥→), LIVE로 돌아가기(L)를 할 수 있습니다."))
                    paragraph(L("일시정지한 자리에서 이어 들을 수 있고, 라이브를 따라잡으면 자동으로 LIVE로 돌아갑니다. 방송국을 바꾸면 이전 방송의 기록은 버려지고, 라디오를 끄면 임시 파일이 지워집니다."))
                }
                section(L("녹음")) {
                    paragraph(L("녹음 버튼(R)을 누르면 지금부터의 방송을 AAC(m4a) 파일로 저장하고, 다시 누르면 끝내고 저장합니다. 되감기 중에도 라이브가 녹음됩니다."))
                    paragraph(L("녹음 버튼 옆의 저장 메뉴에서 타임머신에 쌓인 지난 1/5/15/30/60분을 바로 파일로 저장할 수 있습니다. 설정한 타임머신 길이 안에서만 저장됩니다."))
                    paragraph(L("기본 저장 폴더는 ~/Music/FM Radio이며 설정의 '녹음'에서 바꿀 수 있습니다. 녹음 폴더 열기 메뉴로 바로 열 수 있습니다."))
                }
                section(L("방송 정보 (RDS)와 대체 주파수 (AF)")) {
                    paragraph(L("방송국이 RDS를 송출하면 튜너 카드에 방송국 이름, 프로그램 종류, 라디오 텍스트가 표시됩니다. 송출하지 않는 방송국은 'RDS 수신 대기 중…'만 보이며, 신호가 약해도 오래 기다리게 될 수 있습니다."))
                    paragraph(L("주파수마다 마지막으로 받은 정보를 저장해 두었다가, 다시 돌아오면 새 정보가 들어오기 전까지 '이전 수신' 표시와 함께 보여 줍니다. 설정의 '저장된 RDS 정보 지우기'로 비울 수 있습니다."))
                    paragraph(L("방송국이 대체 주파수(AF) 목록을 보내면 'AF n' 표시가 나타나고, 메뉴에서 그 주파수로 직접 이동할 수 있습니다. A 키로 가장 센 주파수를 지금 확인할 수 있습니다."))
                    paragraph(L("설정의 'AF 자동 전환'(기본 꺼짐)을 켜면, RDS 수신이 4초 넘게 끊길 때 같은 방송(PI가 같음)의 대체 주파수 중 수신이 가장 센 곳으로 옮깁니다. 확인하는 동안 잠깐 소리가 끊깁니다."))
                }
                section(L("소리 출력과 볼륨")) {
                    paragraph(L("소리는 기본적으로 이어폰(EO-IC100)으로 나옵니다. 맥의 시스템 출력이 다른 장치로 되어 있어도 앱이 이어폰의 출력 장치로 직접 보냅니다."))
                    paragraph(L("'Mac 스피커로 재생'(⇧⌘S)을 켜면 맥 내장 스피커로 나오고, 끄면 이어폰으로 돌아갑니다. 이 설정은 저장되지 않아 앱을 켤 때마다 꺼진 상태(이어폰)로 시작합니다."))
                    paragraph(L("설정 > 오디오에서 이어폰 대신 블루투스 스피커 같은 다른 장치를 고를 수도 있습니다. 기본값은 '이어폰 (자동)'입니다."))
                    paragraph(L("맥의 볼륨 키와 이어폰의 볼륨 버튼은 시스템 출력 장치만 조절합니다. 그래서 라디오가 켜져 있는 동안 시스템 출력도 재생 중인 장치로 맞춰 두고, 라디오를 끄거나 앱을 종료하면 원래 장치로 되돌립니다. 이 동안에는 다른 앱의 소리도 같은 장치로 나옵니다. 설정에서 끌 수 있습니다."))
                    paragraph(L("소리가 너무 작으면 설정의 '음량 보정'(0~24dB)을 올려 보세요. 뒤에 리미터가 있어 소리가 깨지는 것을 줄입니다."))
                }
                section(L("설정")) {
                    paragraph(L("설정은 앱 메뉴의 '설정…'(⌘,)에서 엽니다. 화면 모드(다크/라이트/시스템), 자동 끄기 타이머, 출력과 입력 장치, 음량 보정, 타임머신 길이, 녹음 폴더, RDS와 AF, FM 대역을 바꿀 수 있습니다."))
                    paragraph(L("FM 대역은 76.0–107.0 MHz와 87.0–108.0 MHz 중에서 고릅니다. 기본은 87.0–108.0 MHz이며, 수신하려는 지역의 대역에 맞춰 고르세요. 라디오가 켜져 있으면 바로 적용됩니다."))
                }
                section(L("문제가 생기면")) {
                    paragraph(L("'EO-IC100이 연결되지 않았습니다.'가 보이면: 이어폰을 다시 꽂고, 이어폰 연결 허용 팝업이 나왔다면 허용했는지 확인하세요. 설정 > 진단 > '인식 상태 자세히 보기'에서 앱이 보는 USB와 오디오 장치 목록을 볼 수 있습니다."))
                    paragraph(L("소리가 안 나거나 이어폰이 아닌 곳으로 나오면: 설정 > 권한에서 마이크가 허용되어 있는지, 'Mac 스피커로 재생'이 꺼져 있는지, 설정 > 오디오의 출력 장치가 '이어폰 (자동)'인지 확인하세요."))
                    paragraph(L("도움을 요청할 때는 설정 > 진단의 '진단 정보 복사'로 복사한 내용을 함께 보내면 원인을 찾기 쉽습니다."))
                }
                section(L("키보드 단축키")) {
                    ForEach(Array(Self.shortcuts.enumerated()), id: \.offset) { _, row in
                        shortcut(row.0, row.1)
                    }
                }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 520, minHeight: 420)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private static let shortcuts: [(String, String)] = [
        ("⌘↩", L("라디오 켜기 / 끄기")),
        ("M", L("음소거 / 음소거 해제")),
        ("← / →", L("주파수 −0.1MHz / +0.1MHz")),
        ("⇧← / ⇧→", L("주파수 −1.0MHz / +1.0MHz")),
        ("⌘← / ⌘→", L("이전 채널 / 다음 채널")),
        ("⌘F", L("채널 찾기")),
        ("⌘E", L("현재 주파수에 표시명 지정…")),
        ("Space", L("일시정지 / 재생")),
        ("⌥← / ⌥→", L("15초 뒤로 / 15초 앞으로")),
        ("L", L("LIVE로 돌아가기")),
        ("R", L("지금부터 녹음 / 녹음 끝내고 저장")),
        ("A", L("가장 센 대체 주파수 확인 (AF)")),
        ("⇧⌘S", L("Mac 스피커로 재생 전환")),
        ("⌘,", L("설정…")),
        ("⌘?", L("FM Radio 도움말")),
    ]

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.title3.weight(.semibold))
            content()
        }
    }

    private func paragraph(_ text: String) -> some View {
        Text(text)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func shortcut(_ keys: String, _ description: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(keys)
                .font(.system(.body, design: .monospaced))
                .frame(width: 110, alignment: .leading)
            Text(description)
                .foregroundStyle(.secondary)
        }
    }
}

let appVersionString: String =
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"

/// 도움말 창을 하나만 만들어 두고 다시 열 때 앞으로 가져온다.
@MainActor
enum HelpWindow {
    private static var window: NSWindow?

    static func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let controller = NSHostingController(rootView: HelpView())
        let created = NSWindow(contentViewController: controller)
        created.title = L("FM Radio 도움말")
        created.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        created.setContentSize(NSSize(width: 640, height: 680))
        created.isReleasedWhenClosed = false
        created.center()
        window = created
        created.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
