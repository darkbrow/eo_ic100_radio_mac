import SwiftUI

/// 타임머신 위치와 녹음 시간처럼 자주(초당 4번까지) 바뀌는 값.
/// RadioModel에 두면 메뉴바 명령과 모든 화면이 같이 다시 그려져서 열려 있는 메뉴가 닫히므로,
/// 별도 객체로 분리해 TransportBar만 이 값을 관찰한다.
@MainActor
final class TimelineState: ObservableObject {
    @Published var timeShift = TimeShiftStatus()
    @Published var recordingElapsed: TimeInterval = 0
}
