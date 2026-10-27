import Foundation
import CoreAudio
import AudioToolbox

struct AudioDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let inputChannels: Int
    let outputChannels: Int
    let isBuiltIn: Bool
    let isUSB: Bool
}

/// Core Audio 장치 목록 조회
enum AudioDevices {
    /// 이어폰 입력 장치를 자동으로 고를 때 쓰는 이름 힌트(소문자)
    private static let earphoneHints = ["ic100", "akg", "samsung", "usb-c", "usb c", "earphone"]

    static func all() -> [AudioDevice] {
        var address = makeAddress(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else {
            return []
        }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else {
            return []
        }
        // AVAudioEngine이 입력/출력 장치를 묶으려고 임시로 만드는 합성 장치는 목록에서 뺀다.
        // 엔진을 다시 만들 때마다 이름이 바뀌어 목록이 계속 달라지고 화면이 다시 그려지기 때문이다.
        return ids.compactMap(makeDevice).filter { !$0.name.hasPrefix("CADefaultDeviceAggregate") }
    }

    /// 이름/UID에 힌트(또는 USB 제품 이름)가 들어 있는 USB 입력 장치.
    /// 힌트로 못 찾아도 USB 입력 장치가 하나뿐이면 그것을 고른다. 그래도 없으면 nil → 설정에서 직접 선택.
    static func guessEarphoneInput(in devices: [AudioDevice], productName: String?) -> AudioDevice? {
        let usbInputs = devices.filter { $0.inputChannels > 0 && $0.isUSB }
        var hints = earphoneHints
        if let productName, !productName.isEmpty {
            hints.append(productName.lowercased())
        }
        let matched = usbInputs.first { device in
            let haystack = (device.name + " " + device.uid).lowercased()
            return hints.contains { haystack.contains($0) }
        }
        if let matched { return matched }
        return usbInputs.count == 1 ? usbInputs[0] : nil
    }

    /// 지금 시스템 기본 출력 장치. 맥의 볼륨 키와 HUD, 이어폰의 볼륨 버튼은 이 장치를 조절한다.
    static func defaultOutputID() -> AudioDeviceID? {
        var address = makeAddress(kAudioHardwarePropertyDefaultOutputDevice)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
        return status == noErr && id != 0 ? id : nil
    }

    /// 시스템 기본 출력 장치를 바꾼다. 성공하면 true.
    @discardableResult
    static func setDefaultOutput(_ id: AudioDeviceID) -> Bool {
        var address = makeAddress(kAudioHardwarePropertyDefaultOutputDevice)
        var device = id
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
            UInt32(MemoryLayout<AudioDeviceID>.size), &device
        )
        return status == noErr
    }

    static func builtInSpeaker(in devices: [AudioDevice]) -> AudioDevice? {
        devices.first { $0.isBuiltIn && $0.outputChannels > 0 }
    }

    // MARK: 내부

    private static func makeAddress(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func makeDevice(_ id: AudioDeviceID) -> AudioDevice? {
        guard let name = stringProperty(id, kAudioObjectPropertyName),
              let uid = stringProperty(id, kAudioDevicePropertyDeviceUID) else { return nil }
        let inputs = channelCount(id, scope: kAudioObjectPropertyScopeInput)
        let outputs = channelCount(id, scope: kAudioObjectPropertyScopeOutput)
        guard inputs > 0 || outputs > 0 else { return nil }
        let transport = uint32Property(id, kAudioDevicePropertyTransportType) ?? 0
        return AudioDevice(
            id: id,
            uid: uid,
            name: name,
            inputChannels: inputs,
            outputChannels: outputs,
            isBuiltIn: transport == UInt32(kAudioDeviceTransportTypeBuiltIn),
            isUSB: transport == UInt32(kAudioDeviceTransportTypeUSB)
        )
    }

    private static func stringProperty(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = makeAddress(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr,
              let cfString = value else { return nil }
        return cfString.takeRetainedValue() as String
    }

    private static func uint32Property(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var address = makeAddress(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private static func channelCount(_ id: AudioObjectID, scope: AudioObjectPropertyScope) -> Int {
        var address = makeAddress(kAudioDevicePropertyStreamConfiguration, scope: scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }
}
