import SwiftUI
import AppKit
import AVFoundation
import CBesUSB

/// 주파수는 100kHz 단위 정수 (973 = 97.3MHz)
typealias Freq = Int

func mhz(_ f: Freq) -> String {
    String(format: "%.1f", Double(f) / 10)
}

enum ListTab {
    case favorites
    case channels
}

/// 화면 모드. 기본은 다크이고, "시스템"을 고르면 macOS의 모드를 따른다.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case dark
    case light
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dark: return "다크"
        case .light: return "라이트"
        case .system: return "시스템"
        }
    }

    /// nil이면 시스템 설정을 따른다.
    var colorScheme: ColorScheme? {
        switch self {
        case .dark: return .dark
        case .light: return .light
        case .system: return nil
        }
    }
}

enum BandChoice: String, CaseIterable, Identifiable {
    case chipDefault
    case fm87_108
    case fm76_107

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chipDefault: return "장치 기본값 (변경 안 함)"
        case .fm87_108: return "87.0–108.0 MHz"
        case .fm76_107: return "76.0–107.0 MHz"
        }
    }

    var band: BesFM.Band? {
        switch self {
        case .chipDefault: return nil
        case .fm87_108: return .fm87_108
        case .fm76_107: return .fm76_107
        }
    }
}

/// RDS가 왜 안 들어오는지 가르기 위한 수신 통계 (설정 > 진단).
/// 조회를 60ms마다 하므로 "같은 응답을 여러 번 읽은 횟수"도 포함한다.
struct RDSDebug: Equatable {
    var chipRDSOn: Bool?
    var rdsEvents = 0
    var tuneEvents = 0
    var seekEvents = 0
    var otherEvents = 0
    var goodGroups = 0
    var badGroups = 0
    var lastError: Int?
    var lastStrength: Int?
    var lastGroup = ""
    var lastRaw = ""
}

/// 표시명을 지정 중인 주파수 (시트를 띄우는 데 쓴다)
struct RenameTarget: Identifiable {
    let freq: Freq
    var id: Int { freq }
}

struct ScanState {
    var isRunning = false
    var current: Freq?
    var found = 0
}

enum RadioError: LocalizedError {
    case micDenied
    case noInputDevice
    case recordModeFailed

    var errorDescription: String? {
        switch self {
        case .micDenied:
            return "마이크 권한이 필요합니다. 설정 > 권한에서 허용해 주세요."
        case .noInputDevice:
            return "이어폰 입력 장치를 찾지 못했습니다. 설정에서 입력 장치를 선택해 주세요. (설정 > 진단에서 장치 목록을 볼 수 있습니다)"
        case .recordModeFailed:
            return "라디오를 켜지 못했습니다. 이어폰을 다시 연결해 보세요."
        }
    }
}

/// 라디오의 상태와 동작.
/// 칩 제어는 EO-IC100의 "녹음 모드"를 쓴다. 이 모드에서만 라디오 오디오가 USB 입력으로 나와
/// 맥이 원하는 출력 장치로 재생하고, 타임머신/녹음을 할 수 있다.
@MainActor
final class RadioModel: ObservableObject {
    private enum Key {
        static let frequency = "frequency"
        static let channels = "channels"
        static let favorites = "favorites"
        static let autoOff = "autoOffMinutes"
        static let gain = "gainDB"
        static let outputUID = "outputUID"
        static let inputUID = "inputUID"
        static let speaker = "speakerMode"
        static let band = "bandChoice"
        static let timeMachine = "timeMachineMinutes"
        static let recordingFolder = "recordingFolder"
        static let rds = "rdsEnabled"
        static let afAuto = "afAutoEnabled"
        static let rdsCache = "rdsCache"
        static let appearance = "appearanceMode"
        static let channelNames = "channelNames"
        static let syncSystemOutput = "syncSystemOutput"
        static let outputOverride = "outputOverride"
    }

    /// 앱 전체가 함께 쓰는 하나의 모델 (App 구조체가 관찰하지 않도록 @StateObject 대신 공유 인스턴스를 쓴다).
    static let shared = RadioModel()

    // MARK: 화면 상태

    @Published private(set) var isOn = false
    @Published private(set) var isBusy = false
    @Published private(set) var isMuted = false
    @Published private(set) var deviceConnected = false
    @Published private(set) var productID: UInt16 = 0
    @Published private(set) var usbProductName: String?
    @Published private(set) var chipBand: BesFM.Band?
    @Published private(set) var audioDevices: [AudioDevice] = []
    @Published private(set) var toast: String?
    @Published private(set) var scan = ScanState()
    @Published private(set) var rds = RDSInfo()
    @Published private(set) var rdsDemo = false
    @Published private(set) var afBusy = false
    @Published private(set) var isRecording = false
    @Published var tab: ListTab = .channels
    @Published var isEditing = false
    /// 사용자가 지정한 표시명 (주파수 → 이름). 채널 목록, 즐겨찾기, 제목에 쓴다.
    @Published private(set) var names: [Freq: String] = [:]
    @Published var renameTarget: RenameTarget?

    // MARK: 저장되는 상태

    @Published private(set) var frequency: Freq {
        didSet { UserDefaults.standard.set(frequency, forKey: Key.frequency) }
    }
    @Published private(set) var channels: [Freq] {
        didSet { UserDefaults.standard.set(channels, forKey: Key.channels) }
    }
    @Published private(set) var favorites: [Freq] {
        didSet { UserDefaults.standard.set(favorites, forKey: Key.favorites) }
    }

    // MARK: 설정

    @Published var appearance: AppearanceMode {
        didSet {
            UserDefaults.standard.set(appearance.rawValue, forKey: Key.appearance)
            applyAppearance()
        }
    }

    /// 0 = 사용 안 함
    @Published var autoOffMinutes: Int {
        didSet {
            UserDefaults.standard.set(autoOffMinutes, forKey: Key.autoOff)
            scheduleAutoOff()
        }
    }
    @Published var gainDB: Double {
        didSet {
            UserDefaults.standard.set(gainDB, forKey: Key.gain)
            audio.gainDB = Float(gainDB)
        }
    }
    /// 빈 문자열 = 시스템 기본 출력
    @Published var outputUID: String {
        didSet {
            UserDefaults.standard.set(outputUID, forKey: Key.outputUID)
            applyOutputChange()
        }
    }
    /// 빈 문자열 = 자동 감지
    @Published var inputUID: String {
        didSet { UserDefaults.standard.set(inputUID, forKey: Key.inputUID) }
    }
    /// 재생 중인 장치로 시스템 기본 출력 장치를 맞춘다 (볼륨 키가 그 장치를 조절하도록).
    @Published var syncSystemOutputEnabled: Bool {
        didSet {
            UserDefaults.standard.set(syncSystemOutputEnabled, forKey: Key.syncSystemOutput)
            syncSystemOutput()
        }
    }
    @Published var speakerMode: Bool {
        didSet {
            UserDefaults.standard.set(speakerMode, forKey: Key.speaker)
            applyOutputChange()
        }
    }
    @Published var bandChoice: BandChoice {
        didSet { UserDefaults.standard.set(bandChoice.rawValue, forKey: Key.band) }
    }
    /// 타임머신 버퍼 길이(분). 0 = 사용 안 함. 다음에 라디오를 켤 때 적용된다.
    @Published var timeMachineMinutes: Int {
        didSet { UserDefaults.standard.set(timeMachineMinutes, forKey: Key.timeMachine) }
    }
    @Published var recordingFolder: String {
        didSet { UserDefaults.standard.set(recordingFolder, forKey: Key.recordingFolder) }
    }
    @Published var rdsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(rdsEnabled, forKey: Key.rds)
            applyRDSSetting()
        }
    }
    @Published var afAutoEnabled: Bool {
        didSet { UserDefaults.standard.set(afAutoEnabled, forKey: Key.afAuto) }
    }

    // MARK: 내부

    /// 주파수별로 마지막에 받은 RDS 정보. 새로 수신되기 전에 흐리게 보여준다.
    private var rdsCache: [Freq: RDSInfo] = [:]
    private var rdsCacheDirty = false
    private var lastRDSCacheSave = Date.distantPast
    /// 시스템 기본 출력 장치를 우리가 바꿔 둔 기록 (원래 장치, 우리가 바꾼 장치).
    private struct OutputOverride: Codable {
        var originalUID: String
        var overrideUID: String
    }
    private var outputOverride: OutputOverride?
    private var debugAccum = RDSDebug()
    private var demoTask: Task<Void, Never>?
    /// 자주 바뀌는 타임머신/녹음 시간 (모델과 분리해 메뉴가 다시 그려지지 않게 한다)
    let timeline = TimelineState()
    private let audio = AudioBridge()
    private let rdsDecoder = RDSDecoder()
    private var fm: BesFM?
    private var pollTimer: Timer?
    private var tuneTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var autoOffTask: Task<Void, Never>?
    private var scanTask: Task<Void, Never>?
    private var rdsTask: Task<Void, Never>?
    private var uiTask: Task<Void, Never>?
    private var afTask: Task<Void, Never>?
    private var rdsSwitching = false
    private var hadRDS = false
    private var lastGoodRDS: Date?
    private var lastAFCheck = Date.distantPast

    init() {
        let store = UserDefaults.standard
        frequency = store.object(forKey: Key.frequency) as? Int ?? 915
        channels = (store.array(forKey: Key.channels) as? [Int]) ?? []
        favorites = (store.array(forKey: Key.favorites) as? [Int]) ?? []
        autoOffMinutes = store.integer(forKey: Key.autoOff)
        gainDB = store.object(forKey: Key.gain) as? Double ?? 0
        outputUID = store.string(forKey: Key.outputUID) ?? ""
        inputUID = store.string(forKey: Key.inputUID) ?? ""
        speakerMode = store.bool(forKey: Key.speaker)
        syncSystemOutputEnabled = store.object(forKey: Key.syncSystemOutput) as? Bool ?? true
        bandChoice = BandChoice(rawValue: store.string(forKey: Key.band) ?? "") ?? .chipDefault
        timeMachineMinutes = store.object(forKey: Key.timeMachine) as? Int ?? 15
        recordingFolder = store.string(forKey: Key.recordingFolder)
            ?? (NSHomeDirectory() as NSString).appendingPathComponent("Music/FM 라디오")
        rdsEnabled = store.object(forKey: Key.rds) as? Bool ?? true
        afAutoEnabled = store.bool(forKey: Key.afAuto)
        appearance = AppearanceMode(rawValue: store.string(forKey: Key.appearance) ?? "") ?? .dark
        loadRDSCache()
        loadNames()
        loadOutputOverride()
        restoreSystemOutput()   // 이전 실행이 비정상 종료되어 시스템 출력이 바뀐 채 남았으면 되돌린다.
        applyAppearance()

        audio.gainDB = Float(gainDB)
        refreshHardware()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshHardware()
            }
        }
    }

    // MARK: 화면 모드

    /// 화면 모드를 앱 전체(메인 창, 설정 창, 시트, 메뉴, 기본 컨트롤)에 바로 적용한다.
    /// 창마다 `.preferredColorScheme`을 쓰면 "시스템"으로 되돌릴 때 이전 모드가 남을 수 있어서,
    /// AppKit의 앱 모양(appearance)을 직접 지정하고 nil이면 시스템 설정을 따르게 한다.
    private func applyAppearance() {
        switch appearance {
        case .dark:
            NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        case .light:
            NSApplication.shared.appearance = NSAppearance(named: .aqua)
        case .system:
            NSApplication.shared.appearance = nil
        }
    }

    // MARK: 파생 값

    var outputDevices: [AudioDevice] { audioDevices.filter { $0.outputChannels > 0 } }
    var inputDevices: [AudioDevice] { audioDevices.filter { $0.inputChannels > 0 } }

    /// 튜닝 가능한 범위 (100kHz 단위)
    var bandRange: ClosedRange<Freq> {
        if let band = bandChoice.band { return band.range }
        return chipBand?.range ?? 870...1070
    }

    var micStatusText: String {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return "허용됨"
        case .notDetermined: return "아직 요청하지 않음"
        case .denied: return "거부됨"
        case .restricted: return "제한됨"
        @unknown default: return "알 수 없음"
        }
    }

    func isFavorite(_ f: Freq) -> Bool {
        favorites.contains(f)
    }

    /// 화면에 보여줄 RDS 정보.
    /// - 아직 아무것도 못 받았으면 이 주파수에서 마지막으로 받은 정보(저장된 값)를 보여준다.
    /// - 받기 시작했지만 PS/라디오 텍스트가 덜 모였으면, PI가 같은 저장된 값으로 빈 곳을 채운다.
    var displayRDS: RDSInfo {
        let cached = rdsCache[frequency]
        guard rds.pi != nil else { return cached ?? RDSInfo() }
        guard let cached, cached.pi == rds.pi else { return rds }
        var result = rds
        if !rds.psComplete, !cached.ps.isEmpty {
            result.ps = cached.ps
            result.psComplete = cached.psComplete
        }
        if !rds.rtComplete, !cached.rt.isEmpty {
            result.rt = cached.rt
            result.rtComplete = cached.rtComplete
        }
        if rds.afs.isEmpty { result.afs = cached.afs }
        return result
    }

    /// 새로 받은 정보가 없어서 저장된 정보를 보여주는 중인지
    var rdsIsStale: Bool {
        rds.pi == nil && rdsCache[frequency] != nil
    }

    func clearRDSCache() {
        rdsCache = [:]
        rdsCacheDirty = false
        UserDefaults.standard.removeObject(forKey: Key.rdsCache)
        objectWillChange.send()
        showToast("저장된 RDS 정보를 지웠습니다.")
    }

    /// 이어폰이 인식되지 않을 때 원인을 찾기 위한 정보 (설정 > 진단)
    func diagnosticReport() -> String {
        var lines: [String] = []
        lines.append("EO-IC100 인식: \(deviceConnected ? "예" : "아니오")  PID \(String(format: "0x%04x", productID))  이름 \(usbProductName ?? "-")")
        lines.append("마이크 권한: \(micStatusText)")
        if isOn {
            let piText = rds.pi.map { String(format: "%04X", $0) } ?? "-"
            lines.append("RDS: PI \(piText)  PS \(rds.ps.isEmpty ? "-" : rds.ps)  AF \(rds.afs.count)개")
            lines.append("타임머신: \(timeline.timeShift.isActive ? String(format: "%.0f초 저장됨", timeline.timeShift.buffered) : "꺼짐")")
            let d = debugAccum
            lines.append("저장된 RDS 정보: \(rdsCache.count)개 방송국")
            lines.append("RDS 칩 상태: \(d.chipRDSOn.map { $0 ? "켜짐" : "꺼짐" } ?? "-")  앱 설정: \(rdsEnabled ? "켜짐" : "꺼짐")")
            lines.append("조회 응답 종류: RDS \(d.rdsEvents) / 튜닝 \(d.tuneEvents) / 찾기 \(d.seekEvents) / 기타 \(d.otherEvents)")
            lines.append("RDS 그룹: 정상 \(d.goodGroups) / 오류 \(d.badGroups)  마지막 오류값 \(d.lastError.map { String($0) } ?? "-")  세기값 \(d.lastStrength.map { String($0) } ?? "-")")
            lines.append("마지막 그룹(A B C D): \(d.lastGroup.isEmpty ? "-" : d.lastGroup)")
            lines.append("마지막 응답 12바이트: \(d.lastRaw.isEmpty ? "-" : d.lastRaw)")
        }
        lines.append("")
        lines.append(BesUSB.diagnosticReport())
        lines.append("")
        lines.append("오디오 장치 (이름 [입력/출력 채널]  UID):")
        for device in audioDevices {
            var tags = "\(device.inputChannels)/\(device.outputChannels)"
            if device.isUSB { tags += ", USB" }
            if device.isBuiltIn { tags += ", 내장" }
            lines.append("- \(device.name) [\(tags)]  \(device.uid)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: 하드웨어 감시

    func refreshHardware() {
        let devices = AudioDevices.all()
        if devices != audioDevices { audioDevices = devices }

        // 우리가 바꿔 둔 시스템 출력 장치를 사용자가 직접 다른 것으로 바꿨으면, 더 이상 관리하지 않는다.
        if let record = outputOverride,
           let current = AudioDevices.defaultOutputID(),
           let device = devices.first(where: { $0.id == current }),
           device.uid != record.overrideUID {
            outputOverride = nil
            persistOutputOverride()
        }

        let pid = BesUSB.presentProductID()
        if pid != productID { productID = pid }
        let name = pid != 0 ? BesUSB.presentProductName() : nil
        if name != usbProductName { usbProductName = name }
        let present = pid != 0
        if present != deviceConnected {
            deviceConnected = present
            if !present && (isOn || isBusy) {
                showToast("EO-IC100 연결이 끊겼습니다.")
                teardown()
            }
        }
    }

    // MARK: 전원

    func togglePower() {
        if isOn { powerOff() } else { powerOn() }
    }

    func powerOn() {
        guard !isOn, !isBusy else { return }
        guard deviceConnected else {
            showToast("라디오를 켜려면 EO-IC100을 연결하세요.")
            return
        }
        isBusy = true
        Task { [self] in
            defer { isBusy = false }
            do {
                guard await requestMicAccess() else { throw RadioError.micDenied }
                let chip = try BesFM()
                fm = chip
                try await startChip(chip)
                try startAudio()
                isOn = true
                startMonitors()
                scheduleAutoOff()
                syncSystemOutput()
            } catch {
                teardown()
                showToast(error.localizedDescription)
            }
        }
    }

    func powerOff() {
        teardown()
    }

    /// 앱 종료 직전에 호출: 라디오를 끈다.
    func shutdown() {
        teardown()
    }

    private func startChip(_ chip: BesFM) async throws {
        // 일반 수신 모드가 켜져 있으면 먼저 끈다 (두 모드는 동시에 켤 수 없다).
        if try chip.isPowerOn() { try chip.setPower(false) }
        try chip.setRecording(true)
        try await Task.sleep(nanoseconds: 200_000_000)
        guard try chip.isRecording() else { throw RadioError.recordModeFailed }

        try chip.setVolume(15)
        if let band = bandChoice.band { try chip.setBand(band) }
        if let raw = try? chip.bandValue() { chipBand = BesFM.Band(rawValue: raw) }

        // RDS를 켜면 팝 소리가 날 수 있어서, 오디오를 시작하기 전에 설정한다.
        try? chip.setRDS(rdsEnabled)
        debugAccum = RDSDebug()
        debugAccum.chipRDSOn = try? chip.isRDSOn()

        let target = clamp(frequency)
        try chip.setChannel(target)
        frequency = target
    }

    private func startAudio() throws {
        let devices = AudioDevices.all()
        guard let input = resolveInput(in: devices) else { throw RadioError.noInputDevice }
        try audio.start(
            input: input,
            output: resolveOutput(in: devices),
            timeMachineMinutes: timeMachineMinutes
        )
        updateAudioState()
    }

    private func resolveInput(in devices: [AudioDevice]) -> AudioDevice? {
        if !inputUID.isEmpty,
           let chosen = devices.first(where: { $0.uid == inputUID && $0.inputChannels > 0 }) {
            return chosen
        }
        return AudioDevices.guessEarphoneInput(in: devices, productName: usbProductName)
    }

    /// nil = 시스템 기본 출력
    private func resolveOutput(in devices: [AudioDevice]) -> AudioDevice? {
        if speakerMode, let speaker = AudioDevices.builtInSpeaker(in: devices) {
            return speaker
        }
        if !outputUID.isEmpty {
            return devices.first(where: { $0.uid == outputUID && $0.outputChannels > 0 })
        }
        return nil
    }

    private func applyOutputChange() {
        guard isOn else { return }
        let target = resolveOutput(in: AudioDevices.all())
        if target == nil {
            // 시스템 기본 출력을 따르는 경우: 기본 장치를 먼저 원래대로 돌려놓고 엔진을 다시 만든다.
            restoreSystemOutput()
        }
        do {
            try audio.setOutput(target)
        } catch {
            showToast("출력 장치를 바꾸지 못했습니다.")
        }
        if target != nil { syncSystemOutput() }
    }

    // MARK: 시스템 출력 장치 맞추기

    /// 맥의 볼륨 키와 HUD, 이어폰의 볼륨 버튼은 "시스템 기본 출력 장치"만 조절한다.
    /// 앱이 소리를 다른 장치(Mac 스피커 등)로 보내면 키가 소리 나지 않는 장치를 조절하게 되므로,
    /// 켜져 있는 동안은 시스템 기본 출력을 재생 중인 장치로 맞추고, 끄면 원래 장치로 되돌린다.
    private func syncSystemOutput() {
        guard syncSystemOutputEnabled, isOn else {
            restoreSystemOutput()
            return
        }
        let devices = AudioDevices.all()
        guard let target = resolveOutput(in: devices) else {
            restoreSystemOutput()     // 시스템 기본 출력을 따르는 설정이면 바꿀 필요가 없다.
            return
        }
        guard let current = AudioDevices.defaultOutputID(), current != target.id else { return }

        if var record = outputOverride {
            record.overrideUID = target.uid           // 이미 바꿔 둔 상태에서 다른 장치로 옮기는 경우
            outputOverride = record
        } else if let original = devices.first(where: { $0.id == current }) {
            outputOverride = OutputOverride(originalUID: original.uid, overrideUID: target.uid)
        }
        persistOutputOverride()
        if !AudioDevices.setDefaultOutput(target.id) {
            outputOverride = nil
            persistOutputOverride()
            showToast("시스템 출력 장치를 바꾸지 못했습니다. 볼륨 키가 다른 장치를 조절할 수 있습니다.")
        }
    }

    /// 우리가 바꿔 둔 시스템 출력 장치를 원래대로 돌린다.
    /// 그 사이에 사용자가 직접 다른 장치로 바꿨다면 건드리지 않는다.
    private func restoreSystemOutput() {
        guard let record = outputOverride else { return }
        outputOverride = nil
        persistOutputOverride()
        let devices = AudioDevices.all()
        guard let current = AudioDevices.defaultOutputID(),
              devices.first(where: { $0.id == current })?.uid == record.overrideUID,
              let original = devices.first(where: { $0.uid == record.originalUID && $0.outputChannels > 0 }) else { return }
        AudioDevices.setDefaultOutput(original.id)
    }

    private func persistOutputOverride() {
        if let outputOverride, let data = try? JSONEncoder().encode(outputOverride) {
            UserDefaults.standard.set(data, forKey: Key.outputOverride)
        } else {
            UserDefaults.standard.removeObject(forKey: Key.outputOverride)
        }
    }

    private func loadOutputOverride() {
        guard let data = UserDefaults.standard.data(forKey: Key.outputOverride) else { return }
        outputOverride = try? JSONDecoder().decode(OutputOverride.self, from: data)
    }

    private func teardown() {
        persistRDSCacheIfNeeded(force: true)
        stopRecording()
        stopMonitors()
        if scan.isRunning, let fm { try? fm.seekStop() }
        scanTask?.cancel()
        scanTask = nil
        scan = ScanState()
        afTask?.cancel()
        afTask = nil
        afBusy = false
        rdsSwitching = false
        autoOffTask?.cancel()
        autoOffTask = nil
        tuneTask?.cancel()
        tuneTask = nil
        audio.stop()
        restoreSystemOutput()
        if let fm {
            try? fm.setRecording(false)
            try? fm.setPower(false)
        }
        fm = nil
        demoTask?.cancel()
        demoTask = nil
        rdsDemo = false
        rdsDecoder.reset()
        rds = RDSInfo()
        timeline.timeShift = TimeShiftStatus()
        isOn = false
    }

    private func requestMicAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
    }

    // MARK: 음소거 / 오디오 상태

    func toggleMute() {
        isMuted.toggle()
        updateAudioState()
    }

    /// 사용자 음소거, 그리고 채널 찾기/AF 확인/RDS 전환 중에는 소리를 끊고 타임머신 기록도 건너뛴다.
    private func updateAudioState() {
        let suspended = scan.isRunning || afBusy || rdsSwitching
        audio.muted = isMuted || suspended
        audio.setCaptureSuspended(suspended)
    }

    // MARK: 튜닝

    private func clamp(_ f: Freq) -> Freq {
        let range = bandRange
        return min(max(f, range.lowerBound), range.upperBound)
    }

    func tune(_ f: Freq) {
        let target = clamp(f)
        guard target != frequency else { return }
        frequency = target
        guard isOn else { return }
        // 방송국이 바뀌었으므로 이전 방송의 타임머신 기록과 RDS 정보를 버린다.
        audio.flushTimeShift()
        resetRDS()
        guard !scan.isRunning, !afBusy else { return }
        // 다이얼을 끌 때 명령이 쏟아지지 않도록 짧게 모아서 보낸다.
        tuneTask?.cancel()
        tuneTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 40_000_000)
            guard !Task.isCancelled, let self, self.isOn, !self.scan.isRunning, let chip = self.fm else { return }
            try? chip.setChannel(target)
        }
    }

    func step(_ delta: Int) {
        tune(frequency + delta)
    }

    /// 저장된 채널/즐겨찾기 중 이전(-1)/다음(+1)으로 이동
    func jump(_ direction: Int) {
        let all = Array(Set(channels + favorites)).sorted()
        guard !all.isEmpty else { return }
        if direction > 0 {
            tune(all.first(where: { $0 > frequency }) ?? all[0])
        } else {
            tune(all.last(where: { $0 < frequency }) ?? all[all.count - 1])
        }
    }

    // MARK: 채널 / 즐겨찾기

    func toggleFavorite(_ f: Freq) {
        if let index = favorites.firstIndex(of: f) {
            favorites.remove(at: index)
        } else {
            favorites.append(f)
            favorites.sort()
            if !channels.contains(f) {
                channels.append(f)
                channels.sort()
            }
        }
    }

    func remove(_ f: Freq) {
        channels.removeAll { $0 == f }
        favorites.removeAll { $0 == f }
        if names.removeValue(forKey: f) != nil { persistNames() }
    }

    // MARK: 표시명

    static let maxNameLength = 24

    func name(for f: Freq) -> String? {
        names[f]
    }

    func beginRename(_ f: Freq) {
        renameTarget = RenameTarget(freq: f)
    }

    /// 빈 문자열이면 표시명을 지운다. 이름을 붙인 주파수는 채널 목록에도 넣는다.
    func setName(_ raw: String, for f: Freq) {
        let trimmed = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxNameLength))
        if trimmed.isEmpty {
            names.removeValue(forKey: f)
        } else {
            names[f] = trimmed
            if !channels.contains(f) {
                channels.append(f)
                channels.sort()
            }
        }
        persistNames()
        renameTarget = nil
    }

    private func persistNames() {
        let encodable = Dictionary(uniqueKeysWithValues: names.map { (String($0.key), $0.value) })
        if let data = try? JSONEncoder().encode(encodable) {
            UserDefaults.standard.set(data, forKey: Key.channelNames)
        }
    }

    private func loadNames() {
        guard let data = UserDefaults.standard.data(forKey: Key.channelNames),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else { return }
        for (key, value) in decoded {
            if let freq = Int(key) { names[freq] = value }
        }
    }

    // MARK: 자동 찾기 (하드웨어 seek)

    func startScan() {
        guard isOn, let chip = fm else {
            showToast("채널을 찾으려면 라디오를 켜세요.")
            return
        }
        guard !scan.isRunning, !afBusy else { return }

        let range = bandRange
        let original = frequency
        scan = ScanState(isRunning: true, current: nil, found: 0)
        updateAudioState()

        scanTask = Task { [weak self] in
            var found: [Freq] = []
            do {
                try chip.setChannel(range.lowerBound)
                try await Task.sleep(nanoseconds: 300_000_000)
                var last = range.lowerBound - 1
                for _ in 0..<200 {
                    try Task.checkCancellation()
                    try chip.seek(up: true)
                    guard let self else { break }
                    guard let result = try await self.waitSeekResult(chip, ignoring: last),
                          result.success,
                          result.freq > last,
                          range.contains(result.freq) else { break }
                    last = result.freq
                    found.append(result.freq)
                    self.scan.current = result.freq
                    self.scan.found = found.count
                }
            } catch {
                // 취소 또는 USB 오류: 지금까지 찾은 채널만 반영한다.
            }
            self?.finishScan(found: found, restoring: original)
        }
    }

    func cancelScan() {
        scanTask?.cancel()
    }

    private func waitSeekResult(_ chip: BesFM, ignoring last: Freq) async throws -> BesFM.SeekResult? {
        let deadline = Date().addingTimeInterval(6)
        while Date() < deadline {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: 80_000_000)
            if case .seek(let result)? = try? chip.status(), result.freq != last {
                return result
            }
        }
        return nil
    }

    private func finishScan(found: [Freq], restoring original: Freq) {
        guard scan.isRunning else { return }
        scan = ScanState()
        scanTask = nil
        updateAudioState()
        if isOn, let chip = fm {
            try? chip.seekStop()
            try? chip.setChannel(frequency == original ? original : frequency)
        }
        if found.isEmpty {
            showToast("찾은 채널이 없습니다.")
        } else {
            channels = Array(Set(channels).union(found)).sorted()
            tab = .channels
            showToast("채널 \(found.count)개를 찾았습니다.")
        }
    }

    // MARK: 모니터 (RDS 읽기, 타임머신/녹음 상태)

    private func startMonitors() {
        stopMonitors()
        resetRDS()

        rdsTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000)
                guard let self else { return }
                self.rdsTick()
            }
        }
        uiTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard let self else { return }
                self.uiTick()
            }
        }
    }

    private func stopMonitors() {
        rdsTask?.cancel()
        rdsTask = nil
        uiTask?.cancel()
        uiTask = nil
    }

    private func uiTick() {
        guard isOn else { return }
        let status = audio.timeShiftStatus()
        if status != timeline.timeShift { timeline.timeShift = status }
        persistRDSCacheIfNeeded()

        let recording = audio.recorder.isRecording
        if recording {
            timeline.recordingElapsed = audio.recorder.elapsed
        } else if isRecording {
            // 사용자가 멈춘 것이 아니라 디스크 오류 등으로 녹음이 끊긴 경우
            isRecording = false
            showToast("녹음이 중단되었습니다. 저장 폴더와 디스크 공간을 확인하세요.")
        }
    }

    // MARK: 타임머신

    func togglePause() {
        audio.togglePause()
        refreshTimeShift()
    }

    /// seconds < 0이면 뒤로, > 0이면 라이브 쪽으로 건너뛴다.
    func skip(_ seconds: Double) {
        audio.skip(seconds: seconds)
        refreshTimeShift()
    }

    func goLive() {
        audio.setDelay(0)
        refreshTimeShift()
    }

    func seekTimeline(delay: Double) {
        audio.setDelay(delay)
        refreshTimeShift()
    }

    private func refreshTimeShift() {
        let status = audio.timeShiftStatus()
        if status != timeline.timeShift { timeline.timeShift = status }
    }

    // MARK: 녹음

    func toggleRecording() {
        if isRecording { stopRecording() } else { startRecording() }
    }

    private func startRecording() {
        guard isOn else {
            showToast("라디오를 켠 뒤 녹음할 수 있습니다.")
            return
        }
        do {
            let url = try newRecordingURL()
            try audio.startRecording(to: url)
            timeline.recordingElapsed = 0
            isRecording = true
        } catch {
            showToast("녹음을 시작하지 못했습니다: \(error.localizedDescription)")
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        if let url = audio.stopRecording() {
            showToast("녹음을 저장했습니다: \(url.lastPathComponent)")
        }
    }

    /// 타임머신 버퍼의 최근 minutes분을 파일로 저장한다.
    func saveRecent(minutes: Int) {
        guard isOn, timeline.timeShift.isActive else {
            showToast("타임머신이 켜져 있어야 저장할 수 있습니다.")
            return
        }
        let url: URL
        do {
            url = try newRecordingURL()
        } catch {
            showToast("저장 폴더를 만들지 못했습니다: \(error.localizedDescription)")
            return
        }
        let seconds = Double(minutes * 60)
        let bridge = audio
        showToast("저장하는 중입니다…")
        Task.detached { [weak self] in
            let result = Result { try bridge.exportRecent(seconds: seconds, to: url) }
            await MainActor.run { [weak self] in
                guard let self = self else { return }
                self.finishSave(result, url: url)
            }
        }
    }

    private func finishSave(_ result: Result<Double, Error>, url: URL) {
        switch result {
        case .success(let saved):
            showToast("지난 \(Int(saved.rounded()))초를 저장했습니다: \(url.lastPathComponent)")
        case .failure(let error):
            showToast("저장하지 못했습니다: \(error.localizedDescription)")
        }
    }

    func openRecordingFolder() {
        let url = URL(fileURLWithPath: recordingFolder, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }

    private func newRecordingURL() throws -> URL {
        let folder = URL(fileURLWithPath: recordingFolder, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
        let name = "FM \(mhz(frequency))MHz \(formatter.string(from: Date())).m4a"
        return folder.appendingPathComponent(name)
    }

    // MARK: RDS

    /// 의미 있는 내용(PS/라디오 텍스트가 완성되었거나 AF 목록이 있음)이 모이면 이 주파수의 저장 정보를 갱신한다.
    private func updateRDSCache() {
        guard !rdsDemo, rds.pi != nil else { return }
        let info = displayRDS
        guard info.psComplete || info.rtComplete || !info.afs.isEmpty else { return }
        if rdsCache[frequency] != info {
            rdsCache[frequency] = info
            rdsCacheDirty = true
        }
    }

    private func loadRDSCache() {
        guard let data = UserDefaults.standard.data(forKey: Key.rdsCache),
              let decoded = try? JSONDecoder().decode([String: RDSInfo].self, from: data) else { return }
        for (key, value) in decoded {
            if let freq = Int(key) { rdsCache[freq] = value }
        }
    }

    /// 자주 쓰지 않도록 5초에 한 번까지만 디스크에 쓴다.
    private func persistRDSCacheIfNeeded(force: Bool = false) {
        guard rdsCacheDirty, force || Date().timeIntervalSince(lastRDSCacheSave) > 5 else { return }
        let encodable = Dictionary(uniqueKeysWithValues: rdsCache.map { (String($0.key), $0.value) })
        if let data = try? JSONEncoder().encode(encodable) {
            UserDefaults.standard.set(data, forKey: Key.rdsCache)
        }
        rdsCacheDirty = false
        lastRDSCacheSave = Date()
    }

    private func resetRDS() {
        rdsDecoder.reset()
        if rds != RDSInfo() { rds = RDSInfo() }
        hadRDS = false
        lastGoodRDS = nil
    }

    private func applyRDSSetting() {
        guard isOn, let chip = fm else { return }
        resetRDS()
        if rdsEnabled {
            // 켤 때 팝 소리가 나므로 잠깐 소리를 끊는다.
            rdsSwitching = true
            updateAudioState()
            try? chip.setRDS(true)
            debugAccum.chipRDSOn = try? chip.isRDSOn()
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 500_000_000)
                self?.rdsSwitching = false
                self?.updateAudioState()
            }
        } else {
            try? chip.setRDS(false)
            debugAccum.chipRDSOn = try? chip.isRDSOn()
        }
    }

    private func rdsTick() {
        guard isOn, rdsEnabled, !rdsDemo, !scan.isRunning, !afBusy, let chip = fm else { return }
        if let result = try? chip.statusWithRaw() {
            debugAccum.lastRaw = result.raw.map { String(format: "%02X", $0) }.joined(separator: " ")
            switch result.status {
            case .rds(let group):
                debugAccum.rdsEvents += 1
                debugAccum.lastError = group.error
                debugAccum.lastStrength = group.strength
                debugAccum.lastGroup = group.blocks.map { String(format: "%04X", $0) }.joined(separator: " ")
                if group.error == 0 {
                    debugAccum.goodGroups += 1
                    lastGoodRDS = Date()
                    hadRDS = true
                    if rdsDecoder.feed(group.blocks) {
                        rds = rdsDecoder.info
                        updateRDSCache()
                    }
                } else {
                    debugAccum.badGroups += 1
                }
            case .tune:
                debugAccum.tuneEvents += 1
            case .seek:
                debugAccum.seekEvents += 1
            case .other:
                debugAccum.otherEvents += 1
            }
        }
        checkAFTrigger()
    }

    /// 칩과 상관없이 해석 코드와 화면(방송국 이름, 라디오 텍스트, AF 메뉴)을 확인하는 데모.
    /// 가짜 RDS 그룹을 디코더에 넣고, 10초 뒤에 지운다.
    func startRDSDemo() {
        guard isOn else {
            showToast("라디오를 켠 뒤 데모를 볼 수 있습니다.")
            return
        }
        guard !rdsDemo else { return }
        rdsDemo = true
        resetRDS()

        func word(_ high: UInt8, _ low: UInt8) -> UInt16 {
            (UInt16(high) << 8) | UInt16(low)
        }
        let pi: UInt16 = 0x5E21
        let pty: UInt16 = 10                                    // 팝
        func blockB(type: UInt16, low: UInt16) -> UInt16 {
            (type << 12) | (1 << 10) | (pty << 5) | low         // TP = 1
        }

        let station = Array("DEMO FM ".utf8)
        let afWords: [UInt16] = [word(227, 1), word(105, 204), 0, 0]   // AF 3개: 87.6, 98.0, 107.9MHz
        var groups: [[UInt16]] = []
        for segment in 0..<4 {
            groups.append([
                pi,
                blockB(type: 0, low: 0x0008 | UInt16(segment)),        // 음악 플래그 + PS 조각 번호
                afWords[segment],
                word(station[segment * 2], station[segment * 2 + 1]),
            ])
        }
        var text = Array("RDS demo: signal test, not a real broadcast".utf8) + [0x0D]
        while text.count % 4 != 0 { text.append(0x20) }
        for address in 0..<(text.count / 4) {
            let p = address * 4
            groups.append([
                pi,
                blockB(type: 2, low: UInt16(address)),
                word(text[p], text[p + 1]),
                word(text[p + 2], text[p + 3]),
            ])
        }

        demoTask?.cancel()
        demoTask = Task { [weak self] in
            for _ in 0..<2 {
                for group in groups {
                    try? await Task.sleep(nanoseconds: 120_000_000)
                    guard !Task.isCancelled, let self else { return }
                    self.rdsDecoder.feed(group)
                    self.rds = self.rdsDecoder.info
                }
            }
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard !Task.isCancelled, let self else { return }
            self.rdsDemo = false
            self.resetRDS()
        }
    }

    // MARK: AF (대체 주파수)

    /// RDS를 받다가 4초 넘게 끊기면(신호 약화) 대체 주파수를 확인한다. 30초에 한 번까지만.
    private func checkAFTrigger() {
        guard afAutoEnabled, hadRDS, !displayRDS.afs.isEmpty, let last = lastGoodRDS else { return }
        let now = Date()
        guard now.timeIntervalSince(last) > 4, now.timeIntervalSince(lastAFCheck) > 30 else { return }
        evaluateAF(manual: false)
    }

    /// 대체 주파수를 차례로 맞춰 보고, 같은 방송(PI가 같음)이면서 수신이 가장 센 주파수로 옮긴다.
    /// 수신 세기(RSSI)의 단위는 확인되지 않아 값끼리의 상대 비교만 한다.
    func evaluateAF(manual: Bool) {
        guard isOn, !rdsDemo, !afBusy, !scan.isRunning, let chip = fm else { return }
        let known = displayRDS
        guard let pi = known.pi else {
            if manual { showToast("방송국 정보(PI)를 아직 받지 못했습니다.") }
            return
        }
        let candidates = Array(
            known.afs.filter { $0 != frequency && bandRange.contains($0) }.prefix(6)
        )
        guard !candidates.isEmpty else {
            if manual { showToast("대체 주파수 정보가 없습니다.") }
            return
        }

        lastAFCheck = Date()
        afBusy = true
        updateAudioState()
        let original = frequency

        afTask = Task { [weak self] in
            var best: (freq: Freq, rssi: Int)?
            let currentRSSI = (try? chip.rssi()) ?? 0
            for candidate in candidates {
                if Task.isCancelled { break }
                try? chip.setChannel(candidate)
                try? await Task.sleep(nanoseconds: 350_000_000)
                let rssi = (try? chip.rssi()) ?? 0
                guard let self else { break }
                if await self.confirmPI(chip, pi: pi), rssi > (best?.rssi ?? -1) {
                    best = (candidate, rssi)
                }
            }
            self?.finishAF(best: best, original: original, currentRSSI: currentRSSI, manual: manual)
        }
    }

    private func confirmPI(_ chip: BesFM, pi: UInt16) async -> Bool {
        let deadline = Date().addingTimeInterval(1.0)
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 60_000_000)
            if case .rds(let group)? = try? chip.status(), group.error == 0 {
                return group.blocks[0] == pi
            }
        }
        return false
    }

    private func finishAF(best: (freq: Freq, rssi: Int)?, original: Freq, currentRSSI: Int, manual: Bool) {
        afBusy = false
        afTask = nil
        updateAudioState()
        guard isOn, let chip = fm else { return }

        if frequency != original {
            // 확인하는 동안 사용자가 직접 다른 주파수로 옮긴 경우
            try? chip.setChannel(frequency)
            return
        }
        if let best, best.rssi > currentRSSI || currentRSSI == 0 {
            try? chip.setChannel(best.freq)
            let old = frequency
            frequency = best.freq
            resetRDS()
            showToast("AF: \(mhz(old))MHz → \(mhz(best.freq))MHz로 전환했습니다.")
        } else {
            try? chip.setChannel(original)
            if manual { showToast("더 좋은 대체 주파수가 없습니다.") }
        }
    }

    // MARK: 자동 끄기 타이머

    private func scheduleAutoOff() {
        autoOffTask?.cancel()
        autoOffTask = nil
        guard isOn, autoOffMinutes > 0 else { return }
        let seconds = UInt64(autoOffMinutes) * 60
        autoOffTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            guard !Task.isCancelled, let self else { return }
            self.showToast("자동 끄기 타이머로 라디오를 껐습니다.")
            self.teardown()
        }
    }

    // MARK: 토스트

    func showToast(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }
}
