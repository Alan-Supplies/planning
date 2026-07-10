---
name: gsheet-reader
description: Use when reading a Google Sheet (by URL or spreadsheet id) into CSV/JSON — read-only, service-account auth. Triggers on "구글 시트 읽어줘", "이 시트 내용 확인", docs.google.com/spreadsheets URLs.
---

# Google Sheet Reader (read-only)

Google 시트를 읽어 CSV/JSON으로 추출하는 스킬. **읽기 전용**, 서비스 계정(JWT) 인증.

## 준비 (최초 1회)

1. GCP에서 **서비스 계정** 생성 → 키(JSON) 발급.
2. 키 JSON을 **이 저장소 밖**에 저장하고 권한 잠금:
   ```bash
   mkdir -p ~/.config/preppers
   mv ~/Downloads/xxxx-sa.json ~/.config/preppers/gsheets-sa.json
   chmod 600 ~/.config/preppers/gsheets-sa.json
   export GOOGLE_APPLICATION_CREDENTIALS=~/.config/preppers/gsheets-sa.json
   ```
   > ⚠️ 키를 저장소에 커밋하지 말 것. `private_key`는 파일 경로로만 넘긴다(문자열 env로 넘기면 `\n` 처리 필요).
3. 읽을 시트를 서비스 계정 이메일(`client_email`, `...@....iam.gserviceaccount.com`)에 **뷰어로 공유**.
4. 의존성 설치(최초 1회): `npm install --prefix skill/gsheet-reader/scripts`

## 실행

```bash
# URL 통째로(gid 포함) 넘기면 해당 시트만 읽음
node skill/gsheet-reader/scripts/read_sheet.js "<google-sheet-url>"

# spreadsheetId + 범위 지정
node skill/gsheet-reader/scripts/read_sheet.js <spreadsheetId> "'시트명'!A1:H50"

# 특정 gid만
node skill/gsheet-reader/scripts/read_sheet.js <spreadsheetId> --gid 1568776384

# 출력 위치 지정 / 파일 미생성(미리보기만)
node skill/gsheet-reader/scripts/read_sheet.js <url> --out docs/메뉴 --no-file
```

옵션: `--gid <n>` · `--out <dir>`(기본 cwd) · `--key <sa.json>`(env 대신 경로 직접) · `--no-file`(미리보기만).

## 산출물

- `<제목>__<시트명>.csv` — 시트별 원시 값
- `<제목>.json` — 전체(시트명→행 배열) 구조

범위/gid를 안 주면 **모든 시트**를 읽는다.
