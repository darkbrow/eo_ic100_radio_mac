import SwiftUI
import AppKit

@main
struct FMRadioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    /// 일부러 @StateObject를 쓰지 않는다. App이 모델을 관찰하면 모델 값이 바뀔 때마다 App.body가 다시 계산되고
    /// 메뉴바 명령(.commands)도 다시 만들어져서, 메뉴바가 깜빡이고 열려 있던 메뉴가 닫힌다.
    /// 화면은 .environmentObject로 받은 뷰들이 각자 관찰한다.
    private let radio = RadioModel.shared

    var body: some Scene {
        Window("FM 라디오", id: "main") {
            ContentView()
                .environmentObject(radio)
                .onAppear { appDelegate.radio = radio }
        }
        .defaultSize(width: 790, height: 510)
        .commands {
            RadioCommands(radio: radio)
            // 필요 없는 View 메뉴의 기본 항목(툴바, 사이드바)을 비운다. 남는 항목은 AppDelegate가 정리한다.
            CommandGroup(replacing: .toolbar) {}
            CommandGroup(replacing: .sidebar) {}
        }

        Settings {
            SettingsView()
                .environmentObject(radio)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var radio: RadioModel?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // 창을 탭으로 합치는 기능을 꺼서 View 메뉴에 탭 항목이 생기지 않게 한다.
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // swift run 으로 실행해도 일반 앱처럼 창과 메뉴가 나타나게 한다.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        setDockIconIfNeeded()

        configureWindows()
        removeViewMenu()
        let center = NotificationCenter.default
        center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.configureWindows()
                self?.removeViewMenu()
            }
        }
        // SwiftUI가 메뉴를 다시 만들면서 View 메뉴가 되살아나는 경우를 대비한다.
        center.addObserver(forName: NSMenu.didAddItemNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.removeViewMenu()
            }
        }
    }

    /// 전체 화면은 쓰지 않는다 (View 메뉴의 "Enter Full Screen" 항목이 생기지 않게 한다).
    private func configureWindows() {
        for window in NSApp.windows {
            window.collectionBehavior.remove(.fullScreenPrimary)
            window.collectionBehavior.insert(.fullScreenNone)
        }
    }

    /// 메뉴바의 View 메뉴를 없앤다. 제목이 View/보기인 메뉴, 또는 전체 화면 항목을 가진 메뉴를 지운다.
    /// 최신 macOS는 Window 메뉴에도 전체 화면 항목이 있을 수 있어서, Window/Help 메뉴는 건드리지 않는다.
    private func removeViewMenu() {
        guard let mainMenu = NSApp.mainMenu else { return }
        let fullScreen = #selector(NSWindow.toggleFullScreen(_:))
        let protectedTitles: Set<String> = ["Window", "창", "윈도우", "Help", "도움말"]
        for item in mainMenu.items {
            guard let submenu = item.submenu else { continue }
            let isProtected = submenu === NSApp.windowsMenu || protectedTitles.contains(item.title)
            let isViewTitle = item.title == "View" || item.title == "보기"
            let hasFullScreenItem = submenu.items.contains { $0.action == fullScreen }
            if isViewTitle || (hasFullScreenItem && !isProtected) {
                mainMenu.removeItem(item)
            }
        }
    }

    /// .app 번들로 실행하면 Info.plist의 아이콘이 쓰이므로, 번들이 아닐 때(swift run)만 직접 지정한다.
    private func setDockIconIfNeeded() {
        guard !Bundle.main.bundlePath.hasSuffix(".app"),
              let data = Data(base64Encoded: AppIconData.base64, options: .ignoreUnknownCharacters),
              let image = NSImage(data: data) else { return }
        NSApp.applicationIconImage = image
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        // 이어폰의 라디오가 계속 켜져 있지 않도록 종료 전에 끈다.
        radio?.shutdown()
    }
}

/// 메뉴바의 "라디오" 메뉴.
/// 모델을 관찰하지 않는다(@ObservedObject 없음). 관찰하면 모델 값이 바뀔 때마다 메뉴바가 다시 만들어져서
/// 열려 있는 메뉴가 닫히기 때문에, 항목 이름도 상태에 따라 바꾸지 않고 고정했다.
struct RadioCommands: Commands {
    let radio: RadioModel

    var body: some Commands {
        CommandMenu("라디오") {
            Button("라디오 켜기 / 끄기") { radio.togglePower() }
                .keyboardShortcut(.return, modifiers: .command)
            Button("음소거 / 음소거 해제") { radio.toggleMute() }
                .keyboardShortcut("m", modifiers: [])

            Divider()

            Button("주파수 −0.1MHz") { radio.step(-1) }
                .keyboardShortcut(.leftArrow, modifiers: [])
            Button("주파수 +0.1MHz") { radio.step(1) }
                .keyboardShortcut(.rightArrow, modifiers: [])
            Button("주파수 −1.0MHz") { radio.step(-10) }
                .keyboardShortcut(.leftArrow, modifiers: .shift)
            Button("주파수 +1.0MHz") { radio.step(10) }
                .keyboardShortcut(.rightArrow, modifiers: .shift)
            Button("이전 채널") { radio.jump(-1) }
                .keyboardShortcut(.leftArrow, modifiers: .command)
            Button("다음 채널") { radio.jump(1) }
                .keyboardShortcut(.rightArrow, modifiers: .command)
            Button("채널 찾기") { radio.startScan() }
                .keyboardShortcut("f", modifiers: .command)
            Button("현재 주파수에 표시명 지정…") { radio.beginRename(radio.frequency) }
                .keyboardShortcut("e", modifiers: .command)

            Divider()

            Button("일시정지 / 재생") { radio.togglePause() }
                .keyboardShortcut(.space, modifiers: [])
            Button("15초 뒤로") { radio.skip(-15) }
                .keyboardShortcut(.leftArrow, modifiers: .option)
            Button("15초 앞으로") { radio.skip(15) }
                .keyboardShortcut(.rightArrow, modifiers: .option)
            Button("LIVE로 돌아가기") { radio.goLive() }
                .keyboardShortcut("l", modifiers: [])
            Button("지금부터 녹음 / 녹음 끝내고 저장") { radio.toggleRecording() }
                .keyboardShortcut("r", modifiers: [])

            Divider()

            Button("가장 센 대체 주파수 확인 (AF)") { radio.evaluateAF(manual: true) }
                .keyboardShortcut("a", modifiers: [])
            Button("Mac 스피커로 재생 전환") { radio.speakerMode.toggle() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
        }
    }
}
