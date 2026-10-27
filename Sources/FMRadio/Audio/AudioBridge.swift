import AVFoundation
import AudioToolbox
import Foundation

#if canImport(os)
import os
private final class RingLock {
    private let lock = OSAllocatedUnfairLock()
    func withLock<T>(_ body: () -> T) -> T { lock.withLockUnchecked(body) }
}
#else
private final class RingLock {
    private let lock = NSLock()
    func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
#endif

// MARK: - 재생용 링 버퍼

/// 캡처 스레드(또는 타임머신 공급자)가 쓰고 재생 스레드가 읽는 스테레오 링 버퍼.
/// 입력/출력 장치의 클럭이 달라도 지연이 쌓이지 않도록 오래된 데이터를 버린다.
final class StereoRing {
    private let capacity: Int
    private let prefill: Int
    private let maxLatency: Int
    private var left: [Float]
    private var right: [Float]
    private var readIndex = 0
    private var count = 0
    private var primed = false
    private let lock = RingLock()

    init(sampleRate: Double) {
        capacity = max(4096, Int(sampleRate * 2))
        prefill = Int(sampleRate * 0.08)
        maxLatency = Int(sampleRate * 0.4)
        left = [Float](repeating: 0, count: capacity)
        right = [Float](repeating: 0, count: capacity)
    }

    /// 아직 재생되지 않고 쌓여 있는 프레임 수
    var bufferedFrames: Int {
        lock.withLock { count }
    }

    /// 쌓인 데이터를 모두 버린다 (되감기/라이브 전환용).
    func reset() {
        lock.withLock {
            readIndex = 0
            count = 0
            primed = false
        }
    }

    /// stride: 인터리브 입력이면 채널 수, 아니면 1
    func write(left l: UnsafePointer<Float>, right r: UnsafePointer<Float>, frames: Int, stride: Int = 1) {
        lock.withLock {
            for i in 0..<frames {
                var w = readIndex + count
                if w >= capacity { w -= capacity }
                left[w] = l[i * stride]
                right[w] = r[i * stride]
                if count < capacity {
                    count += 1
                } else {
                    readIndex = (readIndex + 1) % capacity
                }
            }
            if count > maxLatency {
                let drop = count - prefill * 2
                readIndex = (readIndex + drop) % capacity
                count -= drop
            }
        }
    }

    /// 데이터가 모자라면 0으로 채우고, 다음에 prefill만큼 쌓일 때까지 기다린다.
    func read(left l: UnsafeMutablePointer<Float>?, right r: UnsafeMutablePointer<Float>?, frames: Int) {
        lock.withLock {
            if !primed && count >= prefill { primed = true }
            for i in 0..<frames {
                if primed && count > 0 {
                    l?[i] = left[readIndex]
                    r?[i] = right[readIndex]
                    readIndex += 1
                    if readIndex == capacity { readIndex = 0 }
                    count -= 1
                } else {
                    l?[i] = 0
                    r?[i] = 0
                    primed = false
                }
            }
        }
    }
}

extension StereoRing {
    func read(into list: UnsafeMutablePointer<AudioBufferList>, frames: Int) {
        let buffers = UnsafeMutableAudioBufferListPointer(list)
        let l = buffers.count > 0 ? buffers[0].mData?.assumingMemoryBound(to: Float.self) : nil
        let r = buffers.count > 1 ? buffers[1].mData?.assumingMemoryBound(to: Float.self) : l
        read(left: l, right: r, frames: frames)
    }
}

// MARK: - 타임머신 저장소 (디스크 순환 파일)

/// 최근 N분의 오디오를 16비트 스테레오 PCM으로 임시 파일에 순환 저장한다.
/// 프레임 번호는 계속 늘어나는 "절대 번호"이고, 파일 안 위치는 번호를 용량으로 나눈 나머지다.
/// 모든 메서드는 AudioBridge의 ctl 락 아래에서만 호출한다.
final class TimeShiftStore {
    let sampleRate: Double
    let capacityFrames: Int
    private let guardFrames: Int
    private let fd: Int32
    private var written = 0

    init?(sampleRate: Double, minutes: Int) {
        self.sampleRate = sampleRate
        capacityFrames = Int(sampleRate) * 60 * minutes
        guardFrames = Int(sampleRate) * 2
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("fmradio-\(UUID().uuidString).pcm")
        let descriptor = open(url.path, O_RDWR | O_CREAT | O_TRUNC, 0o600)
        guard descriptor >= 0 else { return nil }
        unlink(url.path)   // 열어 둔 채 지우면 프로세스가 끝날 때 자동으로 정리된다.
        fd = descriptor
    }

    deinit {
        close(fd)
    }

    /// NaN/무한대가 들어와도 앱이 죽지 않도록 0으로 바꾼다.
    private static func toInt16(_ value: Float) -> Int16 {
        guard value.isFinite else { return 0 }
        return Int16(max(-1, min(1, value)) * 32767)
    }

    /// 지금까지 기록한 프레임 수 (다음에 쓸 절대 번호)
    var frames: Int { written }

    /// 읽을 수 있는 가장 오래된 절대 번호 (덮어쓰는 경계에서 2초 여유)
    var oldest: Int { max(0, written - capacityFrames + guardFrames) }

    var availableFrames: Int { written - oldest }

    func reset() {
        written = 0
    }

    func write(left: UnsafePointer<Float>, right: UnsafePointer<Float>, frames: Int) {
        guard frames > 0 else { return }
        var samples = [Int16](repeating: 0, count: frames * 2)
        for i in 0..<frames {
            samples[i * 2] = Self.toInt16(left[i])
            samples[i * 2 + 1] = Self.toInt16(right[i])
        }
        var frame = written
        var done = 0
        samples.withUnsafeBytes { raw in
            while done < frames {
                let position = frame % capacityFrames
                let chunk = min(frames - done, capacityFrames - position)
                _ = pwrite(fd, raw.baseAddress! + done * 4, chunk * 4, off_t(position * 4))
                frame += chunk
                done += chunk
            }
        }
        written = frame
    }

    /// 절대 번호 [start, start+count)를 float로 읽는다. 범위를 벗어나면 false.
    func read(start: Int, count: Int,
              left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>) -> Bool {
        guard count > 0, start >= oldest, start + count <= written else { return false }
        var samples = [Int16](repeating: 0, count: count * 2)
        var frame = start
        var done = 0
        var ok = true
        samples.withUnsafeMutableBytes { raw in
            while done < count {
                let position = frame % capacityFrames
                let chunk = min(count - done, capacityFrames - position)
                let got = pread(fd, raw.baseAddress! + done * 4, chunk * 4, off_t(position * 4))
                if got != chunk * 4 {
                    ok = false
                    return
                }
                frame += chunk
                done += chunk
            }
        }
        guard ok else { return false }
        for i in 0..<count {
            left[i] = Float(samples[i * 2]) / 32768
            right[i] = Float(samples[i * 2 + 1]) / 32768
        }
        return true
    }
}

// MARK: - 녹음

/// 캡처한 오디오를 AAC(m4a) 파일로 저장한다.
final class Recorder {
    private let lock = NSLock()
    private var file: AVAudioFile?
    private var startedAt: Date?
    private var fileURL: URL?

    var isRecording: Bool {
        lock.lock()
        defer { lock.unlock() }
        return file != nil
    }

    var elapsed: TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        guard let startedAt else { return 0 }
        return Date().timeIntervalSince(startedAt)
    }

    static func settings(sampleRate: Double) -> [String: Any] {
        [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 192_000,
        ]
    }

    func start(url: URL, sampleRate: Double) throws {
        let newFile = try AVAudioFile(forWriting: url, settings: Self.settings(sampleRate: sampleRate))
        lock.lock()
        file = newFile
        fileURL = url
        startedAt = Date()
        lock.unlock()
    }

    /// buffer는 스테레오 float32 비인터리브(= 파일의 processingFormat)여야 한다.
    func write(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard let file else { return }
        do {
            try file.write(from: buffer)
        } catch {
            // 디스크 오류 등: 녹음을 멈춘다 (화면에는 녹음 중 표시가 사라진다).
            self.file = nil
        }
    }

    func stop() -> URL? {
        lock.lock()
        defer { lock.unlock() }
        let url = fileURL
        file = nil          // 해제하면 파일이 마무리된다.
        fileURL = nil
        startedAt = nil
        return url
    }
}

// MARK: - 타임머신 상태

struct TimeShiftStatus: Equatable {
    var isActive = false     // 타임머신 버퍼를 쓰는 중
    var isLive = true
    var isPaused = false
    var delay: Double = 0    // 라이브보다 몇 초 뒤를 듣고 있는지
    var buffered: Double = 0 // 되감을 수 있는 길이(초)
}

enum AudioBridgeError: LocalizedError {
    case invalidInputFormat
    case timeMachineOff
    case nothingToSave
    case bufferOverwritten
    case notRunning

    var errorDescription: String? {
        switch self {
        case .invalidInputFormat:
            return "입력 장치의 오디오 형식을 읽을 수 없습니다."
        case .timeMachineOff:
            return "타임머신이 꺼져 있습니다. 설정에서 버퍼 길이를 정하세요."
        case .nothingToSave:
            return "저장할 오디오가 아직 없습니다."
        case .bufferOverwritten:
            return "저장하는 동안 오래된 구간이 버퍼에서 지워졌습니다."
        case .notRunning:
            return "라디오가 꺼져 있습니다."
        }
    }
}

// MARK: - 오디오 브리지

/// EO-IC100 입력(녹음 모드의 라디오 오디오) → [타임머신 저장소] → 링 버퍼 → 원하는 출력 장치.
/// AVAudioEngine은 입력과 출력에 서로 다른 장치를 쓸 수 없어서 엔진 두 개를 링 버퍼로 잇는다.
///
/// 라이브일 때는 캡처 콜백이 곧바로 링 버퍼에 쓰고, 일시정지/되감기 중에는
/// 공급 타이머가 저장소의 과거 구간을 읽어서 링 버퍼에 채운다.
final class AudioBridge {
    private static let scratchFrames = 4096

    private var captureEngine: AVAudioEngine?
    private var playbackEngine: AVAudioEngine?
    private var equalizer: AVAudioUnitEQ?
    private var ring: StereoRing?
    private var sampleRate: Double = 48_000

    // 시스템 출력 장치가 바뀌면 AVAudioEngine이 설정 변경 알림을 보내고 멈출 수 있다.
    private var captureObserver: NSObjectProtocol?
    private var playbackObserver: NSObjectProtocol?
    private var lastOutput: AudioDevice?
    private var restartingPlayback = false

    // ctl 락이 지키는 상태: 저장소, 라이브/되감기 모드, 되감기 읽기 위치
    private let ctl = NSLock()
    private var store: TimeShiftStore?
    private var live = true
    private var shiftedPlaying = true
    private var cursor = 0
    private var captureSuspended = false

    private var feederTimer: DispatchSourceTimer?
    private let feederQueue = DispatchQueue(label: "fmradio.feeder", qos: .userInitiated)
    private let scratchLeft = UnsafeMutablePointer<Float>.allocate(capacity: AudioBridge.scratchFrames)
    private let scratchRight = UnsafeMutablePointer<Float>.allocate(capacity: AudioBridge.scratchFrames)

    let recorder = Recorder()

    deinit {
        scratchLeft.deallocate()
        scratchRight.deallocate()
    }

    /// 0~24dB (AVAudioUnitEQ.globalGain 한도). 뒤에 리미터가 있어 깨짐을 줄인다.
    var gainDB: Float = 0 {
        didSet { equalizer?.globalGain = min(24, max(0, gainDB)) }
    }

    var muted = false {
        didSet { playbackEngine?.mainMixerNode.outputVolume = muted ? 0 : 1 }
    }

    private(set) var isRunning = false

    // MARK: 시작/정지

    func start(input: AudioDevice, output: AudioDevice?, timeMachineMinutes: Int) throws {
        stop()

        let engine = AVAudioEngine()
        try engine.inputNode.auAudioUnit.setDeviceID(input.id)
        let format = engine.inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw AudioBridgeError.invalidInputFormat
        }
        let stereoFormat = AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: 2)!
        guard let stereo = AVAudioPCMBuffer(pcmFormat: stereoFormat, frameCapacity: 16_384) else {
            throw AudioBridgeError.invalidInputFormat
        }
        let ring = StereoRing(sampleRate: format.sampleRate)

        self.ring = ring
        sampleRate = format.sampleRate
        ctl.lock()
        store = timeMachineMinutes > 0
            ? TimeShiftStore(sampleRate: format.sampleRate, minutes: timeMachineMinutes)
            : nil
        live = true
        shiftedPlaying = true
        cursor = 0
        captureSuspended = false
        ctl.unlock()

        engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.handleCapture(buffer, ring: ring, stereo: stereo)
        }
        engine.prepare()
        try engine.start()
        captureEngine = engine
        captureObserver = observeConfigurationChange(of: engine, playback: false)

        do {
            try startPlayback(output: output)
        } catch {
            stop()
            throw error
        }
        startFeeder(ring: ring, sampleRate: format.sampleRate)
        isRunning = true
    }

    /// 재생 중에 출력 장치만 바꾼다. nil이면 시스템 기본 출력.
    func setOutput(_ output: AudioDevice?) throws {
        guard isRunning else { return }
        stopPlayback()
        try startPlayback(output: output)
    }

    func stop() {
        feederTimer?.cancel()
        feederTimer = nil
        _ = recorder.stop()
        stopPlayback()
        if let observer = captureObserver {
            NotificationCenter.default.removeObserver(observer)
            captureObserver = nil
        }
        if let engine = captureEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        captureEngine = nil
        ctl.lock()
        store = nil
        live = true
        shiftedPlaying = true
        cursor = 0
        captureSuspended = false
        ctl.unlock()
        ring = nil
        isRunning = false
    }

    // MARK: 캡처 콜백 (오디오 스레드가 아닌 탭 스레드)

    private func handleCapture(_ buffer: AVAudioPCMBuffer, ring: StereoRing, stereo: AVAudioPCMBuffer) {
        let frames = copyToStereo(buffer, into: stereo)
        guard frames > 0,
              let left = stereo.floatChannelData?[0],
              let right = stereo.floatChannelData?[1] else { return }

        ctl.lock()
        if captureSuspended {
            ctl.unlock()
            return
        }
        store?.write(left: UnsafePointer(left), right: UnsafePointer(right), frames: frames)
        if live || store == nil {
            ring.write(left: UnsafePointer(left), right: UnsafePointer(right), frames: frames)
        }
        ctl.unlock()

        recorder.write(stereo)
    }

    /// 입력(모노/스테레오, 인터리브 여부 무관)을 스테레오 비인터리브 버퍼로 옮긴다.
    private func copyToStereo(_ source: AVAudioPCMBuffer, into stereo: AVAudioPCMBuffer) -> Int {
        guard let input = source.floatChannelData,
              let outLeft = stereo.floatChannelData?[0],
              let outRight = stereo.floatChannelData?[1] else { return 0 }
        let frames = min(Int(source.frameLength), Int(stereo.frameCapacity))
        let channels = Int(source.format.channelCount)
        if source.format.isInterleaved {
            let base = input[0]
            for i in 0..<frames {
                outLeft[i] = base[i * channels]
                outRight[i] = channels > 1 ? base[i * channels + 1] : base[i * channels]
            }
        } else {
            let first = input[0]
            let second = channels > 1 ? input[1] : input[0]
            for i in 0..<frames {
                outLeft[i] = first[i]
                outRight[i] = second[i]
            }
        }
        stereo.frameLength = AVAudioFrameCount(frames)
        return frames
    }

    /// 채널 찾기/AF 확인처럼 방송이 아닌 소리가 지나가는 동안 저장·재생·녹음을 건너뛴다.
    /// 건너뛴 시간은 타임라인에서 빠진다.
    func setCaptureSuspended(_ suspended: Bool) {
        ctl.lock()
        captureSuspended = suspended
        ctl.unlock()
    }

    // MARK: 되감기 공급자

    private func startFeeder(ring: StereoRing, sampleRate: Double) {
        let timer = DispatchSource.makeTimerSource(queue: feederQueue)
        timer.schedule(deadline: .now() + .milliseconds(20), repeating: .milliseconds(20))
        timer.setEventHandler { [weak self] in
            self?.feed(ring: ring, sampleRate: sampleRate)
        }
        timer.resume()
        feederTimer = timer
    }

    private func feed(ring: StereoRing, sampleRate: Double) {
        ctl.lock()
        defer { ctl.unlock() }
        guard !live, shiftedPlaying, let store else { return }

        if cursor < store.oldest { cursor = store.oldest }
        let head = store.frames
        let target = Int(sampleRate) / 4                  // 링에 0.25초 분량을 유지한다.
        let have = ring.bufferedFrames
        guard have < target else { return }

        let count = min(target - have, head - cursor, Self.scratchFrames)
        guard count > 0 else {
            if cursor >= head { live = true }             // 라이브를 따라잡았다.
            return
        }
        if store.read(start: cursor, count: count, left: scratchLeft, right: scratchRight) {
            ring.write(left: UnsafePointer(scratchLeft), right: UnsafePointer(scratchRight), frames: count)
            cursor += count
            if cursor >= head { live = true }             // 같은 락 안이라 빈틈 없이 라이브로 이어진다.
        } else {
            ring.reset()
            live = true
        }
    }

    // MARK: 타임머신 조작 (메인 스레드)

    func timeShiftStatus() -> TimeShiftStatus {
        ctl.lock()
        defer { ctl.unlock() }
        guard let store, let ring else { return TimeShiftStatus() }
        var status = TimeShiftStatus()
        status.isActive = true
        status.isLive = live
        status.isPaused = !live && !shiftedPlaying
        status.buffered = (Double(store.availableFrames) / sampleRate).rounded(.down)   // 1초 단위
        // 라이브일 때는 링 버퍼 잔량이 흔들리므로 0으로 본다. 되감은 상태는 0.1초 단위로 맞춘다.
        status.delay = live ? 0 : (delaySecondsLocked(store: store, ring: ring) * 10).rounded() / 10
        return status
    }

    private func delaySecondsLocked(store: TimeShiftStore, ring: StereoRing) -> Double {
        let frames = live ? ring.bufferedFrames : store.frames - (cursor - ring.bufferedFrames)
        return Double(max(0, frames)) / sampleRate
    }

    /// 일시정지/재생 토글. 라이브에서 누르면 그 자리에서 멈춘다.
    func togglePause() {
        ctl.lock()
        defer { ctl.unlock() }
        guard let store, let ring else { return }
        if live {
            cursor = store.frames - ring.bufferedFrames
            ring.reset()
            live = false
            shiftedPlaying = false
        } else {
            shiftedPlaying.toggle()
        }
    }

    /// seconds > 0이면 라이브 쪽으로 앞으로, < 0이면 뒤로 건너뛴다.
    func skip(seconds: Double) {
        ctl.lock()
        var current = 0.0
        if let store, let ring {
            current = delaySecondsLocked(store: store, ring: ring)
        }
        ctl.unlock()
        setDelay(current - seconds)
    }

    /// 라이브보다 seconds초 뒤를 듣도록 위치를 옮긴다. 0 이하면 라이브.
    func setDelay(_ seconds: Double) {
        ctl.lock()
        defer { ctl.unlock() }
        guard let store, let ring else { return }
        let wanted = Int(max(0, seconds) * sampleRate)
        let frames = min(wanted, store.availableFrames)
        ring.reset()
        if frames < Int(sampleRate / 20) {
            live = true
            shiftedPlaying = true
        } else {
            cursor = store.frames - frames
            live = false
        }
    }

    /// 방송국을 바꿀 때 이전 방송의 기록을 버린다.
    func flushTimeShift() {
        ctl.lock()
        defer { ctl.unlock() }
        store?.reset()
        live = true
        shiftedPlaying = true
        cursor = 0
        ring?.reset()
    }

    // MARK: 녹음

    func startRecording(to url: URL) throws {
        guard isRunning else { throw AudioBridgeError.notRunning }
        try recorder.start(url: url, sampleRate: sampleRate)
    }

    func stopRecording() -> URL? {
        recorder.stop()
    }

    /// 타임머신 버퍼의 최근 seconds초를 AAC 파일로 저장한다. 저장한 길이(초)를 돌려준다.
    /// 오래 걸릴 수 있으므로 메인 스레드가 아닌 곳에서 호출한다.
    func exportRecent(seconds: Double, to url: URL) throws -> Double {
        ctl.lock()
        guard let store else {
            ctl.unlock()
            throw AudioBridgeError.timeMachineOff
        }
        let head = store.frames
        let available = store.availableFrames
        ctl.unlock()

        let wanted = min(Int(seconds * sampleRate), available)
        guard wanted > 0 else { throw AudioBridgeError.nothingToSave }

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096),
              let left = buffer.floatChannelData?[0],
              let right = buffer.floatChannelData?[1] else {
            throw AudioBridgeError.invalidInputFormat
        }
        let file = try AVAudioFile(forWriting: url, settings: Recorder.settings(sampleRate: sampleRate))

        let start = head - wanted
        var done = 0
        while done < wanted {
            let count = min(4096, wanted - done)
            ctl.lock()
            let ok = store.read(start: start + done, count: count, left: left, right: right)
            ctl.unlock()
            guard ok else { throw AudioBridgeError.bufferOverwritten }
            buffer.frameLength = AVAudioFrameCount(count)
            try file.write(from: buffer)
            done += count
        }
        return Double(wanted) / sampleRate
    }

    // MARK: 재생 엔진

    private func startPlayback(output: AudioDevice?) throws {
        guard let ring else { return }
        let engine = AVAudioEngine()
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!

        let source = AVAudioSourceNode(format: format) { _, _, frameCount, list -> OSStatus in
            ring.read(into: list, frames: Int(frameCount))
            return noErr
        }

        let eq = AVAudioUnitEQ(numberOfBands: 1)
        eq.bands[0].bypass = true
        eq.globalGain = min(24, max(0, gainDB))

        let limiterDescription = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_PeakLimiter,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        let limiter = AVAudioUnitEffect(audioComponentDescription: limiterDescription)

        engine.attach(source)
        engine.attach(eq)
        engine.attach(limiter)
        engine.connect(source, to: eq, format: format)
        engine.connect(eq, to: limiter, format: format)
        engine.connect(limiter, to: engine.mainMixerNode, format: format)

        if let output {
            try engine.outputNode.auAudioUnit.setDeviceID(output.id)
        }
        engine.mainMixerNode.outputVolume = muted ? 0 : 1
        engine.prepare()
        try engine.start()

        playbackEngine = engine
        equalizer = eq
        lastOutput = output
        playbackObserver = observeConfigurationChange(of: engine, playback: true)
    }

    private func stopPlayback() {
        if let observer = playbackObserver {
            NotificationCenter.default.removeObserver(observer)
            playbackObserver = nil
        }
        playbackEngine?.stop()
        playbackEngine = nil
        equalizer = nil
    }

    // MARK: 장치 설정 변경 대응

    private func observeConfigurationChange(of engine: AVAudioEngine, playback: Bool) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            self?.handleConfigurationChange(playback: playback)
        }
    }

    /// 시스템 출력 장치 변경 등으로 엔진이 멈추면, 같은 설정으로 다시 시작한다.
    private func handleConfigurationChange(playback: Bool) {
        guard isRunning, !restartingPlayback else { return }
        if playback {
            restartingPlayback = true
            defer { restartingPlayback = false }
            let device = lastOutput
            stopPlayback()
            try? startPlayback(output: device)
        } else if let engine = captureEngine, !engine.isRunning {
            try? engine.start()
        }
    }
}
