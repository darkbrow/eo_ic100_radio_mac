import Foundation

/// Applies the speaker toggle to macOS's system-wide output as well as the radio's audio engine.
@MainActor
extension RadioModel {
    func setSpeakerMode(_ enabled: Bool) {
        guard speakerMode != enabled else { return }

        let devices = AudioDevices.all()
        if enabled {
            // Remember the current output before RadioModel's property observer can change it.
            if let currentID = AudioDevices.defaultOutputID() {
                SpeakerModeOutput.originalUID = devices.first(where: { $0.id == currentID })?.uid
            }
            speakerMode = true
            guard let speaker = AudioDevices.builtInSpeaker(in: devices) else {
                showToast("Mac의 내장 스피커를 찾지 못했습니다.")
                return
            }
            if !AudioDevices.setDefaultOutput(speaker.id) {
                showToast("시스템 출력 장치를 바꾸지 못했습니다.")
            }
        } else {
            speakerMode = false
            // Prefer the EO-IC100 output; if it cannot be identified, restore the output
            // that was active when speaker mode was enabled.
            let earphone = AudioDevices.guessEarphoneInput(in: devices, productName: nil)
                .flatMap { $0.outputChannels > 0 ? $0 : nil }
            let fallback = SpeakerModeOutput.originalUID.flatMap { uid in
                devices.first(where: { $0.uid == uid && $0.outputChannels > 0 })
            }
            if let target = earphone ?? fallback {
                if !AudioDevices.setDefaultOutput(target.id) {
                    showToast("시스템 출력 장치를 이어폰으로 바꾸지 못했습니다.")
                }
            } else {
                showToast("이어폰 출력 장치를 찾지 못했습니다.")
            }
            SpeakerModeOutput.originalUID = nil
        }
    }
}

private enum SpeakerModeOutput {
    static var originalUID: String?
}
