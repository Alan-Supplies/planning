# 운동(Exercise) API 정리

> 출처: `src/services/exercise/index.ts`, `src/services/exercise/types.ts`
> 구현: RTK Query (`createApi`, `reducerPath: "exerciseApi"`)
> Base URL: `Config.API_URL` (`src/services/baseQuery.ts`)
> 캐시 태그: `ExerciseSession`, `BodyPart`, `Exercise`, `ExerciseMetadata`

---

## 1. 엔드포인트 요약

### 조회 (Query)

| # | Method | URL | 훅 | 설명 |
|---|--------|-----|-----|------|
| 1 | GET | `/user/{userId}/exercise-session/metadata` | `useGetExerciseMetadataQuery` | 유저 운동 메타데이터(목적/레벨) 조회 |
| 2 | GET | `/body-part` | `useGetBodyPartListQuery` | 운동 부위 목록 조회 |
| 3 | GET | `/exercise?gymId=` | `useGetExerciseListQuery` | 지점 운동 목록 조회 (기구 포함) |
| 4 | GET | `/machine/{uniqueCode}/exercise` | `useGetMachineExerciseListQuery` | 기구에 등록된 운동 목록 조회 |
| 5 | GET | `/user/{userId}/exercise-session/recent` | `useGetRecentUserExerciseSessionQuery` | 최근 운동 세션 조회 |
| 6 | GET | `/user/{userId}/exercise-session/body-part/recent` | `useGetRecentUserBodyPartQuery` | 부위별 최근 운동 기록 조회 |
| 7 | GET | `/user/{userId}/exercise-session/{exerciseSessionId}` | `useGetUserExerciseSessionQuery` | 특정 운동 세션 조회 |
| 8 | GET | `/user/{userId}/exercise-session/exercise-history` | `useGetUserExerciseSessionSetHistoryListQuery` | 운동별 세트 기록 이력 조회 |

> 1~8 전부 `useLazy*Query` 버전도 export되어 있음 (단, #1 `getExerciseMetadata`는 lazy 미export)

### 변경 (Mutation)

| # | Method | URL | 훅 | 설명 |
|---|--------|-----|-----|------|
| 9 | POST | `/user/{userId}/exercise-session/survey/onboarding` | `useCreateExerciseMetadataMutation` ⚠️ | 운동 메타데이터 생성 (온보딩 설문) |
| 10 | POST | `/user/{userId}/exercise-session` | `useCreateUserExerciseSessionMutation` | 운동 세션 생성 (부위 선택 시) |
| 11 | PUT | `/user/{userId}/exercise-session/{sessionId}/body-part` | `useUpdateUserExerciseSessionBodyPartMutation` | 세션 운동 부위 수정 |
| 12 | POST | `/user/{userId}/exercise-session/{sessionId}/history` | `useAddUserExerciseSessionHistoryMutation` | 세션에 운동 추가 |
| 13 | PATCH | `/user/{userId}/exercise-session/{sessionId}/history/{historyId}` | `useUpdateUserExerciseSessionHistoryMutation` | 운동 수정 (머신 연결·무게 타입·완료) |
| 14 | PUT | `/user/{userId}/exercise-session/{sessionId}/history/{historyId}/set` | `usePutUserExerciseSetHistoryMutation` | 세트 기록 저장(전체 교체) |
| 15 | PATCH | `/user/{userId}/exercise-session/{sessionId}` | `useUpdateUserExerciseSessionMutation` | 세션 수정 (운동 완료, RPE) |
| 16 | PATCH | `/user/{userId}/exercise-session/{sessionId}/history/round-number` | `useUpdateUserExerciseSessionHistoryRoundNumberMutation` | 운동 순서 변경 |
| 17 | DELETE | `/user/{userId}/exercise-session/{sessionId}/history/{historyId}` | `useDeleteUserExerciseSessionHistoryMutation` | 세션에서 운동 삭제 |
| 18 | POST | `/exercise-recommendation` | `useCreateExerciseRecommendationMutation` | 운동 추천 생성 |
| 19 | POST | `/exercise-recommendation/simple` | `useCreateSimpleExerciseRecommendationMutation` | 운동 대체용 간단 추천 |
| 20 | POST | `/exercise-recommendation/survey/satisfaction` | `useSubmitExerciseRecommendationSatisfactionSurveyMutation` | 추천 만족도 설문 저장 |

> ⚠️ #9 `createExerciseMetadata`는 엔드포인트는 정의되어 있으나 **훅이 export 목록에서 누락**되어 있음 ([index.ts:283-310](../src/services/exercise/index.ts#L283-L310))

---

## 2. 캐시 태그 매핑

| 태그 | provides (조회) | invalidates (변경) |
|------|----------------|-------------------|
| `ExerciseMetadata` (id: userId) | #1 | #9 |
| `BodyPart` | #2, #6 | — |
| `Exercise` | #3, #4 | — |
| `ExerciseSession` | #5 (전체), #7 (id: sessionId), #8 (id: userId) | #10 (전체), #11~#17 (id: sessionId) |

**주의할 점**

- #8 `getUserExerciseSessionSetHistoryList`는 `{ type: "ExerciseSession", id: userId }`로 provide하지만, 무효화하는 mutation은 전부 `id: sessionId`를 사용한다. **userId와 sessionId가 같은 네임스페이스를 공유**하므로 우연히 값이 겹치면 의도치 않은 무효화가, 겹치지 않으면 세트 기록 이력이 갱신되지 않는다.
- #6 `getRecentUserBodyPart`는 `BodyPart` 태그를 provide하지만, 부위를 바꾸는 #11 `updateUserExerciseSessionBodyPart`는 `ExerciseSession`만 무효화한다. → 부위 변경 후 최근 부위 목록이 stale해질 수 있음.
- #2, #3, #4는 무효화 주체가 없는 정적 마스터 데이터.

---

## 3. 도메인 Enum

| 타입 | 값 |
|------|-----|
| `WeightType` | `kg` \| `lb` |
| `BodyPartType` | `CHEST` \| `SHOULDER` \| `BACK` \| `ARM` \| `CORE` \| `LEG` \| `CARDIO` \| `STRETCHING` |
| `ExerciseType` | `MACHINE` \| `CABLE` \| `BARBELL` \| `DUMBBELL` \| `PROP` \| `BODY` |
| `ExerciseUnit` | `SET` \| `MINUTE` |
| `ExercisePurpose` | `WEIGHT_LOSS` \| `STRENGTH_GAIN` \| `ENDURANCE_GAIN` \| `HEALTH_MANAGEMENT` \| `POSTURE_CORRECTION` \| `ATHLETIC_PERFORMANCE` |
| `MachineType` | `PIN` \| `CABLES` \| `PLATE_LOADED` \| `CARDIO` \| `FREE_WEIGHT` |
| `MachineTypeDetail` | `CARDIO_ETC` \| `TREADMILL` \| `BIKE` \| `ELLIPTICAL` \| `ROWING` \| `STAIR` \| `OTHER` |
| `MachineStatus` | `ACTIVE` \| `INACTIVE` \| `MAINTENANCE` |

---

## 4. 엔드포인트 상세

### #1 운동 메타데이터 조회

```
GET /user/{userId}/exercise-session/metadata
```

**Params** `{ userId: number }`

**Response** `ExerciseMetadata`
```ts
{ purpose: ExercisePurpose; level: number }
```

---

### #2 운동 부위 목록 조회

```
GET /body-part
```

**Params** 없음

**Response** `BodyPart[]`
```ts
{ id: number; body_part: { kor: string; eng: string } }[]
```

---

### #3 지점 운동 목록 조회

```
GET /exercise?gymId={gymId}
```

**Params** `gymId: number` (쿼리스트링)

**Response** `Exercise[]`
```ts
{
  id: number
  name: string
  type: ExerciseType
  description: string
  image_url: string
  video_url: string
  unit: ExerciseUnit
  has_weight?: boolean
  exercise_body_part_list: BodyPartType[]
  machine_list: ExerciseMachine[]
}[]
```

`ExerciseMachine`
```ts
{
  id: number
  name: string
  brand_name: string
  type: MachineType
  type_detail: MachineTypeDetail
  line: string
  description: string
  image_url: string
  body_part: BodyPartType
  status: MachineStatus
  created_at: string
  unique_code?: string
}
```

---

### #4 기구별 운동 목록 조회

```
GET /machine/{uniqueCode}/exercise
```

**Params** `uniqueCode: string` (기구 QR/NFC 고유 코드)

**Response** `ExerciseMachine & { exercise_list: Omit<Exercise, "machine_list">[] }`
— 기구 정보 + 해당 기구로 가능한 운동 목록 (중첩 `machine_list` 제외)

---

### #5 최근 운동 세션 조회

```
GET /user/{userId}/exercise-session/recent
```

**Params** `userId: number`

**Response** `UserExerciseSession | null` — 세션 이력이 없으면 `null`

```ts
{
  id: number
  total_time: number
  started_at: string
  end_at: string
  rpe: number | null
  body_part_id_list: number[]
  history_list: UserExerciseSessionHistory[]
}
```

`UserExerciseSessionHistory`
```ts
{
  id: number
  weight_type: WeightType
  exercise: { id, name, type, description, image_url, video_url, unit }
  machine: { id, name, type, type_detail, description, image_url } | null
  set_history_list: { set_number: number; count: number; weight: number }[]
}
```

---

### #6 부위별 최근 운동 기록 조회

```
GET /user/{userId}/exercise-session/body-part/recent
```

**Params** `userId: number`

**Response** `RecentUserBodyPart[]`
```ts
{ body_part_id: number; last_exercised_at: string }[]
```

---

### #7 운동 세션 조회

```
GET /user/{userId}/exercise-session/{exerciseSessionId}
```

**Params** `{ userId: number; exerciseSessionId: number }`

**Response** `UserExerciseSession` (#5와 동일 구조, non-null)

---

### #8 운동별 세트 기록 이력 조회

```
GET /user/{userId}/exercise-session/exercise-history
    ?exercise_id=&machine_id=&limit=&offset=
```

**Params**
```ts
{
  userId: number
  query: {
    exercise_id?: number
    machine_id?: number
    limit?: number
    offset?: number
  }
}
```

- `exercise_id` 없이 호출할 수 있어야 한다. 미지정 시 사용자의 전체 운동 기록을 조회한다.
- 조회 결과는 `done_at DESC` 순서로 반환한다.

**Response** `UserExerciseSetHistoryListItem[]`
```ts
{
  id: number
  weight_type: WeightType
  exercise: { id, name, type, description, image_url, video_url, unit }
  machine: { id, name, type, type_detail, description, image_url } | null
  set_history_list: { set_number: number; count: number; weight: number }[]
  created_date: string
}[]
```

> `UserExerciseSessionSetHistory`는 `@deprecated` — `UserExerciseSetHistoryListItem` 사용

---

### #9 운동 메타데이터 생성 (온보딩 설문)

```
POST /user/{userId}/exercise-session/survey/onboarding
```

**Params** `{ userId: number; body: any }` ⚠️ **타입 미적용**

**Request** — `CreateExerciseMetadataRequest`가 정의되어 있으나 코드에서 미사용
```ts
{
  answers: {
    question_id: number
    options?: {
      option_id: number
      answer_text?: string
      weekly_schedule?: { [key: string]: string[] }
    }[]
  }[]
}
```

**Response** `{ user_survey_submit_id: number }`

---

### #10 운동 세션 생성

```
POST /user/{userId}/exercise-session
```

**Request** `CreateUserExerciseSessionRequest`
```ts
{ access_history_id: number; body_part_id_list: number[] }
```

**Response** `CreateUserExerciseSessionResponse`
```ts
{
  id: number
  user_id: number
  access_history_id: number
  started_at: string
  end_at: string | null
  pre: unknown | null
  is_deleted: number
  created_at: string
  user_exercise_session_body_part: {
    body_part_id: number
    user_exercise_session_id: number
  }[]
}
```

> `access_history_id`가 필수 — 게이트 입장 기록과 세션이 연결되는 구조

---

### #11 세션 운동 부위 수정

```
PUT /user/{userId}/exercise-session/{sessionId}/body-part
```

**Request** `{ body_part_id_list: number[] }` (전체 교체)

**Response** `void`

---

### #12 세션에 운동 추가

```
POST /user/{userId}/exercise-session/{sessionId}/history
```

**Request** `CreateUserExerciseSessionHistoryRequest`
```ts
{
  history_list: {
    exercise_id: number
    weight_type: WeightType
    round_number: number
    machine_id?: number | null
  }[]
}
```

**Response** `AddUserExerciseSessionHistoryResponse[]`
```ts
{
  id: number
  exercise_id: number
  user_exercise_session_id: number
  machine_id: number | null
  weight_type: WeightType
  is_done: number
  created_at: string
  updated_at: string | null
}[]
```

> 배열로 여러 운동을 한 번에 추가. 응답도 배열이며 생성된 `id`로 이후 세트 기록(#14)을 저장한다.

---

### #13 운동 수정

```
PATCH /user/{userId}/exercise-session/{sessionId}/history/{historyId}
```

**Request** `PatchUserExerciseSessionHistoryRequest` (전부 optional)
```ts
{
  machine_id?: number | null
  weight_type?: WeightType
  is_done?: boolean
}
```

**Response** `void`

> 머신 연결/해제, kg↔lb 전환, 운동 완료 처리에 모두 사용

---

### #14 세트 기록 저장

```
PUT /user/{userId}/exercise-session/{sessionId}/history/{historyId}/set
```

**Request** `SetHistoryItem[]` — 배열 자체가 body
```ts
{ set_number: number; count: number; weight: number | null }[]
```

**Response** `void`

> **`MINUTE` 단위 운동 처리**
> - `weight`는 `null`
> - `count`는 운동 시간(**초 단위**)

> PUT이므로 세트 전체를 교체한다. 세트 하나만 수정할 때도 전체 목록을 보내야 함.

---

### #15 세션 수정 (운동 완료)

```
PATCH /user/{userId}/exercise-session/{sessionId}
```

**Request** `PatchUserExerciseSessionRequest`
```ts
{ rpe?: number; end_at?: string }
```

**Response** `PatchUserExerciseSessionResponse`
```ts
{
  id: number
  user_id: number
  access_history_id: number
  started_at: string
  end_at: string | null
  pre: number | null
  is_deleted: number
  created_at: string
}
```

> `end_at`을 채우는 것이 운동 종료. `rpe`는 자각 운동 강도.
> ⚠️ `pre` 필드 타입이 #10 응답에서는 `unknown | null`, 여기서는 `number | null`로 불일치

---

### #16 운동 순서 변경

```
PATCH /user/{userId}/exercise-session/{sessionId}/history/round-number
```

**Request** `UpdateUserExerciseSessionHistoryRoundNumberRequest`
```ts
{ history_list: { id: number; round_number: number }[] }
```

**Response** `void`

---

### #17 세션에서 운동 삭제

```
DELETE /user/{userId}/exercise-session/{sessionId}/history/{historyId}
```

**Params** `{ userId, exerciseSessionId, historyId }`

**Response** `void`

---

### #18 운동 추천 생성

```
POST /exercise-recommendation
```

**Request** `ExerciseRecommendationRequest`
```ts
{
  gym_id: number
  selected_body_part_id_list: number[]
  available_time_minutes: number
}
```

**Response** `ExerciseRecommendationResponse`
```ts
{
  exercise_recommendation_log_id: number
  exercise_list: Exercise[]
}
```

> `exercise_recommendation_log_id`는 #20 만족도 설문 제출 시 필요하므로 보관해야 함
> ℹ️ `ExerciseRecommendationExercise` 타입이 정의되어 있으나 응답은 `Exercise[]`를 사용 — 미사용 타입

---

### #19 간단 추천 (운동 대체)

```
POST /exercise-recommendation/simple
```

**Request** `SimpleExerciseRecommendationRequest`
```ts
{
  gym_id: number
  selected_body_part_id_list: number[]
  exclude_exercise_id_list: number[]
  seed?: string
}
```

**Response** `{ exercise_list: Exercise[] }`

> 이미 추천된 운동을 `exclude_exercise_id_list`로 제외하고 대체 운동을 받는 용도.
> `seed`는 결과 재현/일관성 제어용. 로그 id를 반환하지 않아 만족도 설문 대상이 아님.

---

### #20 추천 만족도 설문 저장

```
POST /exercise-recommendation/survey/satisfaction
```

**Request** `ExerciseRecommendationSatisfactionSurveyRequest`
```ts
{
  exercise_recommendation_log_id: number
  answers: {
    question_id: number
    options?: {
      option_id: number
      answer_text?: string
      weekly_schedule?: Record<string, string[]>
    }[]
  }[]
}
```

**Response** `{ user_survey_submit_id: number }`

> `SurveyQuestionAnswer`/`SurveyOptionAnswer`는 #9의 `CreateExerciseMetadataAnswer`/`CreateExerciseMetadataOption`과 **구조가 완전히 동일** — 통합 가능

---

## 5. 대표 호출 흐름

### 운동 세션 라이프사이클

```
1. GET  /body-part                                   부위 목록 로드
2. GET  /user/{u}/exercise-session/body-part/recent  부위별 최근 기록 (UI 표시용)
3. POST /user/{u}/exercise-session                   세션 생성 (access_history_id + 부위)
   └ 응답의 id = sessionId
4. GET  /exercise?gymId={g}                          지점 운동 목록
   또는
   POST /exercise-recommendation                     추천받기
5. POST /user/{u}/exercise-session/{s}/history       운동 담기 (배열)
   └ 응답의 id = historyId
6. PUT  .../history/{h}/set                          세트 기록 저장 (반복)
7. PATCH .../history/{h}  { is_done: true }          운동별 완료 처리
8. PATCH /user/{u}/exercise-session/{s}              { end_at, rpe } 운동 종료
```

### 기구 스캔 진입

```
GET /machine/{uniqueCode}/exercise    기구 코드 → 가능한 운동 목록
POST .../history                      선택한 운동을 machine_id와 함께 추가
```

### 이전 기록 참조

```
GET /user/{u}/exercise-session/exercise-history?exercise_id=&machine_id=&limit=
```
`exercise_id`를 지정하면 같은 운동의 과거 세트/무게를 불러오고, 생략하면 전체 운동 기록을
`done_at DESC` 순서로 조회한다.

---

## 6. 정리하며 발견한 이슈

| 위치 | 내용 |
|------|------|
| [index.ts:85](../src/services/exercise/index.ts#L85) | `createExerciseMetadata`의 `body: any` — `CreateExerciseMetadataRequest`가 이미 정의되어 있는데 미적용 |
| [index.ts:283-310](../src/services/exercise/index.ts#L283-L310) | `useCreateExerciseMetadataMutation` 훅 export 누락 |
| [index.ts:195](../src/services/exercise/index.ts#L195) | #8이 `ExerciseSession` 태그에 `userId`를 id로 사용 — 다른 곳은 전부 `sessionId`. 태그 id 네임스페이스 충돌 |
| [index.ts:121](../src/services/exercise/index.ts#L121) | #11 부위 수정이 `BodyPart` 태그를 무효화하지 않아 #6 최근 부위 기록이 stale |
| [types.ts:148](../src/services/exercise/types.ts#L148) vs [types.ts:273](../src/services/exercise/types.ts#L273) | `pre` 필드 타입 불일치 (`unknown \| null` vs `number \| null`) |
| [types.ts:285-295](../src/services/exercise/types.ts#L285-L295) | `ExerciseRecommendationExercise` / `ExerciseRecommendationExerciseBodyPart` 미사용 |
| [types.ts:164-175](../src/services/exercise/types.ts#L164-L175) vs [types.ts:314-323](../src/services/exercise/types.ts#L314-L323) | 설문 답변 타입이 이름만 다르고 구조 동일 — 중복 |
| [types.ts:221-235](../src/services/exercise/types.ts#L221-L235) | `UserExerciseSessionHistoryHistoryItem` 미사용 (`UserExerciseSetHistoryListItem`만 사용) |
