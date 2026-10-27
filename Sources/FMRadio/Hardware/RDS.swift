import Foundation

/// 지금까지 해석한 RDS 방송 정보
struct RDSInfo: Equatable, Codable {
    var pi: UInt16?          // 방송국 식별 코드
    var ps = ""              // 방송국 이름 (8자)
    var psComplete = false   // PS 조각 4개를 모두 받았는지
    var rt = ""              // 라디오 텍스트 (최대 64자)
    var rtComplete = false   // 문장 끝까지 받았는지
    var pty: Int?            // 프로그램 종류 (0~31)
    var tp = false           // 교통 방송국
    var ta = false           // 교통 방송 중
    var isMusic: Bool?       // 음악(true) / 음성(false)
    var afs: [Freq] = []     // 대체 주파수 (100kHz 단위)
}

enum RDSNames {
    /// RDS 표준(유럽) PTY 이름. 북미 RBDS는 번호 의미가 다르다.
    private static let pty = [
        "", "뉴스", "시사", "정보", "스포츠", "교육", "드라마", "문화",
        "과학", "기타", "팝", "록", "이지 리스닝", "경음악", "클래식", "기타 음악",
        "날씨", "경제", "어린이", "사회", "종교", "청취자 참여", "여행", "레저",
        "재즈", "컨트리", "민족 음악", "올디스", "포크", "다큐멘터리", "경보 시험", "경보",
    ]

    static func ptyName(_ code: Int) -> String? {
        guard code > 0, code < pty.count else { return nil }
        return pty[code]
    }
}

/// RDS 그룹(블록 A~D 16비트 4개)을 모아서 방송 정보로 해석한다.
/// 지원: PI, PS(그룹 0), AF 방식 A(그룹 0A), PTY/TP/TA/M·S, 라디오 텍스트(그룹 2A/2B).
/// RDS 문자 집합은 ASCII 범위만 표시하고 나머지는 공백으로 둔다.
final class RDSDecoder {
    private(set) var info = RDSInfo()

    private var psChars = [UInt8](repeating: 0x20, count: 8)
    private var rtChars = [UInt8](repeating: 0x20, count: 64)
    private var rtFlag: Int?
    private var psSeen = [Bool](repeating: false, count: 4)
    private var rtSeen = [Bool](repeating: false, count: 16)
    private var pendingPI: UInt16?

    private var afExpected = 0
    private var afConsumed = 0
    private var afCollecting = false
    private var afSkipNext = false
    private var afCurrent: [Freq] = []

    func reset() {
        info = RDSInfo()
        psChars = [UInt8](repeating: 0x20, count: 8)
        rtChars = [UInt8](repeating: 0x20, count: 64)
        rtFlag = nil
        psSeen = [Bool](repeating: false, count: 4)
        rtSeen = [Bool](repeating: false, count: 16)
        pendingPI = nil
        afExpected = 0
        afConsumed = 0
        afCollecting = false
        afSkipNext = false
        afCurrent = []
    }

    /// 오류 없는 그룹 하나를 먹인다. 표시할 정보가 바뀌면 true.
    @discardableResult
    func feed(_ blocks: [UInt16]) -> Bool {
        guard blocks.count == 4 else { return false }
        let before = info

        let pi = blocks[0]
        if let current = info.pi, current != pi {
            // 잡음으로 PI가 한 번 틀어지는 경우를 거르기 위해,
            // 같은 새 PI가 두 번 연속 와야 다른 방송으로 본다.
            if pendingPI == pi {
                reset()
                info.pi = pi
            } else {
                pendingPI = pi
                return false
            }
        } else {
            info.pi = pi
            pendingPI = nil
        }

        let blockB = blocks[1]
        let groupType = Int(blockB >> 12)
        let isVersionB = (blockB & 0x0800) != 0
        info.tp = (blockB & 0x0400) != 0
        info.pty = Int((blockB >> 5) & 0x1F)

        switch groupType {
        case 0:
            decodeBasic(blocks, isVersionB: isVersionB)
        case 2:
            decodeText(blocks, isVersionB: isVersionB)
        default:
            break
        }
        return info != before
    }

    // MARK: 그룹 0: PS, TA, M/S, AF

    private func decodeBasic(_ blocks: [UInt16], isVersionB: Bool) {
        let blockB = blocks[1]
        info.ta = (blockB & 0x0010) != 0
        info.isMusic = (blockB & 0x0008) != 0

        let segment = Int(blockB & 0x0003)
        let blockD = blocks[3]
        psChars[segment * 2] = UInt8(blockD >> 8)
        psChars[segment * 2 + 1] = UInt8(blockD & 0x00FF)
        info.ps = Self.clean(psChars)
        psSeen[segment] = true
        info.psComplete = !psSeen.contains(false)

        if !isVersionB {
            // 0A 그룹의 블록 C에는 AF 코드 두 개가 들어 있다.
            decodeAF(UInt8(blocks[2] >> 8), UInt8(blocks[2] & 0x00FF))
        }
    }

    /// AF 방식 A: 목록의 첫 코드는 225~249(= 224 + 개수), 이어서 주파수 코드가 두 개씩 온다.
    /// 코드 1~204 = 87.6~107.9MHz(0.1MHz 간격), 205 = 채움, 250 = 다음 코드가 LF/MF.
    private func decodeAF(_ first: UInt8, _ second: UInt8) {
        let codes: [UInt8]
        if (225...249).contains(first) {
            afExpected = Int(first) - 224
            afConsumed = 0
            afCurrent = []
            afCollecting = true
            afSkipNext = false
            codes = [second]
        } else {
            guard afCollecting else { return }
            codes = [first, second]
        }

        for code in codes {
            guard afConsumed < afExpected else { break }
            if afSkipNext {
                afSkipNext = false
                afConsumed += 1
                continue
            }
            switch code {
            case 205:
                continue
            case 250:
                afSkipNext = true
            case 1...204:
                afCurrent.append(875 + Int(code))
                afConsumed += 1
            default:
                break
            }
        }

        if afCollecting && afConsumed >= afExpected {
            info.afs = Array(Set(afCurrent)).sorted()
            afCollecting = false
        }
    }

    // MARK: 그룹 2: 라디오 텍스트

    private func decodeText(_ blocks: [UInt16], isVersionB: Bool) {
        let blockB = blocks[1]
        let flag = Int((blockB >> 4) & 1)
        if let old = rtFlag, old != flag {
            // A/B 플래그가 바뀌면 새 문장이 시작된 것이다.
            rtChars = [UInt8](repeating: 0x20, count: 64)
            rtSeen = [Bool](repeating: false, count: 16)
        }
        rtFlag = flag

        let address = Int(blockB & 0x000F)
        if isVersionB {
            let position = address * 2
            rtChars[position] = UInt8(blocks[3] >> 8)
            rtChars[position + 1] = UInt8(blocks[3] & 0x00FF)
        } else {
            let position = address * 4
            rtChars[position] = UInt8(blocks[2] >> 8)
            rtChars[position + 1] = UInt8(blocks[2] & 0x00FF)
            rtChars[position + 2] = UInt8(blocks[3] >> 8)
            rtChars[position + 3] = UInt8(blocks[3] & 0x00FF)
        }

        rtSeen[address] = true

        let terminator = rtChars.firstIndex(of: 0x0D)              // 0x0D = 문장 끝
        info.rt = Self.clean(Array(rtChars[..<(terminator ?? rtChars.count)]))
        if let terminator {
            // 문장 끝이 들어 있는 조각까지 모두 받았으면 완성
            let unit = isVersionB ? 2 : 4
            let lastSegment = min(terminator / unit, 15)
            info.rtComplete = !rtSeen[0...lastSegment].contains(false)
        } else {
            info.rtComplete = !rtSeen.contains(false)
        }
    }

    private static func clean(_ bytes: [UInt8]) -> String {
        let characters = bytes.map { byte -> Character in
            (0x20...0x7E).contains(byte) ? Character(UnicodeScalar(byte)) : " "
        }
        return String(characters).trimmingCharacters(in: .whitespaces)
    }
}
