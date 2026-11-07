import Foundation

/// RDS information decoded so far.
struct RDSInfo: Equatable, Codable {
    var pi: UInt16?          // Station identification code
    var ps = ""              // Station name (8 characters)
    var psComplete = false   // Whether all four PS segments have arrived
    var rt = ""              // Radio text (up to 64 characters)
    var rtComplete = false   // Whether the complete message has arrived
    var pty: Int?            // Program type (0–31)
    var tp = false           // Traffic program
    var ta = false           // Traffic announcement active
    var isMusic: Bool?       // Music (true) / speech (false)
    var afs: [Freq] = []     // Alternative frequencies (100 kHz units)
}

enum RDSNames {
    /// English RDS-standard (European) PTY localization keys. North American RBDS uses different meanings.
    private static let ptyKeys = [
        "", "News", "Current Affairs", "Information", "Sport", "Education", "Drama", "Culture",
        "Science", "Varied", "Pop Music", "Rock Music", "Easy Listening", "Light Classical",
        "Serious Classical", "Other Music", "Weather", "Finance", "Children's", "Social Affairs",
        "Religion", "Phone In", "Travel", "Leisure", "Jazz", "Country", "National Music",
        "Oldies", "Folk", "Documentary", "Alarm Test", "Alarm",
    ]

    static func ptyName(_ code: Int) -> String? {
        guard code > 0, code < ptyKeys.count else { return nil }
        return String(localized: String.LocalizationValue(ptyKeys[code]), table: "RDS")
    }
}

/// Decodes RDS groups (four 16-bit blocks, A–D) into station information.
/// Supports PI, PS (group 0), AF method A (group 0A), PTY/TP/TA/M·S, and radio text (groups 2A/2B).
/// Only ASCII characters are displayed; other RDS character-set values are replaced with spaces.
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

    /// Feeds one error-free group. Returns true if displayable information changed.
    @discardableResult
    func feed(_ blocks: [UInt16]) -> Bool {
        guard blocks.count == 4 else { return false }
        let before = info

        let pi = blocks[0]
        if let current = info.pi, current != pi {
            // Require the same new PI twice to avoid treating a single noisy read as a station change.
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

    // MARK: Group 0: PS, TA, M/S, AF

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
            // Block C in group 0A contains two AF codes.
            decodeAF(UInt8(blocks[2] >> 8), UInt8(blocks[2] & 0x00FF))
        }
    }

    /// AF method A: first code 225–249 (= 224 + count), followed by frequency codes.
    /// Codes 1–204 = 87.6–107.9 MHz (0.1 MHz steps), 205 = filler, 250 = next code is LF/MF.
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

    // MARK: Group 2: Radio text

    private func decodeText(_ blocks: [UInt16], isVersionB: Bool) {
        let blockB = blocks[1]
        let flag = Int((blockB >> 4) & 1)
        if let old = rtFlag, old != flag {
            // A changed A/B flag indicates the start of a new message.
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

        let terminator = rtChars.firstIndex(of: 0x0D)              // 0x0D = end of message
        info.rt = Self.clean(Array(rtChars[..<(terminator ?? rtChars.count)]))
        if let terminator {
            // Complete when all segments through the terminator have arrived.
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
