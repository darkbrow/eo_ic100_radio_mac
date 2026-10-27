import SwiftUI

struct TunerPane: View {
    @EnvironmentObject private var radio: RadioModel
    @Environment(\.palette) private var theme

    /// 켜져 있으면 "지금 재생 중" 아래에 표시명(없으면 주파수)을 보여준다.
    private var title: String {
        guard radio.isOn else { return "라디오를 켜세요." }
        let second = radio.name(for: radio.frequency) ?? "\(mhz(radio.frequency)) MHz"
        return "지금 재생 중\n\(second)"
    }

    var body: some View {
        VStack(spacing: 13) {
            Text(title)
                .font(.system(size: 27, weight: .semibold))
                .foregroundStyle(theme.text)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, minHeight: 70)
            TunerCard()
        }
    }
}

struct TunerCard: View {
    @EnvironmentObject private var radio: RadioModel
    @Environment(\.palette) private var theme

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                PowerButton()
                Spacer()
                MuteButton()
            }
            Spacer(minLength: 0)
            HStack {
                stepButton("chevron.left", delta: -1)
                Spacer(minLength: 0)
                FrequencyReadout()
                Spacer(minLength: 0)
                stepButton("chevron.right", delta: 1)
            }
            Spacer(minLength: 0)
            RDSPanel()
            Spacer(minLength: 6)
            FrequencyDial()
        }
        .padding(17)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: Theme.corner).fill(theme.card))
    }

    private func stepButton(_ symbol: String, delta: Int) -> some View {
        Button {
            radio.step(delta)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 21, weight: .light))
                .foregroundStyle(theme.secondary)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(radio.isOn ? 1 : 0)
        .disabled(!radio.isOn)
    }
}

struct PowerButton: View {
    @EnvironmentObject private var radio: RadioModel
    @Environment(\.palette) private var theme

    var body: some View {
        Button {
            radio.togglePower()
        } label: {
            ZStack {
                Circle().fill(theme.powerFill)
                Circle().stroke(theme.powerBorder, lineWidth: 1)
                if radio.isBusy {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "power")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(radio.isOn ? theme.accent : theme.powerOffIcon)
                }
            }
            .frame(width: 39, height: 39)
        }
        .buttonStyle(.plain)
        .disabled(radio.isBusy)
        .help(radio.isOn ? "라디오 끄기" : "라디오 켜기")
    }
}

struct MuteButton: View {
    @EnvironmentObject private var radio: RadioModel
    @Environment(\.palette) private var theme

    var body: some View {
        Button {
            radio.toggleMute()
        } label: {
            Image(systemName: radio.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 14))
                .foregroundStyle(radio.isMuted ? theme.accent : theme.secondary)
                .frame(width: 39, height: 39)
                .background(
                    Circle().stroke(radio.isMuted ? theme.accent : theme.line, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(!radio.isOn)
        .opacity(radio.isOn ? 1 : 0.4)
        .help(radio.isMuted ? "음소거 해제 (M)" : "음소거 (M)")
    }
}

struct FrequencyReadout: View {
    @EnvironmentObject private var radio: RadioModel
    @Environment(\.palette) private var theme

    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(mhz(radio.frequency))
                    .font(.system(size: 73, weight: .thin))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .overlay(alignment: .topTrailing) {
                        if radio.isOn {
                            favoriteButton.offset(x: 21, y: 6)
                        }
                    }
                Text("MHz")
                    .font(.system(size: 21, weight: .light))
                    .foregroundStyle(radio.isOn ? theme.secondary : theme.dim)
            }
            .foregroundStyle(radio.isOn ? theme.text : theme.dim)
            .contextMenu {
                Button("표시명 지정…") { radio.beginRename(radio.frequency) }
                if radio.name(for: radio.frequency) != nil {
                    Button("표시명 지우기") { radio.setName("", for: radio.frequency) }
                }
                Button(radio.isFavorite(radio.frequency) ? "즐겨찾기에서 삭제" : "즐겨찾기에 추가") {
                    radio.toggleFavorite(radio.frequency)
                }
            }

            if !radio.isOn {
                Text(radio.deviceConnected ? "라디오를 켜세요." : "EO-IC100이 연결되지 않았습니다.")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.dim)
            }
        }
    }

    private var favoriteButton: some View {
        let favorite = radio.isFavorite(radio.frequency)
        return Button {
            radio.toggleFavorite(radio.frequency)
        } label: {
            Image(systemName: favorite ? "star.fill" : "star")
                .font(.system(size: 18))
                .foregroundStyle(favorite ? theme.star : theme.dim)
        }
        .buttonStyle(.plain)
        .help(favorite ? "즐겨찾기에서 삭제" : "즐겨찾기에 추가")
    }
}

/// 86~110MHz 눈금자. 끌어서 주파수를 바꾼다.
struct FrequencyDial: View {
    @EnvironmentObject private var radio: RadioModel
    @Environment(\.palette) private var theme

    private let low = 860
    private let high = 1100
    private let sidePadding: CGFloat = 15
    private let labelHeight: CGFloat = 14

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    drawScale(context, size: size)
                }
                needle(width: width, height: height)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        radio.tune(frequency(atX: value.location.x, width: width))
                    }
            )
        }
        .frame(height: 67)
        .opacity(radio.isOn ? 1 : 0.45)
    }

    private func x(for f: Freq, width: CGFloat) -> CGFloat {
        sidePadding + (width - sidePadding * 2) * CGFloat(f - low) / CGFloat(high - low)
    }

    private func frequency(atX x: CGFloat, width: CGFloat) -> Freq {
        let ratio = (x - sidePadding) / (width - sidePadding * 2)
        return low + Int((ratio * CGFloat(high - low)).rounded())
    }

    private func drawScale(_ context: GraphicsContext, size: CGSize) {
        // 0.5MHz마다 눈금, 3MHz마다 숫자
        for t in stride(from: low, through: high, by: 5) {
            let major = (t - low) % 30 == 0
            let px = x(for: t, width: size.width)
            var path = Path()
            path.move(to: CGPoint(x: px, y: labelHeight + 4))
            path.addLine(to: CGPoint(x: px, y: labelHeight + 4 + (major ? 25 : 14)))
            context.stroke(
                path,
                with: .color(major ? theme.tickMajor : theme.tickMinor),
                lineWidth: major ? 1.5 : 1
            )
            if major {
                context.draw(
                    Text("\(t / 10)")
                        .font(.system(size: 10))
                        .foregroundColor(theme.tickLabel),
                    at: CGPoint(x: px, y: labelHeight / 2),
                    anchor: .center
                )
            }
        }
    }

    private func needle(width: CGFloat, height: CGFloat) -> some View {
        let clamped = min(max(radio.frequency, low), high)
        let px = x(for: clamped, width: width)
        return ZStack {
            Rectangle()
                .fill(theme.accent)
                .frame(width: 2, height: height - 11)
                .position(x: px, y: (height - 11) / 2 + 3)
            Circle()
                .fill(theme.accent)
                .frame(width: 15, height: 15)
                .position(x: px, y: height - 8)
        }
        .animation(.easeOut(duration: 0.12), value: radio.frequency)
        .allowsHitTesting(false)
    }
}
