import Foundation

/// 현재 언어에 맞는 문자열을 돌려준다.
/// 키는 한국어 원문이고, 영어 번역은 Resources/en.lproj/Localizable.strings에 있다.
/// 한국어 번역 파일은 따로 없다: 키가 곧 한국어 문구라서 번역이 없으면 키가 그대로 쓰인다.
func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

/// 서식(%@, %lld 등)이 들어 있는 문자열. 정수는 %lld, 문자열은 %@를 쓴다.
func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: NSLocalizedString(key, comment: ""), arguments: args)
}
