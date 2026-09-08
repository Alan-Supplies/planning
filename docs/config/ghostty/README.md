# Ghostty 개인 설정

macOS Ghostty에서 한글 가독성을 높이고, 장시간 사용할 때 눈부심과 흐릿한 배경을
줄이기 위한 설정이다. Herdr는 Ghostty 안에서 실행되는 터미널 UI이므로 폰트와 셀
높이는 이 설정을 그대로 사용한다.

## 파일

- `config.ghostty`: 실제 Ghostty에 복사해서 사용할 설정
- macOS 적용 경로:
  `~/Library/Application Support/com.mitchellh.ghostty/config.ghostty`

## 현재 설정

```ini
font-family = D2Coding
font-size = 15
adjust-cell-height = 60%
macos-titlebar-style = native
background = 17181c
foreground = caccd4
background-opacity = 1
background-blur = 0
```

| 항목 | 값 | 목적 |
| --- | --- | --- |
| `font-family` | `D2Coding` | 한글과 영문을 고정폭으로 선명하게 표시 |
| `font-size` | `15` | 기본 13pt보다 글자를 크게 표시 |
| `adjust-cell-height` | `60%` | 기본 셀 높이에 60%를 더해 약 1.6배 줄간격 적용 |
| `macos-titlebar-style` | `native` | 제목 표시줄을 명확히 보여 창 이동 영역 확보 |
| `background` | `17181c` | 순수 검정보다 부드러운 중성 차콜 배경 |
| `foreground` | `caccd4` | 순백색보다 눈부심이 적은 밝은 회색 글자 |
| `background-opacity` | `1` | 배경을 완전히 불투명하게 표시 |
| `background-blur` | `0` | 반투명 배경의 흐릿한 느낌 제거 |

## 적용 방법

기존 설정을 백업한 뒤 저장소의 설정 파일을 Ghostty 설정 경로로 복사한다.

```sh
mkdir -p "$HOME/Library/Application Support/com.mitchellh.ghostty"
cp docs/config/ghostty/config.ghostty \
  "$HOME/Library/Application Support/com.mitchellh.ghostty/config.ghostty"
```

Ghostty에서 `Cmd+Shift+,`를 눌러 설정을 다시 읽는다. 폰트와 색상은 현재 창에도
반영되지만 `macos-titlebar-style`은 새 창부터 적용되므로 새 Ghostty 창을 연다.

## Herdr와의 관계

Herdr는 별도 GUI 터미널이 아니라 Ghostty의 터미널 셀 안에서 실행된다. 따라서
다음 항목은 Ghostty가 담당한다.

- 폰트 종류와 크기
- 글자 셀 높이와 줄간격
- 기본 배경색과 글자색
- 창 제목 표시줄과 창 이동

Herdr의 사이드바, 선택 행, 상태 강조색은 Herdr의
`~/.config/herdr/config.toml`에서 별도로 설정한다.

## 조정 기준

- 줄간격이 너무 넓어 한 화면의 행 수가 부족하면 `adjust-cell-height`를 `40%`로
  낮춘다.
- 글자가 크면 `font-size`를 `14`, 작으면 `16`으로 한 단계씩 조정한다.
- 배경은 불투명 상태를 유지한다. 흐릿함이 다시 생기면 `background-opacity = 1`과
  `background-blur = 0`이 다른 설정 파일에서 덮어써지지 않았는지 확인한다.
