import Foundation
import CBesUSB

/// EO-IC100 안의 FM 칩 제어. 명령 번호와 응답 형식은 eo-ic100_radio(besfm.py)를 따른다.
/// 주파수는 모두 100kHz 단위 정수로 다룬다 (973 = 97.3MHz).
final class BesFM {
    enum Band: UInt8 {
        case fm87_108 = 0
        case fm76_107 = 1
        case fm76_91 = 2
        case fm64_76 = 3

        /// 100kHz 단위 범위
        var range: ClosedRange<Int> {
            switch self {
            case .fm87_108: return 870...1080
            case .fm76_107: return 760...1070
            case .fm76_91: return 760...910
            case .fm64_76: return 640...760
            }
        }
    }

    struct SeekResult {
        let success: Bool
        let freq: Int      // 100kHz 단위
        let strength: Int
    }

    /// RDS 그룹: 블록 A~D(각 16비트). error == 0일 때만 믿을 수 있다.
    struct RDSGroup {
        let error: Int
        let strength: Int
        let blocks: [UInt16]
    }

    enum Status {
        case seek(SeekResult)
        case tune(SeekResult)
        case rds(RDSGroup)
        case other
    }

    struct ProtocolError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    // bRequest
    private static let requestSet: UInt8 = 161
    private static let requestGet: UInt8 = 162
    private static let requestQuery: UInt8 = 163

    // GET 명령
    private static let getPowerState: UInt8 = 2
    private static let getBand: UInt8 = 3
    private static let getRSSI: UInt8 = 4
    private static let getRDSStatus: UInt8 = 10
    private static let getChannel: UInt8 = 13
    private static let getRecordingMode: UInt8 = 17

    // SET 명령
    private static let setPowerState: UInt8 = 0
    private static let setBand: UInt8 = 1
    private static let setMute: UInt8 = 4
    private static let setVolume: UInt8 = 5
    private static let setSeekStart: UInt8 = 7
    private static let setSeekStop: UInt8 = 8
    private static let setChannel: UInt8 = 9
    private static let setRDSMode: UInt8 = 10
    private static let setRecordingMode: UInt8 = 14

    private let usb: BesUSB
    private let lock = NSLock()

    init() throws {
        usb = try BesUSB.openDevice()
    }

    var productID: UInt16 { usb.productID }

    // MARK: 저수준 전송

    private func transfer(_ request: UInt8, value: UInt16, index: UInt16, length: UInt16) throws -> [UInt8] {
        lock.lock()
        defer { lock.unlock() }
        let data = try usb.controlIn(request: request, value: value, index: index, length: length)
        return [UInt8](data)
    }

    private func set(_ command: UInt8, _ value: UInt16) throws {
        _ = try transfer(Self.requestSet, value: UInt16(command), index: value, length: 1)
    }

    private func get(_ command: UInt8) throws -> [UInt8] {
        try transfer(Self.requestGet, value: UInt16(command), index: 0, length: 2)
    }

    private func firstByte(_ command: UInt8) throws -> UInt8 {
        guard let byte = try get(command).first else {
            throw ProtocolError(message: "장치 응답이 비어 있습니다.")
        }
        return byte
    }

    // MARK: 전원 / 녹음 모드

    func isPowerOn() throws -> Bool {
        try firstByte(Self.getPowerState) != 0
    }

    func isRecording() throws -> Bool {
        try firstByte(Self.getRecordingMode) != 0
    }

    /// 일반 수신 모드 (오디오가 이어폰 안에서만 나온다). 녹음 모드일 때는 아무 것도 하지 않는다.
    func setPower(_ on: Bool) throws {
        if try isRecording() { return }
        try set(Self.setPowerState, on ? 1 : 0)
    }

    /// 녹음 모드 (오디오가 USB 입력으로 나온다). 일반 수신 중일 때는 아무 것도 하지 않는다.
    func setRecording(_ on: Bool) throws {
        if try isPowerOn() { return }
        try set(Self.setRecordingMode, on ? 1 : 0)
    }

    // MARK: 튜너

    /// 0~15
    func setVolume(_ volume: Int) throws {
        try set(Self.setVolume, UInt16(max(0, min(15, volume))))
    }

    func setMute(_ muted: Bool) throws {
        try set(Self.setMute, muted ? 1 : 0)
    }

    func setBand(_ band: Band) throws {
        try set(Self.setBand, UInt16(band.rawValue))
    }

    func bandValue() throws -> UInt8 {
        try firstByte(Self.getBand)
    }

    /// 수신 세기. 단위는 확인되지 않았고, 같은 장치 안에서 값을 비교하는 용도로만 쓴다.
    func rssi() throws -> Int {
        Int(try firstByte(Self.getRSSI))
    }

    /// 칩의 RDS 수신이 켜져 있는지
    func isRDSOn() throws -> Bool {
        try firstByte(Self.getRDSStatus) != 0
    }

    /// RDS 수신 켜기/끄기. 켤 때 큰 팝 소리가 날 수 있다 (eo-ic100_radio의 경고).
    func setRDS(_ on: Bool) throws {
        try set(Self.setRDSMode, on ? 1 : 0)
    }

    /// tenths: 100kHz 단위 (973 → 97.3MHz). 칩은 10kHz 단위를 받는다.
    func setChannel(_ tenths: Int) throws {
        try set(Self.setChannel, UInt16(tenths * 10))
    }

    func channel() throws -> Int {
        let bytes = try get(Self.getChannel)
        guard bytes.count >= 2 else {
            throw ProtocolError(message: "주파수 응답이 올바르지 않습니다.")
        }
        let raw = Int(bytes[0]) | (Int(bytes[1]) << 8)   // 10kHz 단위
        return (raw + 5) / 10
    }

    // MARK: 자동 찾기 (미검증)

    func seek(up: Bool) throws {
        try set(Self.setSeekStart, up ? 1 : 2)
    }

    func seekStop() throws {
        try set(Self.setSeekStop, 0)
    }

    /// 조회(QUERY) 응답 12바이트 원본
    func queryRaw() throws -> [UInt8] {
        try transfer(Self.requestQuery, value: 0, index: 0, length: 12)
    }

    func status() throws -> Status {
        Self.parse(try queryRaw())
    }

    /// 해석 결과와 원본 응답을 함께 돌려준다 (진단용).
    func statusWithRaw() throws -> (status: Status, raw: [UInt8]) {
        let raw = try queryRaw()
        return (Self.parse(raw), raw)
    }

    static func parse(_ r: [UInt8]) -> Status {
        guard r.count >= 5 else { return .other }
        switch r[0] {
        case 0, 1:
            let result = SeekResult(
                success: r[1] != 0,
                freq: ((Int(r[2]) | (Int(r[3]) << 8)) + 5) / 10,
                strength: Int(r[4])
            )
            return r[0] == 0 ? .seek(result) : .tune(result)
        case 2:
            guard r.count >= 11 else { return .other }
            // 응답 바이트 3~10이 블록 A~D이고, 각 블록은 리틀 엔디언 16비트다 (besfm.py의 순서 뒤집기와 같음).
            func word(_ index: Int) -> UInt16 {
                UInt16(r[index]) | (UInt16(r[index + 1]) << 8)
            }
            return .rds(RDSGroup(
                error: Int(r[1]),
                strength: Int(r[2]),
                blocks: [word(3), word(5), word(7), word(9)]
            ))
        default:
            return .other
        }
    }
}
