# CLAUDE.md

이 파일은 Claude Code(claude.ai/code)가 이 저장소에서 작업할 때 참고하는 안내 문서입니다.

## 이 저장소의 정체

이 저장소는 **애플리케이션 코드베이스가 아닙니다**. Alan이 **Preppers**(레스토랑 주문 플랫폼: KDS/POS/KIOSK/ORDER/AUTH 서버) 업무를 위해 운영하는 개인/팀 플래닝 및 지식베이스 저장소입니다. 일일 업무 로그, 회의록, 아키텍처 참고자료, Jira/스프린트 기획, Claude Code로 저장한 플랜, Claude Code Skill 하나를 담고 있습니다. 실제 제품 소스코드는 이 저장소에 포함되지 않은 별도 저장소(예: `preppers-server`)에 있으며 — 여기 적힌 브랜치/커밋 컨벤션 등은 *그* 저장소들에서 작업할 때 지킬 규칙이지, 이 저장소 자체의 규칙이 아닙니다.

이 저장소 자체에는 빌드/린트/테스트 파이프라인이 없습니다.

## 디렉토리 구조

- `daily/` — 일일 업무 로그, 하루 한 파일, 파일명 `YYMMDD.md` (예: `260408.md`).
- `docs/` — 주제별로 묶인 참고 문서: `plans/`(과제별 스펙·TODO), `preppers/`(제품 문서, `ARCHITECTURE.md` 참고),
  `order/`, `pos/`, `db/`, `deployment/`, `monitoring/`, `grafana/`, `network/`, `보안/`, `restful/`,
  `메뉴/`, `회의/` 등.
  - `docs/ai/` — 도구/주제별로 나뉜 Claude Code 운영 컨벤션. 일부 파일은 `@other.md` import로 체이닝됨
    (예: `data.md` → `db.md`, `deploy.md` → `github.md` + `jira.md`) — 이 저장소가 이미 쓰던 AI 컨텍스트
    구성 패턴이며, 아래에서도 동일하게 재사용합니다.
  - `docs/plans/*.plan.md` — Claude Code의 plan 모드에서 저장된 플랜(파일명 뒤에 해시 접미사 붙음).
    현재 진행 중인 스펙이 아니라 "그때 제안/완료된 내용"의 기록으로 취급합니다.
- `project/<name>/` — 범위가 좁은 스파이크/조사 작업. 보통 가설·성공 기준·범위 밖 항목을 적은
  `GOAL.md`를 둡니다 (`project/test-fly/GOAL.md` 참고).
- `skill/fit-parser/` — Garmin `.fit` 활동 파일을 파싱하는 Claude Code **Skill** (`SKILL.md`).
- `러닝/` — 개인 러닝 데이터: 원본 `.fit` 파일과 위 skill이 생성한 `_records.csv` / `_summary.json` 결과물,
  파일명은 `YYYYMMDD설명.fit` 형식.
- `api/` — VS Code REST Client 확장용 `.http` 요청 모음 (예: `opensearch/base.http`).
- `kds-dev.session.sql`, `.vscode/settings.json` — 읽기 전용 `kds-dev` MySQL DB에 대한 임시 쿼리와
  SQLTools 연결 프로필. 접속 정보는 `docs/ai/db.md`에 문서화되어 있으니 다른 곳에 중복 기재하지 마세요.
- `sprint/`, `presentation/`, `매장/`, `희의/` — 스프린트 노트, 발표 준비, 매장별 노트, 회의록.

## 자주 쓰는 명령

- Garmin `.fit` 파일 파싱: `python3 skill/fit-parser/scripts/parse_fit.py <fit-file>` — 입력 파일 옆에
  `<name>_records.csv`, `<name>_summary.json`을 생성합니다.
- `kds-dev`에 대한 임시 쿼리 실행: `.vscode/settings.json`의 `kds-dev` 연결(SQLTools, 읽기 전용)을
  사용하거나 `kds-dev.session.sql`의 쿼리를 실행합니다.
- OpenSearch/API 엔드포인트 테스트: `api/opensearch/base.http`를 REST Client 확장으로 엽니다.

## 컨벤션

`.cursorrules`에서:
- 답변 앞머리에 질문의 시점/주제에서 뽑은 `[주제어] {YYYY-MM-DD HH:MM}`를 붙인다.
- 답변에 필요한 정보가 부족하면 추측하지 말고 먼저 질문한다.
- 코드블럭에는 항상 언어를 태그한다(순수 텍스트는 `text`).
- 새 참고자료는 `docs/<주제>/`에, 새 일일 기록은 `daily/YYMMDD.md`에 작성한다.

Claude Code가 연동된 제품 저장소에서 작업할 때 쓰는 도구별 컨벤션(자동 로드되도록 import — 자세한 내용은
각 파일 참고):

- @docs/ai/github.md
- @docs/ai/jira.md
- @docs/ai/notion.md
- @docs/ai/slack.md
- @docs/ai/test.md
- @docs/ai/sales.md
- @docs/ai/db.md

## 제품 아키텍처 (플래닝 문서를 위한 배경 지식)

이 저장소가 기획 대상으로 삼는 Preppers 시스템은 5개 서비스로 구성됩니다 (전체 다이어그램은
`docs/preppers/ARCHITECTURE.md` 참고):
- `KDS`(주방 디스플레이, 포지션별 주문 화면)는 `KDS_SERVER`와 통신합니다.
- `POS`(배달 플랫폼/카운터 주문)와 `KIOSK`(무인 주문)는 각각 자신의 서버와 통신하며, 이 서버들은
  표준화된 주문을 `ORDER_SERVER`로 전달합니다.
- `AUTH_SERVER`는 세 클라이언트 모두에 JWT를 발급합니다.
- `ORDER_SERVER`와 `KDS_SERVER`는 공유 MySQL 원장(ledger)을 함께 읽고 씁니다.
