import SwiftUI

/// 채널/즐겨찾기에 보여줄 이름을 지정하는 시트
struct RenameSheet: View {
    @EnvironmentObject private var radio: RadioModel
    @Environment(\.palette) private var theme
    let target: RenameTarget
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("표시명 지정")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(theme.text)
            Text("\(mhz(target.freq)) MHz")
                .font(.system(size: 11))
                .foregroundStyle(theme.dim)

            TextField("예: KBS Cool FM", text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(save)
                .onChange(of: text) { value in
                    if value.count > RadioModel.maxNameLength {
                        text = String(value.prefix(RadioModel.maxNameLength))
                    }
                }

            Text("채널 목록, 즐겨찾기, 제목에 이 이름이 표시됩니다. 최대 \(RadioModel.maxNameLength)자.")
                .font(.system(size: 10))
                .foregroundStyle(theme.dim)

            HStack {
                if radio.name(for: target.freq) != nil {
                    Button("이름 지우기") {
                        radio.setName("", for: target.freq)
                    }
                }
                Spacer()
                Button("취소") {
                    radio.renameTarget = nil
                }
                .keyboardShortcut(.cancelAction)
                Button("저장") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(17)
        .frame(width: 300)
        .background(theme.card)
        .onAppear {
            text = radio.name(for: target.freq) ?? ""
            focused = true
        }
    }

    private func save() {
        radio.setName(text, for: target.freq)
    }
}
