#!/usr/bin/env python3
"""소스의 L("…") / NSLocalizedString(@"…") 키와 Resources/en.lproj/Localizable.strings를 비교한다.

문구를 추가하거나 고친 뒤에 실행하세요:  python3 tools/check_localization.py
  - 번역이 없는 키(missing), 코드에서 안 쓰는 번역(unused), 서식 기호(%@, %lld …)가 키와 다른 번역을 알려줍니다.
  - 문제가 있으면 종료 코드 1을 돌려줍니다.
키는 한국어 원문이다. 서식이 있는 문장은 정수 %lld, 문자열 %@를 쓴다.
"""
import glob, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HANGUL = re.compile(r'[\uac00-\ud7a3]')
SPEC = re.compile(r'%(?:\d+\$)?[-+ 0#]*\d*(?:\.\d+)?(?:ll|l|h)?[@dsxXfFlu]')


def unescape(s):
    return s.replace('\\"', '"').replace('\\n', '\n').replace('\\\\', '\\')


def source_keys():
    keys = []
    def add(k):
        if k not in keys:
            keys.append(k)
    swift = re.compile(r'\bL\(\s*"((?:\\.|[^"\\])*)"')
    for p in sorted(glob.glob(os.path.join(ROOT, 'Sources/FMRadio/**/*.swift'), recursive=True)):
        if p.endswith(('AppIconData.swift', 'Localization.swift')):
            continue
        text = open(p, encoding='utf-8').read()
        for m in swift.finditer(text):
            add(unescape(m.group(1)))
        if p.endswith('Hardware/RDS.swift'):          # PTY 이름은 배열에 들어 있고 조회할 때 번역한다.
            start = text.index('private static let pty = [')
            for w in re.findall(r'"([^"]*)"', text[start:text.index(']', start)]):
                if w:
                    add(w)
    objc = re.compile(r'NSLocalizedString\(@"((?:\\.|[^"\\])*)"')
    for p in glob.glob(os.path.join(ROOT, 'Sources/CBesUSB/*.m')):
        for m in objc.finditer(open(p, encoding='utf-8').read()):
            add(unescape(m.group(1)))
    return keys


def table(path):
    pairs = {}
    pat = re.compile(r'^"((?:\\.|[^"\\])*)"\s*=\s*"((?:\\.|[^"\\])*)";\s*$')
    for line in open(path, encoding='utf-8'):
        m = pat.match(line.rstrip('\n'))
        if m:
            pairs[unescape(m.group(1))] = unescape(m.group(2))
    return pairs


def unwrapped_hangul():
    """L()로 감싸지 않은 한국어 문자열 리터럴(의도한 예외 제외)을 찾는다."""
    found = []
    for p in sorted(glob.glob(os.path.join(ROOT, 'Sources/FMRadio/**/*.swift'), recursive=True)):
        if p.endswith(('AppIconData.swift', 'Localization.swift')):
            continue
        for n, line in enumerate(open(p, encoding='utf-8'), 1):
            s = line.strip()
            if s.startswith('//') or 'protectedTitles' in line or 'isViewTitle' in line:
                continue
            if p.endswith('Hardware/RDS.swift') and s.startswith('"') and s.endswith(','):
                continue
            code = re.sub(r'\s//.*$', '', line)
            for m in re.finditer(r'"((?:\\.|[^"\\])*)"', code):
                if HANGUL.search(m.group(1)) and code[max(0, m.start() - 2):m.start()] != 'L(':
                    found.append((os.path.relpath(p, ROOT), n, m.group(1)))
    return found


def main():
    keys = source_keys()
    en = table(os.path.join(ROOT, 'Resources/en.lproj/Localizable.strings'))
    missing = [k for k in keys if k not in en]
    unused = [k for k in en if k not in keys]
    mismatch = [k for k in keys if k in en and sorted(SPEC.findall(k)) != sorted(SPEC.findall(en[k]))]
    raw = unwrapped_hangul()
    print(f'키 {len(keys)}개, 영어 번역 {len(en)}개')
    for title, items in (('번역 없음(missing)', missing), ('쓰지 않는 번역(unused)', unused),
                         ('서식 기호 불일치', mismatch)):
        if items:
            print(f'\n{title}: {len(items)}')
            for k in items:
                print('  -', k.replace('\n', '\\n'))
    if raw:
        print(f'\nL()로 감싸지 않은 한국어 리터럴: {len(raw)}')
        for f, n, s in raw:
            print(f'  - {f}:{n}: {s}')
    ok = not (missing or mismatch or raw)
    print('\n결과:', '통과' if ok else '문제 있음')
    sys.exit(0 if ok else 1)


if __name__ == '__main__':
    main()
