import SwiftUI

private extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

/// 화면에서 쓰는 색 모음. 뷰는 `@Environment(\.palette)`로 받아 쓴다.
struct Palette {
    let background: Color
    let card: Color
    let text: Color
    let secondary: Color
    let dim: Color
    let line: Color
    let tickMajor: Color
    let tickMinor: Color
    let tickLabel: Color
    let accent: Color
    let onAccent: Color          // 강조색 위에 올리는 글자색
    let star: Color
    let badgeFill: Color
    let badgeText: Color
    let powerFill: Color
    let powerBorder: Color
    let powerOffIcon: Color
    let chipStroke: Color
    let chipText: Color
    let chipSelectedText: Color
    let dialogFill: Color
    let scrim: Color
}

enum Theme {
    /// 삼성 One UI 라디오의 어두운 화면
    static let dark = Palette(
        background: Color(hex: 0x000000),
        card: Color(hex: 0x17171A),
        text: Color.white,
        secondary: Color.white.opacity(0.8),
        dim: Color.white.opacity(0.38),
        line: Color.white.opacity(0.14),
        tickMajor: Color.white.opacity(0.85),
        tickMinor: Color.white.opacity(0.5),
        tickLabel: Color.white.opacity(0.6),
        accent: Color(hex: 0x3D85FF),
        onAccent: Color.black,
        star: Color(hex: 0xFFC200),
        badgeFill: Color.white.opacity(0.14),
        badgeText: Color.white.opacity(0.85),
        powerFill: Color.white,
        powerBorder: Color.clear,
        powerOffIcon: Color.gray,
        chipStroke: Color.white.opacity(0.3),
        chipText: Color.white,
        chipSelectedText: Color(hex: 0x3D85FF),
        dialogFill: Color(hex: 0x242424),
        scrim: Color.black.opacity(0.55)
    )

    /// 라이트 화면 캡처(galaxy-phone-radio7.png)에서 읽은 색
    static let light = Palette(
        background: Color(hex: 0xF6F6F6),
        card: Color(hex: 0xFCFCFC),
        text: Color(hex: 0x202020),
        secondary: Color(hex: 0x5D5D5D),
        dim: Color(hex: 0xA9A9A9),
        line: Color(hex: 0xE6E6E6),
        tickMajor: Color(hex: 0xA8A8A8),
        tickMinor: Color(hex: 0xC5C5C5),
        tickLabel: Color(hex: 0xADADAD),
        accent: Color(hex: 0x45AADC),
        onAccent: Color.white,
        star: Color(hex: 0xF3B900),
        badgeFill: Color.black.opacity(0.07),
        badgeText: Color(hex: 0x5D5D5D),
        powerFill: Color.white,
        powerBorder: Color(hex: 0xE0E0E0),
        powerOffIcon: Color(hex: 0xA9A9A9),
        chipStroke: Color(hex: 0xBABABA),
        chipText: Color(hex: 0xA7A7A7),
        chipSelectedText: Color(hex: 0xA7A7A7),
        dialogFill: Color.white,
        scrim: Color.black.opacity(0.25)
    )

    static func palette(for scheme: ColorScheme) -> Palette {
        scheme == .dark ? dark : light
    }

    /// 카드 모서리 반지름
    static let corner: CGFloat = 20
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = Theme.dark
}

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}
