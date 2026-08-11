# 운동 세션 플로우 — API 실행 순서

> 시작점: [app/app/exercise/body-part/index.tsx](../app/app/exercise/body-part/index.tsx) 의 **확인** 버튼
> 엔드포인트 상세는 [exercise-api.md](./exercise-api.md) 참조 (`#번호`는 그 문서의 엔드포인트 번호)

---

## 0. 진입 전 — body-part 화면에 들어온 시점

이 화면은 **4곳**에서 진입하며, 넘겨받는 params가 모드를 결정한다.

| 진입 위치 | 전달 params | 모드 |
|-----------|-------------|------|
| [BarcodeAndExerciseModal](../src/components/Home/BarcodeAndExerciseModal/index.tsx#L139) (게이트 출입 직후) | `accessHistoryId` | Live (신규) |
| [ActiveExerciseWidget](../src/components/Home/Exercise/ActiveExerciseWidget.tsx#L31) | `accessHistoryId` | Live (신규) |
| [HomeLastFourWeeksCalendar](../src/components/Home/Calendar/HomeLastFourWeeksCalendar.tsx#L222) | `accessHistoryId` | Live (신규) |
| [ExerciseSummaryCard](../src/components/exercise/ExerciseSummaryCard.tsx#L87) (지난 기록 수정) | `exerciseSessionId`, `accessHistoryId`, `selectedBodyPartIds`, `isHistoricalSession="true"`, `accessDate` | Historical |
| 대시보드 상단 부위 카드 / 추천 화면 | 없음 | Live (기존 세션) |

화면 진입 시 자동 실행되는 조회:

```
GET  /user/{userId}/personal-info-agreement   ← userApi, 개인정보 추가동의 여부
GET  /body-part                                #2
GET  /user/{userId}/exercise-session/body-part/recent   #6
```

동시에 로컬 세션(`getExerciseSession()`)을 읽어 `exerciseSessionId` / `accessHistoryId` / 선택 부위를 복원한다 → **기존 세션이 있으면 생성이 아닌 수정 모드**가 된다.

---

## 1. 확인 버튼 — 분기

[body-part/index.tsx:197](../app/app/exercise/body-part/index.tsx#L197) `handleConfirm`

```
handleConfirm()
├─ user_id 없음 → return (아무것도 안 함)
│
├─ isPersonalInfoAgreement === false
│    → pendingConfirmAfterAgreement = true
│    → push /app/exercise/terms-and-conditions
│    → [동의] PATCH /user/{userId}/personal-info-agreement  ← userApi
│    → router.back() → 동의 true 감지 → handleConfirm() 재실행
│
├─ isHistoricalSession === true → handleHistoricalConfirm()
└─ 그 외                        → handleLiveConfirm()
```

> 미동의 상태에서는 **어떤 exercise API도 호출되지 않는다.** 동의 완료 후에만 세션이 생성된다.

### 공통 upsert — [body-part/index.tsx:155](../app/app/exercise/body-part/index.tsx#L155)

```
upsertExerciseSession(userId, existingId)

existingId 있음  →  PUT  /user/{u}/exercise-session/{existingId}/body-part   #11
                    body: { body_part_id_list }
                    return existingId

existingId 없음  →  POST /user/{u}/exercise-session                          #10
                    body: { access_history_id, body_part_id_list }
                    return result.data.id
```

### Live 경로 — [body-part/index.tsx:188](../app/app/exercise/body-part/index.tsx#L188)

```
1. upsertExerciseSession(userId, existingSessionId)   → #10 또는 #11
2. updateSelectedBodyParts(...)                        로컬 저장 (AsyncStorage)
3. exerciseWidget.refreshLiveActivity()                네이티브 위젯 갱신
4. router.dismiss(1) → replace /app/exercise/dashboard
```

### Historical 경로 — [body-part/index.tsx:171](../app/app/exercise/body-part/index.tsx#L171)

```
1. upsertExerciseSession(userId, paramExerciseSessionId)  → #10 또는 #11
2. dispatch(userApi.util.invalidateTags(["AccessHistory"]))   출입 기록 캐시 무효화
3. router.dismiss(1) → replace /app/exercise/summary
   params: { exerciseHistory: { id, access_date, exercise_session_id_list } }
```

> Historical에서는 로컬 세션을 건드리지 않는다 (진행 중 운동과 분리).

---

## 2. 대시보드 — 운동 담기 이후 전 과정

[dashboard/index.tsx](../app/app/exercise/dashboard/index.tsx)

### 진입 시 (`useFocusEffect`, 포커스마다 재실행)

```
loadSessionData()          로컬에서 exercises / exerciseSets / sessionId 복원 (API 없음)
loadRecommendedExercises() POST /exercise-recommendation/simple   #19
                           body: { gym_id, selected_body_part_id_list, exclude_exercise_id_list }
```

> 추천 운동 섹션은 **화면 포커스마다 매번** #19를 호출한다. 운동 추가/삭제/변경 후에도 다시 호출된다.

### 운동 체크 토글 — [dashboard/index.tsx:178](../app/app/exercise/dashboard/index.tsx#L178)

```
1. updateExerciseIsDone(exerciseId, isDone)     로컬
2. exerciseWidget.refreshLiveActivity()
3. PATCH .../history/{historyId}  { is_done }   #13
```

### 운동 삭제 (스와이프) — [dashboard/index.tsx:323](../app/app/exercise/dashboard/index.tsx#L323)

```
1. DELETE .../history/{historyId}               #17   (.unwrap() — 실패 시 알럿, 로컬 삭제 안 함)
2. removeExerciseFromSession()                  로컬
3. refreshLiveActivity()
4. loadSessionData() + loadRecommendedExercises()  → #19 재호출
```

### 운동 변경 (스와이프 → 바텀시트) — [dashboard/index.tsx:358](../app/app/exercise/dashboard/index.tsx#L358)

```
바텀시트 열기:
  POST /exercise-recommendation/simple          #19  (현재 담긴 운동 전부 exclude)

대체 운동 선택:
  1. POST .../history   { exercise_id, weight_type:"kg", round_number: 기존 roundNumber, machine_id }   #12
  2. DELETE .../history/{기존 historyId}         #17
  3. replaceExerciseInSession()                  로컬
  4. refreshLiveActivity()
  5. loadSessionData() + loadRecommendedExercises()  → #19
```

> **추가 → 삭제 순서**다. 1번 성공 후 2번이 실패하면 서버에 운동이 중복으로 남는다.

### 추천 운동 카드에서 추가 — [dashboard/index.tsx:460](../app/app/exercise/dashboard/index.tsx#L460)

```
1. getNextExerciseRoundNumber()                 로컬
2. POST .../history   history_list: [1건]       #12
3. addExercisesToSession()                      로컬 (응답 id를 exerciseHistoryId로 저장)
4. refreshLiveActivity()
5. loadSessionData() + loadRecommendedExercises()  → #19
```

### 편집 화면 (순서 변경/삭제) — [dashboard/edit.tsx:54](../app/app/exercise/dashboard/edit.tsx#L54)

`완료` 누를 때 한 번에 반영:

```
1. updateExerciseOrder(exercises)               로컬
2. 삭제된 운동들 → DELETE .../history/{id}  (Promise.all 병렬)   #17
3. 순서가 바뀐 경우에만
   → PATCH .../history/round-number
     body: { history_list: [{ id, round_number: index+1 }] }     #16
4. refreshLiveActivity() → router.back()
```

---

## 3. 운동 추가 경로 3가지

### (a) QR 스캔 — [qr-add/confirm.tsx:48](../app/app/exercise/qr-add/confirm.tsx#L48)

```
화면 진입:  GET /machine/{uniqueCode}/exercise    #4
           (운동이 1개면 자동 선택)

확인 버튼:
  1. getNextExerciseRoundNumber()                로컬
  2. POST .../history                            #12
     history_list: 선택 운동마다 { exercise_id, machine_id: 기구ID, weight_type:"kg", round_number: start+i }
  3. addExercisesToSession(...)  응답의 id/is_done/weight_type을 로컬에 반영, addedViaQR: true
  4. refreshLiveActivity() → dismissTo /app/exercise/dashboard
```

> QR 경로는 `machine_id`가 처음부터 확정된다 (기구에서 스캔했으므로).

### (b) 검색으로 추가 — [search-add/index.tsx:145](../app/app/exercise/search-add/index.tsx#L145)

```
화면 진입:  GET /exercise?gymId={mainGym.id}      #3

확인 버튼:
  1. POST .../history                            #12
     history_list: 선택 순서대로 { exercise_id, weight_type:"kg", round_number: start+i,
                                   machine_id: 기구가 1개일 때만 그 id, 아니면 null }
  2. addExercisesToSession(...)
```

### (c) 운동 추천 — [recommendation/](../app/app/exercise/recommendation/)

```
recommendation/index.tsx 진입:
  GET /user/{userId}/exercise-session/metadata   #1   (운동 목적 문구 표시용)
  ※ 설문 미완료(hasCompletedSurvey=false)면 대시보드에서 /app/exercise/survey 로 먼저 보냄

recommendation/result.tsx 진입 (시간 선택 후):
  POST /exercise-recommendation                  #18
  body: { gym_id, selected_body_part_id_list, available_time_minutes }
  → exercise_recommendation_log_id 를 state에 보관

  GET /survey?surveyKey=EXERCISE_RECOMMENDATION_SATISFACTION   ← surveyApi (피드백 문항)

[GOOD] 칩:
  POST /exercise-recommendation/survey/satisfaction            #20
  answers: [{ question_id: 메인문항, options: [{ option_id: GOOD }] }]

[BAD] 칩 → 사유 모달 → 제출:
  POST /exercise-recommendation/survey/satisfaction            #20
  answers: [메인문항 BAD, 자식문항 선택사유]

[오늘 운동으로 추가]:
  1. getNextExerciseRoundNumber()
  2. POST .../history   추천 운동 전체                          #12
  3. addExercisesToSession(...)
  4. replace /app/exercise/dashboard
```

---

## 4. 운동 상세 — 세트 기록

[detail/index.tsx](../app/app/exercise/detail/index.tsx)

### 진입 시 — [detail/index.tsx:228](../app/app/exercise/detail/index.tsx#L228)

```
loadSessionData()
├─ 로컬 세션에서 현재 운동 찾기
├─ machineId가 있으면
│    GET .../exercise-history?exercise_id=&machine_id=       #8  (lazy query)
│    → 다른 historyId의 기록만 필터해 "이전 기록" 목록 구성
└─ 세트 입력값 결정
     로컬에 저장된 세트 있음  → 그대로 복원 (API 없음)
     없고 이전 기록 있음      → applyPreviousRecord() 실행 ↓
     둘 다 없음               → 빈 세트 1개
```

**`applyPreviousRecord`** — [detail/index.tsx:174](../app/app/exercise/detail/index.tsx#L174)
가장 최근 기록을 오늘 세트로 **자동 등록**한다.

```
1. updateExerciseWeightType()                    로컬
2. PATCH .../history/{h}  { weight_type }        #13   (무게 있는 운동만)
3. saveExerciseSets()                            로컬
4. PUT  .../history/{h}/set   세트 배열          #14
```

> 화면에 들어오기만 해도 서버에 세트가 기록된다. 사용자가 아무것도 입력하지 않아도 발생.

### 기구 선택 모달 — [detail/index.tsx:323](../app/app/exercise/detail/index.tsx#L323)

기구 후보가 2개 이상이고 `machineId === null`이면 진입 시 자동으로 열린다 (프리웨이트 제외).

```
[기구 선택]
  1. updateExerciseMachineId()                   로컬
  2. PATCH .../history/{h}  { machine_id }       #13
  3. GET .../exercise-history (새 machine_id로)  #8
  4. 로컬 세트가 비어 있고 이전 기록이 있으면 → applyPreviousRecord() → #13 + #14

[모르겠어요]
  1. updateExerciseMachineId(null)               로컬
  2. PATCH .../history/{h}  { machine_id: null } #13
```

### 세트 입력 저장 — `saveCurrentSets`, [detail/index.tsx:390](../app/app/exercise/detail/index.tsx#L390)

```
1. saveExerciseSets()                            로컬 (항상)
2. PUT .../history/{h}/set                       #14  (유효 세트가 1개 이상일 때만)
```

호출 시점:
- 세트 추가 (`handleAddSet`)
- 세트 삭제 (`handleDeleteSet`)
- 입력 바텀시트 닫기 (`closeInputSheet`)
- 이전 기록 적용 (`handleApplyPreviousRecord`)
- 운동 완료 시

> #14는 PUT 전체 교체다. 세트를 하나 고쳐도 전체 배열이 매번 올라간다.

### kg ↔ lbs 전환 — [detail/index.tsx:549](../app/app/exercise/detail/index.tsx#L549)

```
1. updateExerciseWeightType()                    로컬
2. PATCH .../history/{h}  { weight_type }        #13
```

### 완료 버튼 — [detail/index.tsx:487](../app/app/exercise/detail/index.tsx#L487)

```
이미 완료된 운동이면 API 호출 없이 이동만.

미완료이면:
  1. 유효 세트 있으면 → saveCurrentSets()  → PUT .../set    #14
  2. updateExerciseIsDone(true)                  로컬
  3. PATCH .../history/{h}  { is_done: true }    #13
  4. 마지막 운동  → 운동 추가 모달
     아닌 경우    → replace /app/exercise/detail?exerciseId=다음운동
```

---

## 5. 운동 종료

### 대시보드 → 종료 — [dashboard/index.tsx:222](../app/app/exercise/dashboard/index.tsx#L222)

```
[운동 종료] 클릭
├─ 미완료 운동 있음 → IncompleteExerciseModal
│   ├─ [삭제하고 종료] → finishWorkout()  (API 없음, 로컬 세션만 종료)
│   └─ [완료하고 종료] → 미완료 운동마다 PATCH .../history/{h} { is_done: true }  #13
│                        (Promise.all 병렬) → markAllExercisesAsDone() → finishWorkout()
└─ 없음 → finishWorkout()

finishWorkout():
  exerciseWidget.endAllLiveActivities()
  endExerciseSession()                           로컬
  push /app/exercise/intensity
```

### 강도(RPE) 입력 — [intensity/index.tsx:49](../app/app/exercise/intensity/index.tsx#L49)

```
[확인]
  1. getExerciseSession() → exerciseSessionId
  2. PATCH /user/{u}/exercise-session/{s}                      #15
     body: { rpe: 선택값, end_at: new Date().toISOString() }
  3. completeExerciseSession(intensity)           로컬
  4. LiveActivity 종료 + clearLiveActivityId()
  5. 애니메이션 2.2초 → dismissAll() → replace /app/exercise/complete
```

> **여기서 `end_at`이 채워지는 것이 실질적인 운동 종료다.** 대시보드의 "운동 종료"는 로컬 상태만 정리한다.

### 완료 화면

[complete/index.tsx](../app/app/exercise/complete/index.tsx) — API 호출 없음. `/app/tabs/home` 으로 이동.

---

## 6. Historical(지난 기록) 경로

```
홈 캘린더 → 지난 출석 카드 → 부위 수정
  → body-part (isHistoricalSession=true)
  → [확인] → #10 또는 #11 + AccessHistory 캐시 무효화
  → summary

summary/index.tsx 진입:
  GET /user/{u}/exercise-session/{sessionId}     #7
  GET /body-part                                 #2   (body_part_id → 한글명 매핑)
```

---

## 7. 전체 시퀀스 (한눈에)

```
[게이트 출입]  accessHistoryId 확보
     │
     ▼
body-part ──── GET /body-part                                    #2
     │         GET .../body-part/recent                          #6
     │         GET /user/{u}/personal-info-agreement
     │
     │  (미동의) → terms-and-conditions → PATCH /personal-info-agreement → 복귀
     │
   [확인]
     ├── 신규 → POST /user/{u}/exercise-session                  #10  ⇒ sessionId
     └── 기존 → PUT  .../{s}/body-part                           #11
     │
     ▼
dashboard ──── POST /exercise-recommendation/simple              #19 (포커스마다)
     │
     ├─ QR      → GET /machine/{code}/exercise  #4 → POST .../history  #12
     ├─ 검색    → GET /exercise?gymId  #3        → POST .../history  #12
     ├─ 추천    → GET .../metadata #1 → POST /exercise-recommendation #18
     │            → POST .../history #12  (+ 만족도 #20)
     ├─ 변경    → POST .../history #12 → DELETE .../history #17
     ├─ 삭제    → DELETE .../history                              #17
     ├─ 편집    → DELETE .../history #17 + PATCH .../round-number  #16
     └─ 체크    → PATCH .../history { is_done }                    #13
     │
     ▼
detail ─────── GET .../exercise-history            #8  (이전 기록)
     │         PATCH .../history { machine_id }     #13 (기구 선택)
     │         PATCH .../history { weight_type }    #13 (kg↔lbs)
     │         PUT  .../history/{h}/set             #14 (세트 저장, 반복)
     │         PATCH .../history { is_done: true }  #13 (완료)
     │
     ▼
[운동 종료] ── PATCH .../history { is_done: true } × N            #13 (완료하고 종료 시)
     │
     ▼
intensity ──── PATCH /user/{u}/exercise-session { rpe, end_at }  #15  ★ 실제 종료
     │
     ▼
complete       (API 없음)
```

---

## 8. 구조상 알아둬야 할 점

### 로컬 우선 + 서버 이중 저장

모든 화면이 **AsyncStorage 세션(`src/utils/exerciseSession.ts`)을 단일 진실 소스로 렌더링**하고, 서버 호출은 그 뒤에 따라붙는 형태다.

- 화면에 보이는 운동 목록·세트는 전부 로컬에서 온다. `getUserExerciseSession` (#7)은 **Historical summary에서만** 쓰인다.
- 로컬 `exerciseHistoryId`(= #12 응답의 id)가 서버와 로컬을 잇는 유일한 키다. 이게 `undefined`면 이후 #13/#14/#17이 **전부 조용히 스킵**된다.
- 대부분의 mutation이 `.unwrap()` 없이 호출되어 **실패해도 로컬은 정상 진행**한다. 서버와 로컬이 어긋나도 사용자에게 표시되지 않는다.
  - 예외: 운동 삭제(#17)와 운동 변경(#12+#17)은 `.unwrap()` + 알럿 처리.

### 게스트/비로그인 분기

모든 서버 호출이 `if (user?.user_id && exerciseSessionId && exerciseHistoryId)` 가드 안에 있다. 하나라도 없으면 로컬만 기록되고 세션은 서버에 남지 않는다.

### 세션 생성 시점

세션은 **부위 선택 확인 시점(#10)** 에 만들어진다. 운동을 하나도 담지 않고 나가도 서버에는 빈 세션이 남는다.

### round_number 관리

`getNextExerciseRoundNumber()`가 로컬 기준으로 다음 번호를 계산한다. 서버는 이 값을 그대로 받는다. 편집 화면(#16)에서만 index 기반으로 재계산된다 → **로컬 순서가 서버 순서의 기준**이다.

---

## 9. 플로우에서 발견한 이슈

| 위치 | 내용 |
|------|------|
| [dashboard/index.tsx:396-415](../app/app/exercise/dashboard/index.tsx#L396-L415) | 운동 변경이 **추가(#12) → 삭제(#17)** 순서. 추가 성공 후 삭제 실패 시 서버에 중복 운동이 남는다 |
| [detail/index.tsx:200-207](../app/app/exercise/detail/index.tsx#L200-L207) | 상세 화면 진입만 해도 이전 기록이 자동으로 #14(PUT set)로 서버 저장된다. 사용자가 입력하지 않은 기록이 남음 |
| [dashboard/index.tsx:157](../app/app/exercise/dashboard/index.tsx#L157), [:160](../app/app/exercise/dashboard/index.tsx#L160) | `console.log(">>> requestBody:")`, `console.log(">>> result:")` 디버그 로그가 남아 있음 |
| [dashboard/index.tsx:140](../app/app/exercise/dashboard/index.tsx#L140) | 추천(#19)이 `useFocusEffect`마다 호출 + 운동 추가/삭제/변경마다 추가 호출. 한 번의 운동 추가에 #19가 2회 나갈 수 있음 |
| [dashboard/index.tsx:249](../app/app/exercise/dashboard/index.tsx#L249) | `exercise.exerciseHistoryId!` non-null 단언. `undefined`인 운동이 섞이면 `.../history/undefined` 로 요청이 나간다 |
| [body-part/index.tsx:220-225](../app/app/exercise/body-part/index.tsx#L220-L225) | `useEffect` 의존성에 `pendingConfirmAfterAgreement.current` (ref) 사용 — ref 변경은 리렌더를 유발하지 않으므로 의도대로 동작하지 않을 수 있음 |
| [body-part/index.tsx:166](../app/app/exercise/body-part/index.tsx#L166) | `access_history_id: Number(accessHistoryId)` — `accessHistoryId`가 `undefined`면 `NaN`이 전송된다 |
| [recommendation/result.tsx:71](../app/app/exercise/recommendation/result.tsx#L71) | `gym_id: mainGym?.id` — `mainGym`이 없으면 `undefined`로 요청 |
| [detail/index.tsx:216-219](../app/app/exercise/detail/index.tsx#L216-L219) | #8 호출 시 `order`/`limit` 미지정. 전체 이력을 받아 클라이언트에서 자르고 있음 (`RECORDS_PER_PAGE`) |
| [qr-add/confirm.tsx:95](../app/app/exercise/qr-add/confirm.tsx#L95) | #12 응답 배열을 **인덱스 순서로** 요청 운동과 매칭. 서버가 순서를 보장하지 않으면 잘못 매핑된다 (search-add도 동일 패턴) |
