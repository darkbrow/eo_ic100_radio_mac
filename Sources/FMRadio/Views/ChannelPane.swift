import SwiftUI
import AppKit

struct ChannelPane: View {
    @EnvironmentObject private var radio: RadioModel
    @Environment(\.palette) private var theme

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 13) {
                Spacer()
                if radio.isEditing {
                    Button {
                        radio.isEditing = false
                    } label: {
                        Text("완료")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(theme.text)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        radio.startScan()
                    } label: {
                        Text("채널 찾기")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(radio.isOn ? theme.text : theme.dim)
                    }
                    .buttonStyle(.plain)
                    .disabled(!radio.isOn)
                }
                OverflowMenu()
            }
            .frame(height: 21)

            ChannelListCard()
            TabBar()
        }
    }
}

struct OverflowMenu: View {
    @EnvironmentObject private var radio: RadioModel
    @Environment(\.palette) private var theme

    var body: some View {
        Menu {
            Button(radio.isEditing ? "편집 완료" : "편집") {
                radio.isEditing.toggle()
            }
            Toggle("Mac 스피커로 재생", isOn: $radio.speakerMode)
            Divider()
            Button("설정…") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
        } label: {
            Image(systemName: "ellipsis")
                .rotationEffect(.degrees(90))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(theme.text)
                .frame(width: 20, height: 20)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

struct ChannelListCard: View {
    @EnvironmentObject private var radio: RadioModel
    @Environment(\.palette) private var theme

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.corner).fill(theme.card)
            switch radio.tab {
            case .channels:
                ChannelList()
            case .favorites:
                FavoriteGrid()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
    }
}

struct ChannelList: View {
    @EnvironmentObject private var radio: RadioModel
    @Environment(\.palette) private var theme

    var body: some View {
        if radio.channels.isEmpty {
            EmptyHint(
                title: "저장된 채널이 없습니다.",
                message: "라디오를 켜고 채널 찾기를 누르면 방송을 찾아 목록에 추가합니다."
            )
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(radio.channels, id: \.self) { f in
                            ChannelRow(freq: f)
                                .id(f)
                            Divider()
                                .overlay(theme.line)
                                .padding(.horizontal, 17)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .onChange(of: radio.frequency) { f in
                    withAnimation {
                        proxy.scrollTo(f, anchor: .center)
                    }
                }
            }
        }
    }
}

struct ChannelRow: View {
    @EnvironmentObject private var radio: RadioModel
    @Environment(\.palette) private var theme
    let freq: Freq

    var body: some View {
        let current = freq == radio.frequency
        let favorite = radio.isFavorite(freq)
        let name = radio.name(for: freq)
        HStack(spacing: 8) {
            if radio.isEditing {
                Button {
                    radio.remove(freq)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.red)
                }
                .buttonStyle(.plain)
                .help("목록에서 삭제")
                Button {
                    radio.beginRename(freq)
                } label: {
                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(theme.accent)
                }
                .buttonStyle(.plain)
                .help("표시명 지정")
            }
            VStack(alignment: .leading, spacing: 1) {
                if let name {
                    Text(name)
                        .font(.system(size: 15))
                        .foregroundStyle(current ? theme.accent : theme.text)
                        .lineLimit(1)
                    Text("\(mhz(freq)) MHz")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.dim)
                } else {
                    Text("\(mhz(freq)) MHz")
                        .font(.system(size: 18))
                        .foregroundStyle(current ? theme.accent : theme.text)
                }
            }
            Spacer()
            Button {
                radio.toggleFavorite(freq)
            } label: {
                Image(systemName: favorite ? "star.fill" : "star")
                    .font(.system(size: 15))
                    .foregroundStyle(favorite ? theme.star : theme.dim)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .onTapGesture {
            radio.tune(freq)
        }
        .contextMenu {
            Button("표시명 지정…") { radio.beginRename(freq) }
            if name != nil {
                Button("표시명 지우기") { radio.setName("", for: freq) }
            }
            Button(favorite ? "즐겨찾기에서 삭제" : "즐겨찾기에 추가") { radio.toggleFavorite(freq) }
            Divider()
            Button("목록에서 삭제") { radio.remove(freq) }
        }
    }
}

struct FavoriteGrid: View {
    @EnvironmentObject private var radio: RadioModel

    var body: some View {
        if radio.favorites.isEmpty {
            EmptyHint(
                title: "즐겨찾기한 채널이 없습니다.",
                message: "주파수 옆이나 채널 목록의 별표를 눌러 추가하세요."
            )
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 13)], spacing: 13) {
                    ForEach(radio.favorites, id: \.self) { f in
                        FavoriteChip(freq: f)
                    }
                }
                .padding(17)
            }
        }
    }
}

struct FavoriteChip: View {
    @EnvironmentObject private var radio: RadioModel
    @Environment(\.palette) private var theme
    let freq: Freq

    var body: some View {
        let current = freq == radio.frequency
        let name = radio.name(for: freq)
        VStack(spacing: 4) {
            Button {
                radio.tune(freq)
            } label: {
                ZStack {
                    Circle()
                        .stroke(current ? theme.accent : theme.chipStroke, lineWidth: current ? 1.5 : 1)
                    Text(mhz(freq))
                        .font(.system(size: 18))
                        .foregroundStyle(current ? theme.chipSelectedText : theme.chipText)
                }
                .frame(width: 77, height: 77)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .overlay(alignment: .topTrailing) {
                if radio.isEditing {
                    Button {
                        radio.toggleFavorite(freq)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 17))
                            .foregroundStyle(Color.white, Color.red)
                    }
                    .buttonStyle(.plain)
                    .help("즐겨찾기에서 삭제")
                }
            }
            .overlay(alignment: .topLeading) {
                if radio.isEditing {
                    Button {
                        radio.beginRename(freq)
                    } label: {
                        Image(systemName: "pencil.circle.fill")
                            .font(.system(size: 17))
                            .foregroundStyle(Color.white, theme.accent)
                    }
                    .buttonStyle(.plain)
                    .help("표시명 지정")
                }
            }

            if let name {
                Text(name)
                    .font(.system(size: 10))
                    .foregroundStyle(theme.secondary)
                    .lineLimit(1)
                    .frame(width: 77)
            }
        }
        .contextMenu {
            Button("표시명 지정…") { radio.beginRename(freq) }
            if name != nil {
                Button("표시명 지우기") { radio.setName("", for: freq) }
            }
            Button("즐겨찾기에서 삭제") { radio.toggleFavorite(freq) }
        }
    }
}

struct EmptyHint: View {
    @Environment(\.palette) private var theme
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.text)
            Text(message)
                .font(.system(size: 10))
                .foregroundStyle(theme.dim)
                .multilineTextAlignment(.center)
        }
        .padding(22)
    }
}

struct TabBar: View {
    @EnvironmentObject private var radio: RadioModel
    @Environment(\.palette) private var theme

    var body: some View {
        HStack(spacing: 0) {
            tabButton("즐겨찾기", .favorites)
            tabButton("채널", .channels)
        }
    }

    private func tabButton(_ title: String, _ value: ListTab) -> some View {
        let selected = radio.tab == value
        return Button {
            radio.tab = value
        } label: {
            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? theme.text : theme.dim)
                Capsule()
                    .fill(selected ? theme.text : Color.clear)
                    .frame(width: 31, height: 2)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
