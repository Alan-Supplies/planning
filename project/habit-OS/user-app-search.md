토큰 효율 순서 (싼 것 → 비싼 것)
1. 파일 트리부터 좁히기 (거의 무료)


fd -e ts -e tsx . src/api src/services   # 파일명만
파일명 규칙(workout, exercise, record, history)만으로 대상이 5개 이내로 줄면 여기서 끝.

2. rg로 "정의 지점"만 뽑기 — 파일 내용 통째로 읽지 않기


rg -l 'workout|exercise|record'          # 파일 목록만 (-l)
rg -n 'export (const|function|async)' src/api/workout.ts   # 시그니처만
rg -n --no-heading -m3 'useQuery|axios\.' -g '*workout*'   # 매치당 상한
핵심은 -l(목록만), -n -m(개수 제한), -A2(맥락 최소). -C5 남발이 토큰을 제일 많이 먹는다.

3. 진입점 하나만 정독 → 그 다음은 심볼 추적
API 레이어 index나 타입 정의 파일 하나만 Read하고, 거기서 나온 심볼 이름으로 다시 rg. 전체 파일 Read는 마지막 수단.

4. 컨텍스트에 안 남기고 싶으면 서브에이전트
"운동 기록 관련 API 엔드포인트 목록과 파일 경로만 반환" 같은 좁은 지시로 Explore 에이전트에 위임. 탐색 과정의 파일 덤프는 서브에이전트 컨텍스트에서 소각되고, 결론만 메인에 올라온다. 다만 서브에이전트 자체 비용이 있으므로 파일이 수십 개 이상 흩어져 있을 때만 이득.

안티패턴
Read 먼저 → 파일 하나가 500줄이면 그것만으로 수천 토큰
여러 후보를 "일단 다 읽고 판단" → 병렬 Read 3~4개가 grep 20번보다 비쌈
git log/git diff 전체 출력 → --stat, --oneline -10으로 제한
같은 파일 재확인용 재-Read (편집 후 검증 Read 불필요)
이 레포에 맞는 실전 조합
모노레포라 apps/gymboxx-user-app 스코프를 명시하는 게 제일 크다. rg --glob 'apps/gymboxx-user-app/**'로 시작하고, API 클라이언트 컨벤션(예: src/api/*.ts + react-query 훅) 한 곳만 확인한 뒤 그 패턴 이름으로 grep 확장하는 순서. 스키마/타입 파일이 따로 있으면 거기가 가장 정보 밀도가 높다 — 엔드포인트 이름이 한 파일에 모여 있는 경우가 많아서 Read 1회로 전체 지도가 나온다.

rg: brew install ripgrep
