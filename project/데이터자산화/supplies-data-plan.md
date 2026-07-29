# 데이터 자산화 기획안

> DB · 이벤트 · DW · CDP 4계층 · 실행 계획
>
> 서플라이스 · Gymboxx  
> Product | 작성 vonn  
> 2026-07-27

**측정 못 하면 개선도 없다.**

<!-- 원문 PDF 2쪽 -->

한 줄 요약: 데이터 자산화 = DB(정본) + 이벤트 로그·택소노미(행동) + DW(분석) + CDP(활성화)의 4계층 전부. 목표는 단 하나의 기준 — 모 든 데이터가 고객 ID( user_id ) 기준으로 분석·해석 가능한 구조. 이 문서는 현행 실측 진단(§4)과 계층별 To-Be 설계(§5~8), 이를 지키게 하 는 운영 원칙·거버넌스(§9~10), 실행 순서(§11~§16)를 하나로 묶은 데이터 자산화의 상위 정본이다.

한 사실 = 한 자리. 같은 내용을 여러 절에 반복 서술하지 않는다. 각 주제의 정본 위치는 — 결함 49건 명세 §13 · 우선순위 정의와

```text
G1 ~ G4   판정 §11-3 · 티켓 소유권 §11-5 · WP 상세 §12 · QA 자동화 §10-4 · 스크린 레지스트리 §6-7. 다른 절에서는 이들을 참
```

조만 한다.

## 1. 배경·목적

### 1-1. 왜 지금 하는가

- 측정 못 하면 개선도 없다. Habit OS 기획의 지표 체계 중 행동 계열(스트릭·목표·미션·행동 이벤트)은 현행 스키마에 원천 데이터가 없거나 신뢰할 수 없다. 기능을 배포해도 성과를 판정할 수단이 없으면 다음 의사결정의 근거가 생기지 않는다.

- 회사 전략과 직결. PT Data Assetization 은 2026년 3대 사업축 중 하나다 (출처: 2026-roadmap).

- "기능 먼저, 계측 나중"이 지금의 공백을 만들었다. 기능은 배포됐지만 "어떤 목적으로, 어떤 데이터를, 어떻게 수집·분석할지"의 준 비가 부재했다. 그 결과가 §4의 진단 — 도메인 혼합 저장, 타입 결함, ID 결측, 계측 공백이다.

### 1-2. 이 문서가 세우는 단 하나의 기준

모든 데이터는 고객 ID( user_id ) 기준으로 분석·해석 가능해야 한다.

fact_visit 출입 1건 — 언제 왔나

```text
 dim_user                                      fact_workout
 고객 1명 = 1행                                    운동 세션 1건 — 무엇을 했나
```

◀ user_key ▶ 누구인가 fact_order 인구통계 · 가입월차 결제 1건 — 무엇을 샀나 멤버십 상태 · 세그먼트

fact_engagement 이벤트 1건 — 어떻게 반응했나

이 그림 한 장이 데이터 자산화의 목적이다. 한 명의 고객( dim_user )을 중심에 두고 "누가 · 언제 왔고 · 무엇을 했고 · 무엇을 샀고 · 어떻 게 반응했는지"를 하나로 연결해 보는 것. 지금은 이 다섯 조각이 서로 다른 테이블에 흩어져 있고 일부는 user_id 조차 없어서 한 사람의 이야기로 이어 붙일 수가 없다.

이 기준은 심미적 원칙이 아니라 L3(DW)·L4(CDP)의 물리적 전제다. user_id 로 조인되지 않는 레코드는 dim/fact 모델에 들어갈 수 없 고, 세그먼트의 원료가 되지 못한다. 즉 user_id 없는 레코드는 자산이 아니라 부채다.

### 1-3. 범위

```text
구분        이 문서가 다루는 것                                            다루지 않는 것


계층        L1 DB · L2 이벤트 · L3 DW · L4 CDP 전 계층의 설계와 착수 순서        각 테이블의 상세 DDL·인덱스 문장(→ 각 Wave 개발계획)

시점        1단계(현재 착수)에서 확정된 것 + 2~4단계로 이연한 것의 진입 조건               2단계 이후 기능 기획 자체
```

<!-- 원문 PDF 3쪽 -->

```text
구분   이 문서가 다루는 것               다루지 않는 것


판단   데이터 구조·지표 정의에 영향을 주는 결정   화면 UX·비주얼 디자인(→ 각 디자인계획)
```

<!-- 원문 PDF 4쪽 -->

## 2. 4계층 정의와 현재 상태

### 2-1. 4계층이란 무엇인가

```text
 계층                                역할                           담는 것


 L1. DB (정본)                       사실의 원천                       결제·멤버십·출석·운동 기록·목표 등 트랜잭션 상태

 L2. 이벤트 로그·택소노미 (행동)              사용자가 무엇을 했는가                 화면 진입·탭·완료·공유 등 행동 스트림

 L3. DW (분석)                       질문에 답하는 층                    dim/fact 정제 모델, 지표 레이어

 L4. CDP (활성화)                     데이터로 행동을 만드는 층               고객 프로필 통합, 세그먼트, 캠페인 타겟팅
```

두 가지 규율이 계층을 갈라놓는다.

1. 행동은 L2, 상태는 L1 — 이벤트로 매출을 세지 않고, DB로 여정을 추적하지 않는다.

2. L3·L4는 L1·L2가 고객 ID로 조인 가능할 때만 성립한다 — §1-2의 기준이 전 계층의 전제인 이유.

### 2-2. To-Be 아키텍처

```text
 [앱/서버]             [L2 이벤트]            [L3 DW]          [L4 CDP/소비]
  유저 행동 ──logEvent()──▶ Firebase/Braze ──┐      스테이징(원본 보존)       세그먼트·오디언스
```

트랜잭션 ──[L1 DB 정본]── CDC/배치 ───────┼──▶ 정제(dim/fact) ──▶ 지표 레이어 ──▶ 푸시 타겟팅(push_schedule)

```text
                                    │     마트(도메인별)           BI 대시보드
  Clarity(정성 리플레이) ─── 보조 ──────────┘                                 분석(코호트·퍼널)
```

### 2-3. 현재 상태 (2026-07-26 기준)

L1. DB — 가동 중이나 구조 결함 다수, 1단계로 대규모 정비 착수

1단계 6기능 상세기획이 신규 테이블 21종 · 기존 테이블 변경 3종을 확정했다(§5-1). 신규분은 예외 없이 §9 운영 원칙을 준수하도록 설계됐고, 신규 21종 전부가 user_id 를 보유하거나 마스터 테이블이며 SQL 집계 대상 JSON 컬럼은 0건이다. 반면 기존 테이블의 결함 은 §4-5에 전수 등재되어 있고 상당수가 이번 단계 범위 밖으로 남는다.

L2. 이벤트 — 발송 경로는 이미 있었고, 택소노미가 없었다

계측 자체가 "사실상 부재"였던 것은 SDK가 없어서가 아니다. CLIENT/src/utils/log.ts:7-10 의 logEvent() 단일 함수가 Firebase Analytics와 Braze에 동시 발송하고 있었고, 없었던 것은 설계된 이벤트 체계였다. 1단계에서 97종 택소노미를 확정(§6)했으므로 이 제 발화 경로와 정의가 모두 존재한다. 주의 다만 수집 후 분석 저장소가 없다 — 이벤트는 Firebase/Braze 안에 갇히고, DB와 조인할 수 없다. 이것이 L3의 존재 이유다.

L3. DW — 부재. 단 진입 조건이 갖춰지는 중

여전히 원천 직접 쿼리에 의존한다. 1단계 범위 밖이지만, 원천이 정리되면서 진입 조건이 갖춰졌다. 착수 시점과 조건은 §7.

L4. CDP — 부분 착수

푸시(Wave 5)의 push_schedule + PushGateway 가 세그먼트 → 채널 발송 → 결과 회수 루프의 1차 구현이다. 다만 세그먼트 정의가 DW가 아니라 배치 쿼리 안에 있다는 한계가 있다(§8).

정리: 이번 단계의 실질적 진전은 L1과 L2다. L3·L4는 도구 선정(§18-2)이 선행되어야 하므로 2단계 이후 과제로 남는다.

<!-- 원문 PDF 5쪽 -->

## 3. 설계 원칙 5

1. 질문이 먼저다 — 질문 → 지표 → 이벤트/테이블 순으로 역산 설계한다. 테이블을 먼저 만들고 쓸 데를 찾지 않는다.

2. 행동과 상태를 분리한다 — L2/L1 역할 분리. 이벤트로 매출을 세지 않고, DB로 여정을 추적하지 않는다.

3. 계측 없는 배포는 없다 — 신규 화면·기능의 이벤트 정의를 DoD에 포함한다. 1단계 6기능이 전부 계측 절을 갖고 있는 것이 이 원칙

의 1호 적용 사례다.

4. 모든 데이터는 고객 ID 기준으로 해석 가능해야 한다 — 신규 테이블·이벤트에 user_id (또는 명시적 비회원 표기) 필수. 신규 21종 전

부 user_id 보유 또는 마스터 테이블( goal_outcome · goal_action · goal_audience_rule · machine_substitute 4종만 마스터).

5. 타입·저장 방식 무결성 — 도메인 혼합 저장, JSON 텍스트, 문자열 리스트 컬럼, enum 오염, 시간대 모호를 신규 설계에서 금지하고

기존 것은 계획적으로 해소한다. 신규 21종에 SQL 집계 대상 JSON 컬럼 0건( push_schedule.params 만 예외이며 스키마 주석에 "집 계 대상 아님"을 명시).

<!-- 원문 PDF 6쪽 -->

## 4. As-Is 진단 — 전부 실측 기반

진단은 두 층으로 되어 있다. §4-1의 7유형은 결함이 왜 생기는지의 분류 체계이고 그대로 To-Be 설계 요구사항이 된다(§17-1 매핑). §4-5의 결함 대장은 1단계 상세기획이 코드·DB로 직접 확인한 실행 가능한 개별 항목이다. 분류가 없으면 재발을 막지 못하고, 대장이 없으면 실행이 안 된다.

### 4-1. DB 문제 유형 분류 (7유형)

산발적으로 축적된 함정(지표_테이블맵)을 유형화한 것.

```text
#    유형            실측 사례                                                                                 영향


①    도메인 혼         payment_history 1개 테이블에 멤버십 구독·G오더·PT·일일권·챌린지 결제 35종 혼재. 스키마 실측                       도메인별 매출·상품 분석마다
     합 저장          (2026-07-19): 상품별 컬럼쌍( membership_ / sportswear_ / locker_ / pt_ × name·amount) + 도   type 매핑 수작업, 신규 type
                   메인별 주문 FK 8종이 한 행에 공존하는 와이드-스파스 구조, locker_order_id_list 는 varchar 콤마                 추가 시 리포트 누락
```

리스트

```text
②    SQL 집계        JSON 텍스트 4종( food_statistics.statistics 등), user_inbody.inbody_data JSON              지표 계산 불가 또는 앱 레벨
     불가 타입                                                                                               파싱 필요

③    enum 오        COMPLETE / COMPLETED , REFUND / REFUNDED , "SMALL_COMPANY " (뒤 공백) 병존.                필터 집계 누락 — 조용한 오
     염             notification.type 은 enum 선언에도 채팅방 이름 약 150종이 저장(§4-5 P-3)                             답

④    시간 무결         UTC 저장 KST 하루 밀림, user_inbody.record_time 문자열·date와 9시간 차, zero-date 862건. 코          일자·주간 지표 왜곡
     성             드 레벨 TZ 결함 3건 실증(§4-5 T-1·T-2·T-3)

⑤    단위 혼재         weight decimal(10,7) + weight_type kg/lb 운동 단위 부착, count 가 exercise.unit 에 따라 횟       볼륨 집계 시 환산 누락·오합
                   수/초                                                                                   산(§4-5 E-4·E-9가 실제 사
```

례)

```text
⑥    적재 정지·        user_inbody 2024-11-22 정지, user_statistics (1회 배치 후 정지), 빈 테이블 9종                     최신 지표 사용 불가·탐색 비
     유령 테이                                                                                               용
```

블

```text
⑦    키 연결성         device_id 형식 3종 불일치, sales.type ↔ payment_history.type 체계 불일치,                        테이블 간 조인 실패·오조인
     결함            survey_question.survey_id 명명 함정, 추천↔실제 수행 연결 키 부재(§4-5 S-8)
```

### 4-2. 고객 ID 연결성 감사 (2026-07-19 실측, 최근 30일)

§1-2 기준의 현주소.

user_id

```text
테이블                  전체                        결측률                     원인 분해
```

NULL

```text
 payment_history     239,300   22,307          9.3%                    ONE_DAY_BUY 14,752 + FOOD_BUY 7,529 (+환불 26) — 비회원 일일
(결제)                                                                   권·비로그인 G오더

 food_order (G오      150,479   7,529           5.0%                     payment_history FOOD_BUY 결측과 정확히 일치 — 동일 원인
```

더)

```text
 access_history      738,020   10,400          1.4%                    미확인 (게스트 출입·단말 오류 추정, 분해 필요)
```

(출석)

<!-- 원문 PDF 7쪽 -->

user_id

```text
테이블                     전체                       결측률                 원인 분해
```

NULL

```text
user (인구통계)             392,670   —              gender 0.76% · 생년   양호 — "고객은 누구인가"는 즉시 답변 가능
```

0.83%

- 판정: G오더의 "누가·언제·무엇을·몇 개"에서 품목( food_id )·수량( count )·지점( gym_id )·시점은 100% 저장 중( food_order 실측 —

```text
     gym_id   결측 0). 구멍은 "누가"의 5%다.
```

- 비회원 주문을 없앨 수 없다면 비회원 식별 정책(게스트 ID 발급 또는 명시적 GUEST 마킹)이 필요하다. NULL은 "비회원"과 "유 실"을 구분하지 못한다.

- 운동기록 3층 구조는 user_id 연결이 완비되어 있다. 문제는 연결이 아니라 작성률이다(§4-5 S-1).

### 4-3. 행동 계측 공백

- 화면·버튼 이벤트 택소노미의 설계·수집이 사실상 전무했다. 온보딩 퍼널은 gbx_step1~3_click 3개가 전부이고 welcome-new-member 이 후는 0건이다(§4-5 I-1).

- 목표 등록 퍼널은 전량 웹뷰라 앱 계측과 단절되어 있다 — "왜 등록을 완료하지 않는가"를 답할 수 없다(§4-5 I-2).

- login_history 는 재인증 이벤트만 기록한다(실사용의 15% 수준) — 앱 사용 리텐션의 분모로 부적합하다.

- Habit OS 신규 기능 중 목표·미션은 원천 테이블조차 없었다. 단 스트릭은 원천이 이미 있었다 — getUserWeeklyConsecutiveAttendence 가 YEARWEEK(..., 1) KST 변환까지 포함해 계산하고 있다. 새로 만들 것이 아니라 버그 1건을 고칠 대상이다(§4-5 T-3).

### 4-4. Clarity 실사 (2026-07-19 라이브 조회)

```text
항목            실측                                                                                   판정


규모            최근 7일 세션 약 23.2만(모바일 99.6%), 고유 사용자 4.3만, 평균 세션 234.6초, 페이지/세션 3.4                   수집 자체는 대규모 가동
```

중

```text
화면 식          방문 URL 전량 빈값(22.9만 세션 전부) — 앱 내 웹뷰/SDK 환경이라 URL 없음, 화면 이름 태깅 미적용                     화면 단위 분석 불가
```

별

```text
이벤트           스마트 이벤트 5종뿐, 전부 자동 감지·소량 (ShowMore 1,413 / ApplyCoupon 348 / Other 259 / Login 9 /   설계된 택소노미 없음
```

Download 2)

```text
고객 ID         custom user id/tag 조회 불가 — DB user_id 와의 연결 미구성                                      고객 ID 기준 해석 불가

UX 신호         dead click 17% (rage 0.36%, quick back 0.01%)                                        정성 리플레이 가치는 있
```

음

- 결론: Clarity는 정성 도구(리플레이·히트맵)로 유지하되, 제품 분석·CDP를 대체할 수 없다. 화면 이름 태깅 + custom id(내부 us er_id 의 해시) 주입은 저비용 개선으로 병행한다(§8-4).

- 주의 신규 리스크: 요약 이미지의 셀피가 Clarity 세션 리코딩에 실릴 수 있다 → 해당 화면 마스킹 강제(§10-3).

### 4-5. 결함 대장 — 코드·DB로 직접 확인한 49건

1단계 상세기획이 코드 직접 확인(app-server / supplies-apps / gymboxx-lib / batch / messaging-lambda / HQ / branch-admin / web)과 2026-07-26 레플리카 실측으로 특정한 개별 결함이다. 심각도: 높음 = 지표·대외 노출·법적 리스크 / 중간 = 기능 오작동·데이터 오염 / 낮음 = 위생

★ 개별 49건의 전체 명세는 §13 결함 49건 실행 대장이 정본이다. 결함별 영향·재현 방법·수정 검증 기준·담당·WP가 거기 한 표에 모여 있다. 이 절은 진단 관점의 분포와 각 군의 성격만 다룬다 — 같은 결함을 문서 안에서 두 번 서술하지 않기 위함이다.

<!-- 원문 PDF 8쪽 -->

```text
                   건    높    중
 군                                낮음     이 군을 대표하는 실측                                                       P0
                   수    음    간


 E 운동 기록           14   6    4    4      started_at 이 출석 시각이라 운동 시간 평균 111분. detail 진입만으로 하지 않은 운동          7
```

이 기록된다

```text
 S 데이터 희소·         8    1    6    1      기록 보유 세션 8.4% — 90일 세션 180,649건 중 운동을 담은 것은 15,189건                0
```

구조

```text
 M 기구·카탈로          6    0    4    2      기구 대체 커버리지 0%. FREE_WEIGHT 148모델 중 108개가 운동 미매핑                    0
```

그

```text
 T 시간대·배치          5    3    1    (규범    챌린지 주 경계가 KST 09:00 — 매주 9시간 어긋난다                                  3
```

1)

```text
 P 푸시·알림           8    4    4    0      동의를 보는 곳이 179곳 중 2곳(1.1%). 7일 심야 발송 2,536건                         2

 I 계측·인프라          5    1    2    2      목표 등록 퍼널이 전량 웹뷰 — 앱 계측과 완전히 단절                                     0

 Q 성능              3    0    2    1      access_history 15.1M에 (user_id, created_at) 복합 인덱스 부재              0

 합계                49   15   23   10     —                                                                  12건 / 12
```

행

이 진단이 말하는 것 세 가지

1. 지금도 오염이 진행 중이다. E-3·E-4·E-9·T-1·T-3·T-4는 고치기 전까지 매일 잘못된 행을 새로 쌓는다. 나중에 고쳐도 그 구간 데이

터는 되살릴 수 없다 — P0가 존재하는 이유다(§11-3 G1 ).

2. 법적 노출이 둘 있다. 동의 없는 발송(P-1)과 심야 발송(P-7). 즉시 차단과 법무 판단이 함께 필요하다(§11-3 G2 ).

3. 분석의 토대 자체가 비어 있다. 기록 보유 세션 8.4%(S-1)에 행동 계측 공백(§4-3)이 겹쳐, 현재는 "무엇이 문제인가" 를 데이터로

답할 수 없다. 이 문서 전체가 그 상태를 벗어나기 위한 계획이다.

### 4-6. 1단계에서 손대지 않는 As-Is

아래는 진단은 끝났으나 이번 단계 범위 밖이다. 전부 §18-2 잔존 미결로 관리한다.

```text
payment_history   와이드-스파스 35종 혼재 · locker_order_id_list varchar 콤마 리스트 · 비회원 user_id NULL(결제 9.3%·G오더 5.0%·
```

출석 1.4%) · enum 오염( COMPLETE / COMPLETED 등) · zero-date 862건 · device_id 형식 3종 · sales.type ↔ payment_history.type 불일치

- 유령 테이블 9종 · user_inbody 재가동.

<!-- 원문 PDF 9쪽 -->

## 5. To-Be L1 — DB 스키마

### 5-1. 스키마 통합 카탈로그 — 신규 21종 · 변경 3종

lib 릴리

```text
#    테이블                  종류     소유 문서(정본)                 핵심 제약
```

스

```text
1    user_exercise_se     변경     공통 §2·§4-3       4.29.0   access_history_id nullable · source · template_id · program_
     ssion                                                 slot_id · idx_user_source_started


2    user_exercise_se     변경     운동기록 §2-2        4.29.0   status · deleted_at 추가 · round_number nullable · uq_session_
     ssion_history                                         round


3    user_exercise_te     신규     공통 §3-1          4.29.0   origin 3종 · soft delete · last_used_at
```

mplate

```text
4    user_exercise_te     신규     공통 §3-2 + 운동세트   4.29.0   UNIQUE(template_id, order_no) · idx_exercise(exercise_id,st
     mplate_item                 §2-4                      atus)


5    user_exercise_te     신규     공통 §3-3          4.29.0   복합 PK · weight 항상 kg
```

mplate_set

```text
6    user_exercise_pr     신규     공통 §4-1          4.29.0   4주×주2회 · survey_submit_id · status 4종
```

ogram

```text
7    user_exercise_pr     신규     공통 §4-2          4.29.0   UNIQUE(program_id, week_no, session_no) · planned_on (1단계
     ogram_slot                                            NULL)

8    machine_substitute   신규(마   공통 §5 + 운동세트     4.29.0   복합 PK · source RULE/RULE_CARDIO/TRAINER · batch_run_
                          스터)    §2-2·§2-3                 id · updated_at


9    goal_outcome         신규(마   운동목표 §2-2-1      4.29.0   uq_code · is_outcome_metric
```

스터)

```text
10   goal_action          신규(마   운동목표 §2-2-2      4.29.0   metric_type 4종 = 달성률 산식 규격 · evidence_key
```

스터)

```text
11   goal_audience_rule   신규(마   운동목표 §2-2-3      4.29.0   성별·연령 노출 — 종류 분기와 순서 분기를 동시 지원
```

스터)

```text
12   user_goal            신규     운동목표 §2-3-1      4.29.0   active_flag 생성 컬럼 + uq_user_active = 1인 1 ACTIVE 강제 · p
```

rev_goal_id 이력 체인

```text
13   user_goal_action     신규     운동목표 §2-3-2      4.29.0   마스터 스냅샷 4컬럼(§9 G1) · uq_goal_order

14   user_exercise_pr     신규     운동목표 §2-4        4.29.0   active_flag UNIQUE · user_exercise_metadata 와 듀얼 라이트
```

ofile

```text
15   user_exercise_pr     신규     운동목표 §2-4        4.29.0   복합 PK
```

ofile_injury

```text
16   user_body_metric     신규     운동목표 §2-5        4.29.0   시계열 · weight_kg 항상 kg · PII · uq_user_date_source

17   user_goal_weekly_    신규     운동목표 §2-6        4.29.0   gym_value / outside_value 분리 · capped_value · raw_rate_pct
     progress                                              · is_final

18   user_workout_plan_   신규     캘린더 §2-2         4.29.0   plan_on = date 타입 · state ≠ status 분리 · active_flag
     date                                                  UNIQUE · fulfilled_* 근거
```

<!-- 원문 PDF 10쪽 -->

lib 릴리

```text
 #      테이블                    종류        소유 문서(정본)                          핵심 제약
```

스

```text
 19     user_workout_day_      신규        캘린더 §2-3                4.29.0     uq_user_dow_active · user_workout_alarm 병행 동기화
```

pattern

```text
 20     push_schedule          신규        푸시 §2-2                 4.30.0     uq_dedup · send_at (UTC)+ local_send_on/minute (KST) · trig
```

ger_type varchar · bigint PK

```text
 21     push_delivery_log      신규        푸시 §2-3                 4.30.0     지표 정본 · 판정 스냅샷 6컬럼 · idx_cap(user_id, local_on,
```

outcome)

```text
 22     user_push_prefer       신규        푸시 §2-4                 4.30.0     PK= user_id · 행 없으면 기본값(백필 0건)
```

ence

```text
 23     notification           변경        푸시 §2-5                 4.30.0     read_at · trigger_type 추가 (12.8M, nullable만 · INSTANT 목표)


 24     user_tutorial_pr       신규        튜토리얼 §2-2               4.31.0     uq_user_step · step_version 재노출 판정 · local_on KST
```

ogress

요약: 신규 테이블 21종(마스터 4 + 사용자 데이터 17) · 기존 테이블 변경 3종 · 신규 인덱스 다수. 신규 21종 중 JSON 집계 대상 컬럼 0 건, soft delete( status ) 미보유 3종( user_exercise_template_set · user_exercise_profile_injury · user_exercise_program_slot — 전부 부 모에 종속된 값 오브젝트).

스키마 정본은 Wave 1 공통 데이터모델과 각 기능 개발계획이다.

### 5-2. gymboxx-lib 릴리스 열차 — 배포 순서의 정본

소비 repo의 현재 버전 (2026-07-26 package.json 실측)

```text
 repo                                                                                  현재 lib


  gymboxx-app-server                                                                   4.28.7

  gymboxx-user-app-batch                                                               4.28.5

  gymboxx-headquarter-server                                                           4.28.5

  gymboxx-branch-admin-server                                                          4.28.5

  gymboxx-pass-server                                                                  3.6.1 (major 스큐)

  messaging-lambda                                                                      미정 미확인
```

3열차 구성

```text
 열차            담는 것                                                          합류 기능                   승격 필요 repo


 4.29.0        UserExerciseSessionEntity 컬럼 3종 + UserExerciseSessionHisto    운동기록 · 운동세트 ·           app-server(필수) · batch(필수,
               ryEntity 컬럼 2종 + 신규 엔티티 17종(템플릿3·프로그램2·대체1·목표                 운동목표 · 캘린더 (4기          4.28.5→4.29.0) · HQ/branch-admin
               9·캘린더2) + enum 다수                                             능 공동)                    미정


 4.30.0        푸시 신규 엔티티 3종 + NotificationEntity 컬럼 2개 + enum 확장             푸시알림                    app-server · batch · messaging-
```

lambda ★

```text
 4.31.0        UserTutorialProgressEntity 1종 + enum 3종                       코치마크·튜토리얼               app-server
```

<!-- 원문 PDF 11쪽 -->

규칙 (확정)

1. 4.29.0은 반드시 한 릴리스로 병합한다. user_exercise_session 에 붙는 template_id · program_slot_id 는 운동기록 DDL-A와 운동세트

요구가 같은 ALTER 문장이다. 두 번 실행하면 배포가 깨진다. ALTER 1회 · npm 배포 1회.

2. 합류 순서: 운동기록(세션 컬럼) → 운동세트(신규 6종) → 운동목표(신규 9종) → 캘린더가 마지막(신규 2종뿐이라 충돌 표면 0).

3. 푸시는 4.29.0 열차에 타지 않는다. 4.29.0 배포 후 D+7 안정화 확인 뒤 4.30.0을 낸다. 푸시는 앞 Wave 스키마를 읽기만 하므로 마

지막 합류가 안전하다.

4. 요약 이미지는 lib 승격이 불필요하다 — 신규 테이블 0·신규 컬럼 0·엔티티 변경 0. 자매 기능과 독립 배포 가능(배포 리스크가 가장

낮은 기능).

5. gymboxx-pass-server (3.6.1)는 전 열차에서 승격 불필요. access_history 자체를 바꾸지 않고, notification 추가 컬럼은 nullable이

라 구버전 INSERT가 통과한다. 단 출석 테이블 자체를 바꾸는 후속 과제가 생기면 major 스큐 때문에 반드시 재검토.

6. messaging-lambda 는 server보다 먼저 올린다. 새 필드( consent_checked )를 모르는 람다에 새 메시지가 들어가면 게이트가 무력화된

채 발송된다. 반대 순서는 하위호환이라 무해.

배포 순서 (열차별)

4.29.0 : lib → DB DDL(정합화→추가→완화→UNIQUE) → server → batch → client(플래그 OFF) → 플래그 단계 개방 4.30.0 : lib → DB DDL → messaging-lambda <span class='star'>★</span> → server → batch(PUSH_DRY_RUN=true 1주) → client → 실발송 4.31.0 : lib → DB DDL → server → client

### 5-3. 소유·충돌 조정 — 같은 자원을 두 문서가 원했던 것

1단계 6기능이 서로 충돌한 지점과 그 확정 결과. 이 표가 없으면 착수 시 중복 작업·이중 진실이 발생한다.

```text
#     충돌                                                                      확정


①     user_exercise_session 의 template_id · program_slot_id — 운동              운동기록 DDL-A가 한 번에 처리. 운동세트는 값만 채운다
```

기록과 운동세트가 각각 ALTER 계획

```text
②     GET .../exercise-session/recent — 운동기록은 "진행 중 1건 복                       /recent = 진행 중 1건(운동기록 소관). 운동세트는 목록 API + only_co
      원", 운동세트는 "지난 세션 불러오기"로 원함                                              mpleted 필터 + POST .../import 로 우회


③     요일·시간 정보 — 운동목표 user_goal 에 넣을지, 캘린더에 넣을지                               캘린더 user_workout_day_pattern 소관. 운동목표 §2-7이 명시적으로
```

이관

```text
④     주 경계 헬퍼 — 목표·캘린더·스트릭·챌린지가 각자 계산                                          kstDayRange() · kstWeekRange() · kstToday() 단일 헬퍼로 통일.
```

server·batch 양쪽에 동일 구현 (§9 C1)

```text
⑤     user_workout_alarm — 캘린더는 동기화 대상, 푸시는 원천 후보                             캘린더가 병행 동기화(쓰기), 푸시는 읽지 않는다. 푸시의 원천은 user_wo
```

rkout_day_pattern (정본)

```text
⑥     pt.dao.ts 타임존 버그 — 캘린더 CAL-PRE-3 이 수정 예정                                푸시 PUSH-BT-6 (경로 폐기)로 대체. 데이터 계약은 유지되므로 캘린더 동
```

기화는 깨지지 않는다

```text
⑦     access_history (user_id, created_at) 복합 인덱스 — 캘린더 D-4                   한쪽에서만 결정. 캘린더 D+14 실측으로 통합
```

와 요약이미지 D-13이 동일 사안

```text
⑧     2-pass 순서 재부여 알고리즘 — 운동기록 history와 운동세트                                 공용 유틸로 뺄지 각자 둘지 미정 (운동세트 SET-D-8)
```

template item이 동일

```text
⑨     메가폰 배지 — 푸시(동의 토글 부작용)와 요약이미지(배지 쇼케이스 화                                 푸시가 중복 방지·1회 정리 담당, 요약이미지가 화이트리스트 교차 확인( P
      이트리스트)                                                                  USH-QA-5 )


⑩     flow_id 앱↔웹 조인 키 — 운동목표가 먼저 정의                                          튜토리얼이 온보딩 전체로 확대 적용. 같은 키를 재사용
```

<!-- 원문 PDF 12쪽 -->

### 5-4. 검토했으나 만들지 않는 것 (의도적 제외)

```text
항목                                              왜 안 만드나


 streak 캐시 테이블                                  원천이 이미 있다( consecutive_attendance_week , YEARWEEK(...,1) KST). 버그 1건(T-3)만
```

고치면 된다

```text
 share_log                                      요약 이미지는 DB row를 만들지 않는다. 공유 성사는 측정 불가(§9 M2) — 이벤트로만

 xp_ledger · user_level · quest · user_quest    2단계 레벨링 소관

 user_exercise_set_history.created_at           세트를 값 오브젝트로 취급하고 전량 교체 유지. 2단계 재검토 미정

 user_exercise_program_slot.completed_at        이행 판정은 user_exercise_session.program_slot_id 역조인. 컬럼을 두면 이중 진실

 attendance_challenge 컬럼 추가( planned_dates      JSON은 SQL 집계 불가. FK 한 방향 참조로 스키마 무변경 달성 → 기존 코드 전부 무영향 +
JSON / 비트마스크)                                   pass-server 승격 불필요

 user_goal_daily_progress                       목표선이 전부 주 단위(WHO·ACSM). 일 단위 집계는 근거가 없다

 user_body_metric 의 체지방률·골격근량                   인바디 재가동 전에는 수집 경로가 없다 → 영영 NULL. source='INBODY' 어댑터 자리만 남긴
```

다

```text
 notification 인덱스 추가                            12.8M에 인덱스를 붙이면 온라인 DDL이 실제 데이터 복사가 된다. 쿼리 교정 우선

 user_badge.created_at 인덱스                      실측 판정 불필요 — user_id 카디널리티 244,490 = 유저당 평균 4.16행
```

### 5-5. L1의 남은 큰 과제 — 결제 도메인 분리

§4-1 ①의 해소책이며 1단계 범위 밖이다. 착수 시 아래 3옵션에서 선택한다(권고 (c), 서버 개발 리뷰 필요 — §18-2).

```text
옵션              내용                                                             장점                     단점


(a) 물리 분리       도메인별 결제 테이블 신설 + 데이터 마이그레이션                                    구조 최종 해결               결제 코드 전면 수정·마이
```

그레이션 리스크 大, 5.65M행 이관

```text
(b) 원천 유지       type→도메인 매핑 딕셔너리(테이블) + 표준 뷰                                   무중단·즉시 가능              와이드-스파스 구조
+ 리포트 층                                                                                               ·varchar 리스트 등 원천
```

결함은 잔존

```text
(c) 표준 원장       공통 스키마의 order_ledger (주문 원장:                                   신규부터 깨끗한 정본 확          이중 기록 기간의 정합성
신설 + 원천         user_id ·domain·item·qty·amount· gym_id · paid_at )를 신설해 신규    보 + 무중단, DW fact_      QA 필요
유지 (권고)         결제부터 이중 기록, 과거분은 매핑 뷰로 백필                                      order 의 직접 원천
```

- 어느 옵션이든 매핑 딕셔너리는 즉시 착수 가능하다 (type 35종 → MEMBERSHIP/GORDER/PT/ONE_DAY/CHALLENGE/기타). 코드 하드코딩 금지 — 신규 type 추가 시 리포트에서 조용히 누락되는 것을 막는다.

- G오더 품목·수량은 food_order ( food_id · count · gym_id · user_id )가 이미 보유하므로, 리포트는 매핑 뷰만으로도 즉시 성립한다. 원 장(c)은 도메인 확장 대비다.

- 함께 결정할 것: 비회원 식별 정책(§4-2) — 결제·주문의 user_id NULL을 GUEST 명시 체계(게스트 ID 또는 buyer_type 컬럼)로 전 환.

<!-- 원문 PDF 13쪽 -->

## 6. To-Be L2 — 이벤트 택소노미 (97종)

### 6-1. 발화 경로 — 신규 인프라를 만들지 않는다

// CLIENT/src/utils/log.ts:7-10 (전체) export const logEvent = async (eventName: string, params?: Record<string, any>) => {

```text
   Braze.logCustomEvent(eventName, params)                 // :8
   await logEventFirebase(analytics, eventName, params)    // :9
```

}

한 번 호출하면 Firebase Analytics + Braze 양쪽에 간다. 서버 사이드 이벤트는 배치 로그·CloudWatch·슬랙으로, 웹뷰는 웹에서 직 접 Firebase로 보낸다(postMessage 브리지 위임 금지 — 유실 위험).

### 6-2. 명명 규칙

```text
 #      규칙


 1       기능네임스페이스_대상_행동 snake_case. 현행 표준( menu_click · payment_info_submit )과 정합. 레거시 camelCase( onGorderTabPressed )는 따
```

르지 않는다

```text
 2      기능별 네임스페이스 접두를 강제한다(§6-3) — 이것이 이벤트명 충돌 차단의 정본

 3      이벤트명은 언더바 포함 최대 40자(초과 시 SDK 잘림)

 4      클라 이벤트는 사용자 액션 시점 기준. 서버 처리 완료는 *_complete (응답 수신)로 분리 — 액션과 결과를 섞지 않는다

 5       *_error 표준을 전 기능에 둔다 — 무음 실패 가시화. 필요 시 *_stay (N초 체류)도 표준 추가


 6      enum 값은 사전 등록제. 기존 워딩 재사용, 택소노미 문서 등재 후 코드 리뷰 대조

 7      프로퍼티 타입 규칙: Integer/Float에 string 혼용 금지, Boolean은 소문자 true / false , List는 항목 타입 일관, String은 enum화

 8      프로퍼티는 id 필수, name 선택(클라이언트가 name을 보유할 때만 로깅)
```

프로퍼티 타입 예시

```text
 타입                         예시                                                              주의


 Integer                     weight_kg=60 , count=12                                        string 혼용 금지

 Float                       equipment_match_rate=0.83                                      string 혼용 금지

 String                      goal_type='WEIGHT_LOSS'                                        enum화 — 사전 등록제

 Boolean                     is_prefilled=true                                              반드시 소문자

 List                        body_parts=['CHEST','ARM']                                     항목 타입 일관성
```

### 6-3. 네임스페이스 7종

```text
 접두                                소유               개수         주의 주의


 workout_record_                   운동 기록            12         활동 탭에 이미 exercise_make_click · exercise_list_click 이 있는데 이는 '같이 운동하기'
```

모임 이벤트다. 운동 기록과 무관 — 재사용 금지

```text
 template_ / program_ / m          운동 세트            8/7/       기록 행위( workout_record_ )와 계획 행위를 의도적으로 분리
 achine_swap_                                       3
```

<!-- 원문 PDF 14쪽 -->

```text
 접두                             소유            개수          주의 주의


 goal_ / goal_wv_               운동 목표         12 / 8      _wv_ 는 웹뷰 전용. flow_id 로 앱과 조인


 calendar_                      캘린더           10

 summary_image_                 요약 이미지        9

 push_                          푸시 알림         8           후속 행동 이벤트는 신규로 만들지 않고 자매 이벤트를 entry_point='push' 로 재사용

 tutorial_ / onboarding_        코치마크·튜        11 / 7
```

토리얼

### 6-4. 이벤트 전량

A. 운동 기록 — workout_record_* (12)

```text
 이벤트                                 트리거                          주요 속성


 workout_record_entry_click          진입 카드 탭                       entry_point (activity_tab|home_widget|home_calendar), session_state


 workout_record_session_start        POST /exercise-session        source , body_part_count , entry_point — 외부 기록 채택률
```

201

```text
 workout_record_session_resume       /recent 복원 성공                 source , elapsed_minutes


 workout_record_exercise_add         POST /history                 method (search|qr|recommend_card|recommend_result), count


 workout_record_exercise_repl        PUT .../replace               from_exercise_id , to_exercise_id
```

ace

```text
 workout_record_exercise_del         DELETE .../history/:id        is_done
```

ete

```text
 workout_record_set_save             PUT .../set                   set_count , weight_type , unit , is_prefilled — E-3 수정 후 "실제 입력" 비율


 workout_record_prev_record_a        이전 기록 수동 적용                   record_age_days
```

pply

```text
 workout_record_session_end          PATCH {rpe,end_at}            duration_minutes , exercise_count , done_count , rpe , total_sets — 핵심 완
```

주 지표

```text
 workout_record_session_aban         서버 마감 배치                      duration_hours , done_count
```

don

```text
 workout_record_history_list_        외부 기록 목록 진입                   source_filter , item_count
```

view

```text
 workout_record_error                세션·세트 API 실패                  api , http_status , error_code
```

B. 내 운동 세트·추천 플랜·기구 대체 — template_* · program_* · machine_swap_* (18)

```text
 이벤트                                                       주요 속성


 template_list_view                                         template_count , has_program


 template_create                                            origin , item_count , has_target_sets


 template_edit                                              edit_type (name|item_add|item_delete|order|set), is_copy_on_write


 template_delete                                            origin , age_days , use_count
```

<!-- 원문 PDF 15쪽 -->

```text
 이벤트                                                   주요 속성


  template_load                                         template_id , mode , with_sets , days_since_last_use


  session_import                                        item_count , mode , source_age_days


  template_save_from_session                            item_count , only_done


  template_stale_shown                                  reason (exercise_inactive|machine_unavailable)


  program_survey_start                                  entry_point


  program_start                                         sessions_per_week , minutes , focus , purpose , level , fallback_level


  program_generate_fallback                             fallback_level , gym_id , parts — 지점별 기구 보강 판단 자료


  program_slot_start / program_slot_complete            week_no , session_no , done_count , duration_minutes


  program_complete                                      elapsed_days — 완주율·구독 연장 가설의 핵심


  program_abandon                                       done_slots , elapsed_days


  machine_swap_click                                    machine_id , exercise_id , context , gym_id


  machine_swap_empty                                    machine_id , reason , gym_id — 대체 매핑 품질의 직접 지표


  machine_swap_apply                                    from_machine_id , to_machine_id , similarity , source , rank
```

C. 운동 목표 — goal_* 12 + goal_wv_* 8 + 서버 2

```text
 이벤트                                                                                          주요 속성


  goal_banner_impression / goal_register_click                                                variant / entry_point


  goal_widget_click / goal_detail_view / goal_history_view                                    overall_rate_pct , days_left , week_count , a
```

vg_rate_pct

```text
  goal_edit_click / goal_delete                                                               duration_weeks , avg_rate_pct — 이탈 목표 분
```

석

```text
  goal_first_progress_of_week                                                                 week_start_on , metric_type


  goal_week_achieved                                                                          week_start_on , streak_weeks — 핵심 성공 지표


  goal_body_metric_save / goal_body_metric_skip                                               has_height , has_weight / step — 이탈 지점


  goal_error                                                                                  api , http_status , error_code


 웹뷰 goal_wv_start · _step_view · _step_answer · _step_back · _skip · _submit · _s             전부 flow_id + user_id 필수
```

ubmit_result · _abandon

```text
 서버 goal_progress_finalized / goal_recalc_failed                                              주간 확정 배치 / 실시간 재계산 실패(알림 대상)
```

D. 캘린더 — calendar_* (10)

calendar_view ( planned_count · done_count · missed_count · entry_point ) · calendar_month_change · calendar_day_tap ( status ) · calendar_ plan_add ( date_count · origin · has_template · days_ahead — 핵심 전환) · calendar_plan_remove · calendar_template_assign · calendar_p

```text
attern_save ( day_count · has_time   — 자동 배치 채택률) · calendar_missed_view · calendar_commitment_cta · calendar_error
```

E. 요약 이미지 — summary_image_* (9)

<!-- 원문 PDF 16쪽 -->

summary_image_open ( entry_point · days_ago · has_records · badge_count ) · _variant_view (1초 이상 노출) · _variant_switch · _photo_pick ( result · source · bytes ) · _render ( duration_ms · output_bytes · result ) · _share_tap (주 지표) · _share_result (주의 §6-7 ④) · _screenshot (iOS 보조 신호) · _error ( stage 7종)

F. 푸시 — push_* (8)

push_received (포그라운드만) · push_opened ( app_state · elapsed_sec — 열람의 정본) · push_deeplink_failed (구버전 미대응 탐지) · push_ inbox_open · push_inbox_item_tap · push_consent_view · push_consent_result ( os_granted · app_agreed — 1차 KPI) · push_permission_de nied_modal

G. 코치마크·튜토리얼 — tutorial_* 11 + onboarding_* 7

tutorial_tour_start · _step_view ( render_mode ) · _step_complete ( dwell_ms ) · _step_skip (어디서 새는지의 정본) · _tour_complete · _ tour_abandon ( reason ) · _step_skipped_by_condition · tutorial_anchor_missing (★ 화면 개편 시 앵커 미이동을 잡는 유일한 신호 — 알람 필수) · _anchor_offscreen · _measure_slow · _spec_override_invalid onboarding_flow_start · _step_view · _step_complete · _step_skip

- _flow_complete · _flow_abandon · _resume — 전부 flow_id 부착

### 6-5. 프로퍼티 정책 — Event / User 2층 구조

```text
 구분               Event Property                             User Property


 의미               행동 당시의 컨텍스트                                유저의 현재 상태·장기 특성

 저장               이벤트 로그마다 기록                                유저별 1개 값(최신 상태)

 갱신               시점 기반, 실시간                                 배치/서버 동기화(주기 1일 이상)

 활용               퍼널·흐름·행동 분석                                CRM·타겟팅·리텐션 세그먼트 (L4 원료)
```

전 이벤트 공통 Event Property

```text
 속성                                                      값                   이유


  user_id                                                내부 유저 id            필수 — §1-2 기준. 비로그인 이벤트는 anonymous_id 발급 후 로그
```

인 시 병합(identity resolution)

```text
  record_source                                          GYM | OUTSIDE       기록 관련 전 이벤트에 부착 (§9 R5)

  exercise_session_id                                    서버 세션 id (있         서버 DB와 조인 가능하게
```

을 때만)

```text
  feature_flag_*                                         각 기능 플래그            단계 개방 A/B 판정
```

상태

```text
  entry_point                                            진입점                 진입점이 늘어도 이벤트명을 분화하지 않는다(§6-6-4)

  flow_id                                                앱↔웹 퍼널 조            목표 등록·온보딩
```

인키

```text
  session_id · gym_id · screen_name · event_time (KST    공통 컨텍스트             화면·지점·버전 축 분석
```

명시) · app_version · os

```text
  device_tier                                            기기 등급               미정 앱 전역 유저 속성으로 승격 권장(저사양 성능 분석)
```

User Property 4유형

```text
 유형             갱신 규칙                   짐박스 예시


 불변 상태          최초 설정 후 변경 금지            signup_channel , first_plan_created_at
```

<!-- 원문 PDF 17쪽 -->

```text
유형             갱신 규칙                     짐박스 예시


누적 상태          조건 충족 시 true, 이후 유         has_created_plan , has_used_gorder , has_pt_experience
```

지

```text
현재 상태          주기 갱신/서버 동기화               membership_type , current_streak_weeks


윈도우 상          배치 쿼리로 주기 갱신               is_low_visitor_30d (직전 30일 1–3회 방문) — L4 세그먼트 1호의 원료, is_plateau_biceps_14d (정체 감
태                                        지)
```

- 생성 조건: 현재 상태를 설명하면서 분석·CRM에서 반복 필터링에 쓰일 때만 만든다. 빈번히 바뀌는 값은 이벤트 프로퍼티로.

- membership_type 은 이벤트 프로퍼티가 아니라 유저 프로퍼티다(상태이지 행동 컨텍스트가 아니다).

- 보안: user id 원값을 유저 프로퍼티에 넣지 않는다.

- 스냅샷 프로퍼티: 퍼널 진입~완료 구간에서 동일 값을 지속 추적해야 할 때(예: 플랜 생성 설문의 goal_type , A/B 구분값) 구간 내 전 이벤트에 부착한다.

### 6-6. 이벤트 경제성 원칙 — 이벤트 수 폭증 방지

1. 모든 경로를 이벤트로 만들지 않는다 — 속성으로 경로를 간소화한다. a화면→b화면 전환은 양쪽 screen_view 로 파악 가능하므로 단

순 "다음" 클릭 이벤트는 생략한다.

2. 클릭은 최대한 하나의 이벤트 + button 프로퍼티로 통합한다 — 홈 카드 탭 전체를 dashboard_card_click + card_type 하나로. 단, 핵

심 퍼널이면서 추가 프로퍼티가 필요한 클릭(플랜 생성·PT 매칭 등)은 별도 이벤트로 설계한다.

3. 핵심 지표가 걸린 퍼널은 화면 진입(view)과 클릭(click)을 모두 설계한다 — 이벤트 손실 방지 + 화면 개선 A/B 가능성 확보.

4. entry_point 설계 기준: 기존 플로우에 신규 진입점(푸시·딥링크·배너)이 추가돼도 기존 퍼널 이벤트명은 유지하고 entry_point 프로

퍼티로 구분한다. 진입점별 퍼널 전환율이 필요하면 퍼널 내 전 이벤트에, 최종 결과만 필요하면 마지막 이벤트에만 부착한다. Habit OS는 푸시 진입(플랜 유도·스트릭 위기·PT 추천)이 많아 이 규칙이 없으면 이벤트명이 진입점마다 분화된다. 주의 공용 이벤트(여러 도메인에서 로깅)는 이벤트명만으로 특정 퍼널 전환율을 재지 않는다 — 프로퍼티로 분류한 뒤 해석한다.

### 6-7. 스크린 레지스트리 — 화면·기능 전수 매핑

"현재·개편 후 짐박스 앱의 모든 화면·버튼·기능에 이벤트가 매핑되어 있다"를 보장하는 방법. 커버리지는 선언이 아니라 절차로 강제한 다.

1. 화면 인벤토리 취합 (원천 3종): ① 위키 UserApp Index(플로우 PRD 40종) + IA 개요(온보딩+탭바 5개, Figma 크로스체크 완료본)

② Figma 최신 개편 디자인 ③ 1단계 6기능의 신규 화면(목표·캘린더·플랜·요약 이미지·튜토리얼 등)

2. 스크린 레지스트리 문서화: screen_name enum의 단일 원천. 화면ID·화면명·진입 경로·포함 버튼/인터랙션 목록을 위키 단일 문서로

관리한다. 등록되지 않은 screen_name 은 QA에서 리젝한다.

3. 화면×이벤트 커버리지 매트릭스: 모든 화면 = 최소 screen_view 1개, 모든 버튼/인터랙션 = 별도 이벤트 또는 button 프로퍼티 값으

로 귀속(§6-6-2 적용). 매트릭스 공란 0 = 계측 QA 통과 조건.

4. 유지 절차: 신규 화면은 레지스트리 등록 없이 배포 불가(DoD), 릴리스마다 레지스트리 diff 리뷰 — "기능 먼저, 계측 나중"의 재발

방지 장치.

### 6-8. 충돌·한계 정리

```text
#      항목                          확정


①      활동 탭 기존 exercise_ma         '같이 운동하기' 이벤트다. 재사용 금지. 운동 기록은 workout_record_ 네임스페이스
```

ke_click · exercise_list_ click

```text
②      푸시의 후속 행동 이벤트               신규로 만들지 않는다. T2→ calendar_plan_add , T3→ summary_image_create , T5→ template_create ,
```

T6→ goal_detail_view 를 entry_point='push' 로 재사용

```text
③      웹뷰 계측 발송 방식                 웹에서 직접 Firebase. postMessage 브리지 위임 금지(유실 위험, 기존 브리지는 ALERT 용도로만 검증됨)
```

<!-- 원문 PDF 18쪽 -->

```text
#   항목           확정


④   공유 성사        주의 측정 불가. Android Share.share() 는 취소해도 sharedAction 을 반환한다 → 허위 수치를 만들어낸다. expo-
```

sharing 단일 경로로 통일하고 "공유 성사율"을 지표로 정의하지 않는다. KPI는 summary_image_share_tap uniq / summary_image_open uniq 하나뿐

```text
⑤   푸시 도달        FCM analyticsLabel = 근사(플랫폼 집계) · push_received = 부분(포그라운드만) · push_opened = 정확(탭 시점)
```

이나 배너를 안 누르고 앱을 열면 안 잡힌다 → 최종 판정은 후속 행동("T1 수신군의 당일 출석률 vs 대조군")

```text
⑥   A/B 인프라 부재   자연 대조군으로 대체 — 발송군 outcome='SENT' vs 대조군 outcome='BLOCKED' AND block_reason IN
```

('DAILY_CAP','WEEKLY_CAP') . 주의 완전 무작위가 아니므로 보조 지표로만. 정식 A/B는 2단계 미정

```text
⑦   is_read      지표에서 배제(§9 M1)
```

<!-- 원문 PDF 19쪽 -->

## 7. To-Be L3 — DW 설계

### 7-1. 착수 시점과 진입 조건

착수: 로드맵 3단계. 1단계에서 하지 않는 이유는 둘이다.

1. 도구 선정(§18-2)이 예산·법무(데이터 국외 이전)·팀 역량 판단을 요구한다.

2. 무엇보다 원천이 정리되기 전에 DW를 만들면 결함을 그대로 복제한다. started_at 의미가 흔들리고(E-2) 총무게 산식이 틀린(E-9)

상태로 fact_workout 을 만들면 잘못된 숫자에 정본 지위를 부여하는 셈이다.

진입 조건 (전부 충족 시 착수)

```text
#      조건                                                                                        현황


1      Wave 1~6 스키마 배포 완료 + D+30 안정화                                                             진행 예정

2      이벤트 97종 수신 검증 통과(§10-4)                                                                   Wave별

3      주 경계· started_at · source 등 지표 정의가 용어사전에 등재(§18-3 N-1·N-5·N-15)                               미정


4      DW·제품분석 도구 선정 완료                                                                              미정


5      이벤트를 DB와 조인 가능한 형태로 내릴 경로 확보(현재 Firebase/Braze에 갇힘)                                           미정
```

### 7-2. 구조

스테이징(원천 무변형 적재: DB CDC 또는 일배치 + 이벤트 스트림) → 정제(스타 스키마) → 마트(도메인별).

핵심 설계는 dim_user 중심이다. 모든 fact가 user_key 로 조인된다 — §1-2 기준의 물리적 구현이 이 층에서 완성된다.

```text
테이블                              그레인       답하는 질문                        주요 원천


 dim_user                        고객 1명     누구인가 (인구통계·가입월차·멤버십 상태·세그먼    user , 멤버십
```

트)

```text
 fact_order                      주문 1건     누가·언제·무엇을·몇 개·어디서·얼마에 — 도메인   order_ledger 또는 매핑 뷰(§5-5) + food_
                                           통합 주문                         order


 fact_visit                      출석 1건     언제·어느 지점·주간 빈도 (북극성 지표 원천)    access_history


 fact_workout                    운동 세션 1   무엇을·얼마나 (부위·볼륨·완료율·작성률)       user_exercise_session 3층 + source
```

건

```text
 fact_goal_progress              유저×주 1건   목표를 지켰나 (달성률·연속 달성)           user_goal_weekly_progress


 fact_engagement                 이벤트 1건    앱에서 무엇을 했나 (퍼널·리텐션)           L2 이벤트 스트림

 fact_push                       발송 1건     보냈나·닿았나·열었나·막혔나               push_delivery_log + push_opened


 dim_gym / dim_exercise / dim_   지점/운동/일   축 공통화                         마스터
date                             자
```

### 7-3. 지표 레이어 (metric as code)

- 지표(주간 방문·주2회 비중·유지율·작성률·목표 달성률 등)를 SQL 정의로 코드화하고 용어사전과 1:1 연결한다.

- 이렇게 하면 "같은 지표 다른 수치" 문제가 원천 차단된다. 정의 변경은 PR 리뷰로만 한다.

<!-- 원문 PDF 20쪽 -->

- 주의 지표 정의에는 §9 R5( source 분리)가 반드시 반영되어야 한다 — 북극성(주간 방문)에 OUTSIDE 는 미포함, 목표 달성률에는 포 함이다. 같은 원천을 쓰지만 규칙이 다르다.

- 도구 후보: BigQuery/Redshift + dbt. 판단 기준은 AWS 기존 스택 정합·비용·팀 역량(§18-2).

<!-- 원문 PDF 21쪽 -->

## 8. To-Be L4 — CDP 설계

### 8-1. 역할

```text
dim_user   + 이벤트를 고객 프로필로 통합 → 세그먼트 정의 → 채널(푸시·인앱) 타겟팅 → 반응을 다시 이벤트로 회수하는 루프.
```

### 8-2. 이미 만들어진 1차 구현 — push_schedule

Wave 5의 push_schedule + PushGateway + push_delivery_log 가 이 루프의 첫 구현체다.

```text
 루프 단계         1차 구현                                                   한계


 세그먼트 정        배치 쿼리(트리거별 대상 산출)                                       DW가 아니라 배치 코드 안에 정의가 있다 — 재사용·버전 관리
 의                                                                     불가

 발송 스케줄        push_schedule ( uq_dedup ·조용시간·상한)                      —

 채널 발송         PushGateway → messaging-lambda → FCM                    —

 결과 회수         push_delivery_log (지표 정본·판정 스냅샷 6컬럼) + push_opened 이    도달은 근사(§6-8 ⑤)
```

벤트

```text
 효과 판정         자연 대조군( SENT vs BLOCKED(CAP) )                          무작위가 아니므로 보조 지표
```

따라서 4단계 CDP 본격화는 "인프라 신설"이 아니라 "세그먼트 원천을 DW로 옮기는 일"이다. 발송 인프라는 이미 있다.

### 8-3. 유스케이스

```text
 #      세그먼트                                          액션                        측정


 1호     직전 30일 1–3회 저방문 활성층 ( is_low_visitor_30d )    스트릭 위기·플랜 생성 넛지 푸시        구간 상향 이동률(주간 방문 4회+ 전환)

 2호     부위 성장 정체 감지 ( is_plateau_*_14d )              PT 추천 푸시                  PT 상담 전환·매칭률

 후보     운동 직후 G오더 미구매                                 쿠폰 푸시                      coupon_used → 매출 귀속(기존 gifticon 체계)
```

세그먼트 원료는 §6-5의 윈도우 상태 User Property다. 즉 L2 프로퍼티 설계가 L4의 입력이 된다.

### 8-4. 도구 선택지 (미결 — §18-2)

```text
 옵션                    구성                                        판단 기준


 (a) SaaS 제품분석 + 엔     Amplitude/Mixpanel + Braze류 — 이벤트 SDK·    빠른 가동, 구독 비용, 데이터 국외 이전 법무 검토 필요. 주의 Braze는 이
 게이지먼트                 세그먼트·캠페인 일체                               미 logEvent 경로에 연결되어 있다

 (b) 자체 구축             이벤트 파이프라인 + DW 세그먼트 쿼리 + 자체 발송            비용 통제·유연, 개발 리소스 大. 주의 발송단( push_schedule )은 이미 자
```

체 구축됨

```text
 (c) 하이브리드 (권고 검       제품분석 SaaS(계측·퍼널) + 세그먼트는 DW→ pu           현실적 균형. 현재 구조가 이미 (c)에 가깝다
 토안)                   sh_schedule 자체 발송
```

### 8-5. Clarity 재배치

- 정성 리플레이 전용으로 유지한다. 정량 제품 분석·CDP를 대체하지 않는다.

<!-- 원문 PDF 22쪽 -->

- 저비용 개선 병행: 화면 이름 태깅 + custom id(내부 user_id 해시) 주입 → 정량 도구와 세션 단위 상호 참조 가능.

- 주의 선행: 개인정보 처리방침 반영 여부 법무 확인(§18-2) · 요약 이미지 셀피 화면 마스킹 강제 · 웹뷰 별도 설치 여부 미정 (N-12).

<!-- 원문 PDF 23쪽 -->

## 9. 데이터 운영 원칙 14조

1단계 6개 개발계획이 각각 "기획안에 등재 필요"로 올린 항목의 통합본. 신규 스키마·코드는 예외 없이 준수하고, 기존 코드는 각 Wave에서 순 차 교정한다.

```text
#     원칙                 내용                                                                                     근거


R1    입력 원본(값+단          사용자가 10 lb로 입력하면 weight_value=10 · weight_unit='lb' 그대로 저장한다. 집계·비교용 w                 E-4 · 공통 §7
      위)을 저장하고, 집        eight_kg 는 생성 컬럼( GENERATED ALWAYS AS (IF(weight_unit='lb', weight_value*0.45359237,
      계용 kg는 DB가         weight_value)) STORED )으로 DB가 계산한다. 애플리케이션은 환산을 하지 않는다 — 이것이 E-4(이중
      자동 계산              변환)의 구조적 재발 방지책이다. 표시는 저장된 원본 단위 그대로, 다른 단위 표시가 필요하면 조회 시 계
```

산

```text
R2     count 는 exerc     현행 unit='MINUTE' 인데 값은 초를 담는다 — 이름과 값이 어긋나 오합산(E-9)의 원인이 된다. enum                      공통 §7 · E-9
      ise.unit 에 종속      을 SET / SECOND 로 바꾸고 값도 초로 통일한다(마이그레이션 필요, DA-P0-11 열차 합류). SET 이면 횟
      하고, 단위명은 실         수, SECOND 면 초. 집계 시 반드시 unit으로 분기
```

제 저장값과 일치 시킨다

```text
R3    삭제는 비활성화           status='INACTIVE' . 물리 삭제 금지 — 과거 기록·달성률·참조 무결성 보존. 주의 메가폰 배지 회수만 아                    공통 §7
      (soft delete)      직 물리 삭제(2단계 전환 미정 )

R4    유일성은               애플리케이션 검증만으로는 동시 요청에서 깨진다. 순서는 order_no + UNIQUE, 재정렬은 2-pass(음                        공통 §7
      UNIQUE 제약으로        수 경유)
```

DB가 강제

```text
R5    지표 산출 시 sou        북극성(주간 방문)에 source='OUTSIDE' 는 미포함. 단 목표 달성률에는 포함한다 — 목적이 다르므로 규                       용어사전 G-1 · 운
      rce 분리 필수          칙이 다른 것이 정상. gym_value / outside_value 를 분리 저장해 정책 변경 시 재계산 가능하게 한다                    동목표 §5-5

C1    모든 날짜·시각 판         kstDayRange() · kstWeekRange() · kstToday() . 주 경계는 월요일 00:00 KST( 미정 전사 확정 대          캘린더 §5-1 실증
      정은 KST · 단일        기 — N-1). 다른 방법으로 변환하지 않는다. server·batch에 동일 구현. 전역 TZ 설정에 의존하지 않는                     3건(T-1·T-2·T-3)
      헬퍼로만               다(app-server는 있고 batch는 핸들러마다 제각각)

C2    날짜는 date , 시       "그 날"을 timestamp 로 두면 UTC→KST 하루 밀림이 구조적으로 발생한다. 시각 판정용 컬럼은 UTC                        캘린더 §2-2 · 푸
      각은                 저장 + KST 재현용 컬럼 병기( local_send_on · local_send_minute · local_on ) — 인덱스 range 스       시 §2-2
       timestamp (UTC)   캔을 위해 CONVERT_TZ 를 WHERE에 쓰지 않는다

G1    스냅샷 불변 — 마         목표값·산식 규격은 생성 시점 값을 user_goal_action 에 복사한다. in-place UPDATE 금지, 변경은 새                 운동목표 §2-3
      스터 변경이 과거          세대 생성. "지난주에 달성했던 것이 오늘 미달로 바뀌는" 현상을 원천 차단
```

지표를 소급 변경 하지 않는다

```text
S1    1인 1건 강제는 생        문제 — "사용자당 활성 목표는 1개"를 애플리케이션 코드로만 검사하면, 동시에 두 요청이 오면 둘 다 통                            운동목표 §2-3 ·
      성 컬럼 +             과해 2개가 생긴다. 해결 — DB에 UNIQUE(user_id, 활성여부) 를 걸면 되는데 MySQL에는 "활성 행만                     캘린더 §2-2 · 운
      UNIQUE             대상으로 하는 UNIQUE"(부분 UNIQUE)가 없다. 그래서 활성일 때만 1, 비활성이면 NULL이 되는 컬럼                        동기록 §2-2
      (쉽게: "활성 목표는       을 DB가 자동 생성하게 한다 — active_flag GENERATED ALWAYS AS (IF(status='ACTIVE',1,NULL))
      1인당 1개"를 코드가       STORED + UNIQUE(user_id, active_flag) . MySQL은 NULL끼리는 중복으로 보지 않으므로 활성은 1
      아니라 DB가 막게 하       건만, 비활성 이력은 무제한이 된다. 같은 원리로 비활성 행의 round_number 를 NULL로 만들어
      는 기법)              UNIQUE에서 배제한다

X1    계속 늘어나는 분          문제 — DB enum 은 허용값 목록이 스키마에 박혀 있다. 푸시 트리거 종류처럼 앞으로 계속 늘어날 값을                           푸시 §2-2 · 튜토
      류값은 DB enum        enum으로 만들면 값 하나 추가할 때마다 ALTER TABLE + 배포가 필요하다. 해결 — 그런 컬럼은 varc                       리얼 §2-2
      대신 varchar         har 로 두고 허용값 검증은 애플리케이션 코드가 한다. 코드 배포만으로 값을 늘릴 수 있다. 반대로 SET /
      (쉽게: 값을 하나 추       SECOND 처럼 거의 안 바뀌는 닫힌 집합은 DB enum을 유지한다 — DB가 잘못된 값을 막아주는 이점이
      가할 때마다 DB 변경       더 크다
```

- 배포가 필요해지는 것을 피하는 기법)

<!-- 원문 PDF 24쪽 -->

```text
#       원칙              내용                                                                                 근거


J1      집계 대상 값의        JSON은 SQL 집계가 불가하다. 리스트는 정규화 테이블로. 불가피한 JSON( push_schedule.params )은              설계 원칙 5
        JSON 저장 금지      "집계 대상 아님"을 스키마 주석에 명시하고, 집계가 필요한 값은 전용 컬럼으로 뺀다

M1      is_read (알림 읽   문제 — 사용자가 푸시 배너를 직접 탭하면 앱이 읽음 처리 API를 아예 호출하지 않는다. 반대로 알림함에                        푸시 §6-3
        음 여부)를 지표로      서 "모두 읽기"를 누르면 안 본 알림까지 전부 읽음이 된다. 그래서 현재 읽음률 5.3%는 관심도가 아니라
        쓰지 않는다          계측 결함을 보여주는 숫자다. 해결 — 지표는 push_opened 이벤트를 정본으로 쓴다. is_read 컬럼은
        (쉽게: 이 컬럼은 실    앱 동작 호환을 위해 남기되 리포트·의사결정에서는 배제한다. 같은 이유로 notification.type 기준 집
        제로 읽었는지를 반      계도 금지(채팅방 이름 약 150종이 섞여 있음) — trigger_type 을 쓴다
```

영하지 못해 숫자가 틀린다)

```text
M2      측정 불가능한 것       "공유 성사율"처럼 플랫폼이 알려주지 않는 값은 지표로 만들지 않는다. 측정 가능한 대리 지표( share_                       요약이미지 §6-3
        을 KPI로 정의하지     tap )로만 목표를 세우고 플랫폼 한계를 명시한다. 허위 신호를 만들어내는 API(Android Share.share )
        않는다             는 애초에 쓰지 않는다

PII     민감정보는 집계로       신규 등재: user_body_metric.height_cm · weight_kg (신체정보) · notification.type 의 채팅방 자   운동목표 §2-5 ·
        만 다루고 원값을       유기재명 · 요약 이미지의 셀피(Clarity 마스킹·크래시 리포트 경로 기록 금지). 기존 목록( trainer_sch                요약이미지 R7
        노출하지 않는다        edule.title · payment_history.card_number · buyer )에 추가하고 지표_테이블맵 하단 PII 목록과 동
```

기화. 신체정보는 개인정보 동의문에 항목이 없다 → 법무 확인 후 플래그 ON

### 9-1. 파생 데이터 운영 원칙

- machine_substitute 는 한 번 만들고 끝나는 데이터가 아니다. 기구 마스터( machine )를 HQ가 상시 write( HQ/gym.dao.ts: 384-398,404-415 ), 지점 보유( gym_machine )를 branch-admin이 write( :175,:338 )한다 → 주기 재계산 필수. 재계산은 멱등 upsert 로 하고 트레이너 검수분( source='TRAINER' )은 보존한다( batch_run_id 로 이번 실행 미확인 RULE 행만 정리).

- 캐시된 후보라도 지점 보유 확인은 매번 실시간으로 한다( gym_machine 교집합). 전역 후보 132종 → 지점 내 평균 5.0종.

- 정기 관측이 필요한 무거운 집계는 배치가 파일/집계 테이블로 남긴다 — 상시 쿼리 금지(DB 분석 업무방식 — 추출 1회·로컬 반복).

- 모든 스케줄 작업은 gymboxx-user-app-batch (Serverless cron) 로 만든다 — app-server에 @nestjs/schedule 의존성이 없다(T-5).

<!-- 원문 PDF 25쪽 -->

## 10. 거버넌스·품질·QA 자동화

### 10-1. 택소노미 정본 관리

- 이벤트·enum·지표 정의의 정본은 본 문서와 그 하위 문서다. 스크린 레지스트리(§6-7)가 screen_name 의 단일 원천이다.

- 신규 화면·기능 DoD에 "이벤트 정의·QA 완료"를 포함한다(설계 원칙 3).

- 용어사전 등재는 지표 정의의 최종 착지점이다 — Wave별 DOC 태스크로 관리(§18-3 N-15).

### 10-2. 이벤트 명세 생성 프로세스 (6단계 게이트)

설계 → 데이터 검토 → 명세 기록(필수) → dev 반영 → QA → prod 반영

- 명세 기록 없이 dev 착수 금지. 이벤트 명세와 유저 프로퍼티 명세는 각각 위키 지정 문서에 기록한다.

- 목적: "코드에만 존재하는 이벤트"를 만들지 않는다.

### 10-3. PII 정책

- 이벤트·원장·DW에 이름/전화번호/카드 원값 저장 금지. user_id 로만 연결한다.

- DW 적재 시 마스킹/제외 1호 목록: payment_history.card_number · buyer · trainer_schedule.title (사전 미고지 회원명 자유기재) · n otification.type (채팅방명 오염) · user_body_metric.height_cm · weight_kg .

- 자유기재 텍스트에 회원명이 들어가는 입력을 신규로 만들지 않는다.

- 요약 이미지 셀피: Clarity 세션 리코딩 마스킹 강제, 크래시 리포트에 파일 경로 기록 금지.

- 신체정보는 개인정보 동의문에 항목 자체가 없다 → 법무 확인 후 수집 플래그 ON(§18-3 N-8).

- PII 전체 목록은 지표_테이블맵 하단과 동기화한다.

### 10-4. 데이터 QA 자동화

```text
항목                          구현


enum 드리프트 감지                신규 값 등장 알림. notification.type 오염(P-3) 전례가 근거

 user_id 결측률 임계 알림          신규 21종은 전부 user_id 필수라 대상은 기존 테이블(§4-2)

이벤트 수신량 급변 알림               Firebase 콘솔 + tutorial_anchor_missing 알람(일 3배 또는 step_view 의 20% 초과)

배치 건강                       처리 건수·duration·적체·좀비를 CloudWatch + 슬랙( BATCH/utils.ts sendSlackMessage 기존 패턴)

배포 후 검증 쿼리                  각 개발계획 §3에 Wave별로 확정 병기. Q-2 계열 무거운 쿼리는 배포 검증 1회만

동의 철회율 감시                   ★ 푸시의 브레이크. 주간 철회율이 기준선 1.5배 초과 시 트리거 축소 — 운영 규칙으로 명문화

원천↔DW 건수 대사                 L3 착수 후. 이중 기록 기간(§5-5 옵션 c)에는 payment_history ↔ order_ledger 일일 대사
```

<!-- 원문 PDF 26쪽 -->

## 11. 실행 트랙 정의

### 11-1. 왜 "병렬 트랙"인가

데이터 자산화 전부를 끝내고 Wave 1을 시작하는 순차 관계가 아니다. 하반기 전체 업무를 고려해 "지금 할 수 있는 것·지금 먼저 해야만 하는 것"부터 끝내고 Wave 1을 시작한다. 나머지는 Wave 1~6과 같은 시간축에서 굴러간다.

이 구조가 필요한 이유는 셋이다.

1. 선행 대상의 선별 기준은 "지금 먼저 해야만 하는가"이지 "데이터 업무인가"가 아니다. 그래서 §11-3의 판정 기준이 필요하다.

2. 경계가 애매한 이유는 운동기록 결함이 Wave 1의 개발 범위와 같은 파일·같은 ALTER 문장을 건드리기 때문이다. 애매함을 없애는

방법은 하나 — 소유권을 한쪽으로 몰고 다른 쪽에서 지운다(§11-5).

3. 데이터 자산화를 제대로 시작하려면 운동기록의 오류를 먼저 해결해야 한다. 오염된 원천 위에 계측을 얹으면 틀린 값을 정밀하게 수

집하게 된다.

### 11-2. 업무 범위 (PO 확정, 2026-07-27)

```text
#     범위                                                       본 문서에서의 대응


1     이 기획안 문서에 있는 업무 전부                                       §5~§10의 설계·원칙을 §12 WP로 전량 전개

2     현재 상태가 아니라 로드맵 1~4단계 전체에 대응 가능한 데이터 수집·분석 인프라            §14 (재작업 0 조건을 명시)

3     현재 발생 중인 모든 데이터 수집·적재 오류 개선                              §13 결함 49건 실행 대장 (전건 배치)
```

### 11-3. P0 / P1 / P2 정의와 판정 기준

```text
구분          정의                 Wave 1과의 관계                                                 WP 수


P0 · 선행     지금 먼저 해야만 하는 것     Wave 1 착수 게이트. 전건 DoD 충족 전에는 Wave 1 개발을 시작하지 않는다            17

P1 · 병렬     지금 할 수 있는 것        Wave 1~6과 동시 진행. 릴리스 열차(§5-2)를 공유한다                         27

P2 · 후속     지금은 불가능한 것         3단계(DW)·4단계(CDP) 이후. 도구 선정·예산·법무가 선행                        12
```

P0 판정 기준 — 아래 G1~G4 중 하나라도 해당하면 P0

코

```text
       기준                               왜 미룰 수 없나
```

드

```text
G1     지금도 데이터를 오염시키는 중                 오늘 들어오는 행이 계속 틀린다. 늦출수록 오염 구간이 길어지고 소급 보정이 불가능해진다

G2     법적·보안 리스크                        리스크가 시간에 비례해 누적된다. 리드타임이 긴 외부 판단(법무)은 착수 자체가 지연 요인
```

이다

```text
G3     스키마·데이터 선행 정합화가 없으면 이후 작업이 실패    UNIQUE 생성 실패·ALTER 중복 실행 등 기술적으로 순서를 바꿀 수 없는 항목

G4     전사 정의가 확정되지 않으면 여러 기능이 동시에 어긋    주 경계· started_at 처럼 4개 이상 기능이 같은 값을 참조한다. 나중에 바꾸면 전 기능 재작
       남                                업
```

P0 제외 규칙 (남용 방지) — G1~G4에 걸려도 아래면 P0가 아니다. - Wave 1~6의 신규 화면·신규 테이블에 물리적으로 종속되는 항목 (그 화면이 없으면 실행할 수 없다) → P1 - 개선이 아니라 신규 기능 추가인 항목 → 해당 Wave

<!-- 원문 PDF 27쪽 -->

P1 판정 기준 — 아래를 모두 만족 - 지금 착수할 수 있다(선행 결정·외부 판단 대기 없음) - P0 게이트가 아니다(Wave 1 착수를 막지 않는 다) - 기존 코드 전수 교정 · 계측 실행 · 신규 원천 신설 · 데이터 보강 중 하나에 해당

P2 판정 기준 — 아래 중 하나라도 해당 - 도구 선정·예산·법무가 선행해야 한다 (DW·CDP·A/B 인프라) - 원천 정리 완료(전 Wave 배포 + D+30 안정화) 후에만 의미가 있다 (DW 적재·지표 레이어) - 과거 데이터 복원이 불가능해 신규 차단만 가능하고, 과거분 처리는 DW 적 재 시점에만 성립한다

### 11-4. 게이트 판정 규칙

- Wave 1 착수 가능 = P0 17건 전부 DoD 충족. 부분 통과·조건부 착수는 없다.

- 법무 의뢰 항목(DA-P0-15·16)의 P0 DoD는 "의뢰 접수 확인"까지다. 회신은 리드타임을 통제할 수 없으므로 게이트에 넣지 않는 다. 단 회신은 Wave 2(신체정보)·Wave 5(광고성 판정)의 블로커로 승계된다(§18).

- 판정 근거는 각 WP의 DoD 산출물이며 판정 기록을 본 문서 §16-4에 남긴다.

### 11-5. Wave 티켓 중복 제거 원칙 ★

각 기능 개발계획에는 이미 Linear 이슈가 분해되어 있다( WR- · SET- · GOAL- · CAL- · SUM- · PUSH- · TUT- ). 데이터 자산화가 항목을 가져 오면 그쪽 티켓은 반드시 지운다.

```text
 원칙              내용


 소유권 단일          하나의 작업에 티켓은 하나. DA WP가 가져온 항목은 각 Wave 개발계획의 태스크 표에서 행 삭제 + "→ DA-Pn-xx로 이관
```

(2026-07-27)" 주석을 남긴다

```text
 릴리스 열차는 공       소유권과 배포 단위는 별개다. DA WP가 소유해도 gymboxx-lib 릴리스 열차(§5-2)와 배포 순서는 §5-2를 그대로 따른다
```

유

```text
 소비는 중복이 아       각 Wave의 계측 티켓이 DA가 만든 스크린 레지스트리·이벤트 명세 대장을 소비하는 것은 중복이 아니다. 이런 티켓은 그대로 둔다
```

니다

```text
 분할은 명시적으로       한 결함을 P0/P1로 쪼갠 경우(예: E-1 스키마/기능) 양쪽 WP에 서로를 참조하고, 각 Wave 티켓에는 어느 쪽이 남는지를 적는다

 반영 책임           이관 주석을 각 개발계획에 반영하는 것은 Harvey의 P0 기간 내 작업이다(§12-2 DA-P1-27에 포함)
```

이관 요약 — 각 Wave에서 삭제되는 티켓

```text
 소스       삭제 대상                                                                                 이관처


 운동기록     WR-PRE-1 · WR-PRE-3 · WR-PRE-4 · WR-LIB-1 · WR-DB-1 · WR-DB-2 · WR-CL-5 · WR-CL-6 ·   DA-
          WR-CL-15 (총무게·잔재분)                                                                    P0-02·10·06·11·07·08·09

 운동기록     WR-SV-2 ~ SV-4 · SV-8 ~ SV-10 · CL-7 · CL-8 · CL-11 · CL-14 · CL-16                   DA-P1-16

 운동세트     SET-PRE-4 · SET-PRE-5 (스키마 병합·차분 승인분)                                                 DA-P0-11

 운동목표     GOAL-PRE-2 · GOAL-PRE-4                                                               DA-P0-01·16

 캘린더      CAL-PRE-1 · CAL-PRE-3 · CAL-SV-1 · CAL-SV-9 · CAL-BT-4                                DA-P0-01·03·05 / DA-P1-13

 요약이미     SUM-CL-9 · SUM-SV-3 의 TZ 수정분                                                          DA-P0-09·04
```

지

```text
 푸시알림     PUSH-PRE-2 · PUSH-SV-6 · PUSH-DB-2 · PUSH-MSG-2 · PUSH-BT-6                           DA-P0-15 / DA-P1-15·07·13

 코치마크     — (전건 잔존. 앵커·온보딩은 Wave 1~5 배포 후에만 가능)                                                 —
```

주의 CAL-PRE-3 (pt.dao.ts TZ 버그)은 §5-3 ⑥에서 이미 PUSH-BT-6 (경로 폐기)로 대체 확정됐다. 이번 이관으로 최종 소유는 DA-P1-13이며 캘린더·푸시 양쪽에서 삭제한다.

<!-- 원문 PDF 29쪽 -->

## 12. 작업 패키지(WP) 분해

### 12-0. 표기 규칙

```text
 항목                  규칙


 키                   DA-{트랙}-{일련} — 예 DA-P0-01 . Linear 이슈와 1:1. 재사용·재번호 금지


 규모                  S = 0.5~1일 · M = 2~3일 · L = 4일 이상 (1인 기준 순수 작업시간)

 담당                  Vonn(PO·기획) · Harvey(PM) · Rothy(Design) · Jenna(FE) · Alan(BE)

 Linear 라벨           track/data-assetization + p0 | p1 | p2 + area/server | client | lib | db | analytics | ops


 판정                  P0는 §11-3의 G1 ~ G4 중 어디에 걸려 P0가 됐는지를 반드시 표기
```

Design(Rothy) 원칙 (2026-07-27 확정): 이 트랙에서 Rothy는 계측 정의 협업만 한다 — 화면 인벤토리·스크린 레지스트리 검토. 산출물이 있는 태스크는 두지 않는다. 표에서 Rothy는 (검토) 로만 등장한다.

### 12-1. P0 · 선행 — Wave 1 착수 게이트 (17건)

DA-P0-01 · 주 시작 요일 전사 확정

```text
 담당           Vonn

 판정           P0 · G4

 설명           목표·스트릭·챌린지·캘린더가 각자 주 경계를 계산한다. 스트릭 DAO는 YEARWEEK(..., 1) (월요일 시작), 챌린지는 challenge_calendar , 목
```

표·캘린더는 신규 정의다. 하나라도 다르면 모든 주간 지표가 어긋난다. 제안값은 월요일 00:00 KST

```text
 선행           —

 산출물          결정문 1건 + §9 C1 갱신 + 용어사전 주 경계 항목

 DoD          ① 월요일 00:00 KST가 확정되어 본 기획안 §9 C1 · 용어사전 · 공통 데이터모델 3곳에 동일 문장으로 반영 ② 운동목표·캘린더·요약이미지·
```

푸시 4개 개발계획의 주 경계 서술이 전부 이 값을 참조하도록 수정

```text
 규모           S

 주의 중복           GOAL-PRE-2 · CAL-PRE-1 삭제(두 문서 모두 "한쪽에서만 처리"를 이미 명시)
```

제거

DA-P0-02 · started_at 의미·채우기 규칙 확정

```text
 담당          Vonn(결정) · Alan(구현 규격)

 판정          P0 · G4 (+G1 — 현재 값이 이미 틀렸다)

 설명          E-2. started_at 이 출석 시각을 복사해 운동 시간 평균 111분, 3시간 초과 1,431건. 요약 이미지가 대외 노출물이라 잘못된 숫자가 SNS에 박제
```

된다. 결정 항목 3개 — ① GYM 세션의 기준(세션 생성 시각 vs 첫 운동 추가 시각) ② OUTSIDE 세션의 채우기(클라 전송값 vs 서버 NOW() )와 clamp 범위(미래 금지·과거 24h) ③ 과거 행 소급 보정 없음을 전제로 한 경계 상수

```text
 선행          —
```

<!-- 원문 PDF 30쪽 -->

```text
 산출물     결정문 + WAVE1_SESSION_TIME_EPOCH 상수명·값 확정 + 용어사전 운동 시간 항목

 DoD     ① 3개 결정이 문서화 ② 시계열 지표에 구조적 단절이 생김을 명시하고 GROUP BY source, (created_at < EPOCH) 강제 규칙을 §9에 등재 ③
```

운동기록 §5-1 표와 요약이미지 duration_basis 판정이 이 값을 참조

```text
 규모      S

 주의 중    WR-PRE-1 삭제. SUM-SV-6 ( duration_basis + 환경변수)은 Wave 4 잔존 — 이 결정을 소비만 한다
```

복 제거

DA-P0-03 · KST 단일 헬퍼 구현 (server · batch)

```text
 담당      Alan

 판정      P0 · G1 · G4

 설명      §9 C1. kstDayRange() · kstWeekRange() · kstToday() 를 gymboxx-app-server 와 gymboxx-user-app-batch 양쪽에 동일 시그니처로 구
```

현한다. 전역 TZ 설정에 의존하지 않는다 — app-server에는 tz.setDefault 가 있고 batch는 핸들러마다 제각각이라 T-1이 발생했다. 이 헬퍼 가 없으면 DA-P0-04·05를 고쳐도 다음 핸들러에서 재발한다

```text
 선행      DA-P0-01 (주 경계 값 확정)

 산출물     두 repo의 utils/kst.ts + 경계 단위 테스트 12종

 DoD     ① 두 repo 동일 구현 ② 캘린더 개발계획 §8-1 타임존 경계 시나리오 12종 전부 통과 ③ moment().startOf('day') · dayjs() 의 날짜 판정
```

목적 직접 호출 잔존 0건(grep 결과를 PR 본문에 첨부)

```text
 규모      M

 주의 중    CAL-SV-1 삭제. SUM-SV-3 은 이 헬퍼를 재사용해야 하며 중복 구현 금지(Wave 4에는 주차 파라미터화·104주 범위 제한만 잔존)
```

복 제거

DA-P0-04 · 스트릭 타임존 버그 수정 (T-3)

```text
 담당          Alan · Harvey(CS 사전 공유)

 판정          P0 · G1

 설명          DAO는 YEARWEEK(..., 1) KST 변환 주차를 만드는데 서비스( user.service.ts:4314-4317 )가 dayjs() 로 서버 로컬 TZ 기준 주차를 계산한
```

다. 서버가 UTC면 KST 월요일 00:00~08:59에 "이번 주"가 지난 주가 된다. 홈의 "N주 연속"이 이미 틀렸을 수 있다

```text
 선행          DA-P0-03

 산출물         수정 PR + 회귀 테스트 + CS 공지문

 재현          서버 TZ=UTC 환경에서 시스템 시각을 KST 월요일 00:30(= UTC 일요일 15:30)으로 고정 → 홈 스트릭 조회 → 직전 주 기준 값 반환

 DoD         ① dayjs() → kstWeekRange() 교체 ② TZ=UTC 컨테이너에서 KST 월 00:30 / 월 09:30 / 일 23:30 3케이스 값 일치 ③ 수정 후 사용자에게
```

보이는 수치가 바뀌므로 배포 전 CS 사전 공유 완료

```text
 규모          S

 주의 중복       SUM-SV-3 의 TZ 수정분만 삭제. 주차 파라미터화·104주 제한은 Wave 4 잔존
```

제거

<!-- 원문 PDF 31쪽 -->

DA-P0-05 · 챌린지 주 경계 · 캘린더 선택 버그 수정 (T-1 · T-4)

```text
 담당      Alan

 판정      P0 · G1

 설명      ① T-1: challenge-handler.ts:515-516 의 moment().startOf('day') 가 TZ 미설정(이 핸들러에 tz.setDefault 없음)이라 challenge_cal
```

endar.start_at 이 KST 09:00을 가리킨다. round 219 실측값 2026-07-20 00:00:00 UTC. ② T-4: challenge.dao.ts:68-83 의 getOnGoing ChallengeCalendar 가 상태 조건 없이 id 최댓값을 반환한다 — 잘못된 캘린더 1건이 전 사용자 주 경계를 오염시킨다

```text
 선행      DA-P0-03

 산출물     수정 PR 2건 + 상태별 픽스처 테스트

 재현      ① SELECT id, start_at FROM challenge_calendar ORDER BY id DESC LIMIT 5 → start_at 이 UTC 00:00(= KST 09:00) ② 종료된 캘린더
```

를 최신 id로 삽입 후 getOnGoingChallengeCalendar 호출 → 종료분 반환

```text
 DoD     ① 신규 생성 round의 start_at 이 KST 00:00 = UTC 전일 15:00 ② 상태 픽스처 4종(예정·진행·종료·취소)에서 진행 건만 반환 ③ 캘린더 독
```

립 계산 이중 방어(§4-5 T-4 해소안) 적용

```text
 규모      S

 주의 중    CAL-BT-4 · CAL-SV-9 삭제
```

복 제거

DA-P0-06 · 운동 세션 소유자 검증 (E-10, 보안)

```text
 담당          Alan

 판정          P0 · G2 (현재도 재현 가능)

 설명          user-exercise.service.ts:186-195 가 access_history 의 존재만 확인하고 소유자를 확인하지 않는다. 타인의 access_history_id 로 세션
```

을 생성할 수 있다

```text
 선행          — (독립 · 최우선 착수)

 산출물         핫픽스 PR + 회귀 테스트

 재현          계정 A의 JWT로 POST /user/{A}/exercise-session 에 계정 B의 access_history_id 를 실어 호출 → 현재 201

 DoD         ① accessHistory.user_id !== userId 면 400 ② 회귀 테스트 등재 ③ 과거 오염 여부 실측 1회 — user_exercise_session s JOIN
```

access_history a ON s.access_history_id=a.id WHERE s.user_id <> a.user_id 건수를 조사해 결과를 본 WP에 기록

```text
 규모          S

 주의 중복       WR-PRE-4 삭제. 유사 IDOR인 PUSH-SV-9 (알림 읽음 소유자 검증)· TUT-SV-5 (튜토리얼 4엔드포인트)는 각 Wave 잔존 — 데이터 오염이 아니
 제거          라 각 기능 고유 경로다
```

DA-P0-07 · detail 진입 시 자동 서버 저장 차단 (E-3)

```text
 담당       Jenna

 판정       P0 · G1 (가장 직접적인 오염원)

 설명          detail/index.tsx:267-268 에서 화면 진입만 해도 이전 세트가 PUT .../set 으로 오늘 기록에 저장된다. 하지 않은 운동이 기록에 남는다 —
```

총 세트·총 무게·기록 작성률이 전부 오염된다. applyPreviousRecord ( :174-210 )에 persist 인자를 추가해 자동 경로에서 서버 호출을 차단 한다

```text
 선행       — (독립 병렬)
```

<!-- 원문 PDF 32쪽 -->

```text
 산출물     수정 PR + QA 시나리오

 재현      이전 기록이 있는 운동을 세션에 추가 → detail 화면 진입 후 아무 입력 없이 뒤로가기 → user_exercise_set_history 에 오늘자 세트 행이 생
```

성됨

```text
 DoD     ① 같은 시나리오에서 세트 행 0건 ② 수동 [이전 기록 적용] 경로( :585-600 )는 계속 저장 ③ 배포 후 D+7에 workout_record_set_save 의
```

is_prefilled=true 비율 하락을 확인(=실제 입력 비율의 기준선 확보)

```text
 규모      S

 주의 중복   WR-CL-5 삭제
```

제거

DA-P0-08 · lb 이중 변환 수정 (E-4)

```text
 담당       Jenna

 판정       P0 · G1

 설명       DB는 항상 kg인데 weight_type='lb' 면 불러올 때 다시 kg로 변환한다( detail/index.tsx:100 ). 불러올 때마다 ×0.4536 — 사용자 무게가
```

계속 줄어든다. 표시부( :811-813 )는 kg 값에 lbs 라벨을 붙인다. 변환 방향이 정반대다

```text
 선행       — (독립 병렬)

 산출물      수정 PR

 재현          weight_type='lb' 계정에서 60 입력 → 저장 → 재진입 시 27.2 → 다시 재진입 시 12.3


 DoD      ① :100 의 convertLbsToKg 제거, :811-813 에서 kg→lbs 변환 후 렌더 ② 3회 재진입 후에도 값 불변 ③ 표시 라벨과 값의 단위 일치 ④
```

§9 R1(" weight 는 항상 kg로 저장, weight_type 은 표시 단위") 준수를 PR 체크리스트에 명시

```text
 규모       S

 주의 중복       WR-CL-6 삭제
```

제거

DA-P0-09 · 총무게 산식 정정 + 공용 헬퍼 추출 (E-9)

```text
 담당      Jenna(클라) · Alan(서버 산식 정합)

 판정      P0 · G1

 설명      summary/index.tsx:86-92 가 weight × count 를 unit·null· is_done 필터 없이 합산한다. 20분 러닝이 weight×1200 이 된다. complete
```

화면( :73-75 )은 type === "SET" 만 합산해 올바르므로 두 화면이 다른 값을 보여준다. MINUTE 포함 세션 2,777건 = 기록 보유 세션의 18.3%(5건 중 1건)

```text
 선행      — (독립 병렬)

 산출물     src/utils/exercise.ts 의 sumTotalWeight() + 두 화면 적용 + 단위 테스트


 재현      MINUTE 단위 운동(러닝 등)이 포함된 세션에서 complete 화면과 summary 화면의 총 무게 값 비교 → 불일치

 DoD     ① 헬퍼 1개로 단일화 ② MINUTE 포함 픽스처 10종에서 summary = complete = 서버 집계 3값 일치 ③ is_done=false · weight IS NULL
```

제외 규칙 반영 ④ §9 R2( count 는 exercise.unit 에 종속) 준수

```text
 규모      S

 주의 중    SUM-CL-9 삭제 · WR-CL-15 의 총무게분 삭제(non-null 단언· console.log · getSingleMachineId 정리는 DA-P1-16으로 이관). SUM-
 복 제거    SV-1 (서버 집계 산식 확정 + AG-1~10 테스트)은 Wave 4 잔존하되 본 WP의 헬퍼 규칙을 정본으로 참조
```

<!-- 원문 PDF 33쪽 -->

DA-P0-10 · round_number 중복 데이터 사전 정합화 (E-5a)

```text
 담당              Alan

 판정              P0 · G3 (이게 안 끝나면 uq_session_round DDL이 실패한다)

 설명              운동 교체 시 1,2,2 가 발생하고 삭제 API가 -1 감소시켜 충돌한다. UNIQUE 제약 생성의 절대 전제다. 세션별 id ASC 재넘버링 스크립
```

트를 실행한다

```text
 선행              —

 산출물             실측 쿼리 결과 + 재넘버링 스크립트 + 실행 로그

 재현              SELECT user_exercise_session_id, round_number, COUNT(*) c FROM user_exercise_session_history GROUP BY 1,2 HAVING c > 1


 DoD             ① 위 쿼리 0행 ② 스테이징 → 프로덕션 순차 실행, 각 단계 소요시간·영향 행수 기록 ③ 스크립트를 재실행해도 결과가 같은 멱등성 확인

 규모              S

 주의 중복 제         WR-PRE-3 삭제. UNIQUE 생성은 DA-P0-11, replace API(E-5b)는 DA-P1-16
```

거

DA-P0-11 · gymboxx-lib 4.29.0 열차 + 기존 테이블 ALTER 통합 실행 (E-1a)

```text
 담당          Alan

 판정          P0 · G3

 설명          §5-2 규칙 1(ALTER 1회)의 소유자. user_exercise_session ( access_history_id nullable · source · template_id · program_slot_
```

id · idx_user_source_started )과 user_exercise_session_history ( status · deleted_at 추가 · round_number nullable · uq_sess ion_round )의 전 컬럼 변경을 한 ALTER 문장으로 통합해 실행하고, gymboxx-lib 4.29.0을 이 ALTER 대응분으로 확정 배포한다. 운동기록· 운동세트가 각각 ALTER 계획을 갖고 있어 두 번 실행하면 배포가 깨진다(§5-3 ①)

```text
 선행          DA-P0-10 (중복 정합화) · DA-P0-02 ( started_at 규격이 DTO에 반영돼야 함)

 산출물         lib 4.29.0 npm 배포 · DDL-A/B/C 마이그레이션 스크립트 · 소비 repo 승격 계획

 DoD         ① 스테이징 → 프로덕션 DDL 실행, INSTANT/INPLACE 알고리즘 명시 + 소요시간 계측 ② access_history_id nullable 확인(E-1a 해소)
```

③ uq_session_round 생성 성공 ④ 소비 repo lib 영향 조사 완료 — gymboxx-user-app-batch (4.28.5)·HQ·branch-admin이 이 엔티티를 읽는지 확인하고 승격 필요 repo 확정, gymboxx-pass-server (3.6.1) 승격 불필요를 회귀로 증명 ⑤ 롤백 계획 문서화

```text
 규모          L

 주의 중복       WR-LIB-1 · WR-DB-1 · WR-DB-2 · SET-PRE-4 · SET-PRE-5 (스키마 병합·차분 승인분) 삭제
```

제거

```text
 ** §5-2     신규 테이블 CREATE 17종(운동세트 6 · 목표 9 · 캘린더 2)은 ALTER가 아니라 CREATE라 충돌 표면이 0이다. 따라서 SET-LIB-1 · GOAL-
 규칙 1 정      LIB-1 · CAL-LIB-1 과 각 DB-1 은 각 Wave 잔존하고 4.29.x 후속 마이너로 합류한다. GOAL-DB-1 의 마스터 시드는 GOAL-PRE-3 (콘텐츠 시
 밀화**        트)에 종속되므로 Wave 2 잔존. 이 정밀화를 §5-2 규칙 1에 반영해야 한다(§18 신규 미결 D-3)
```

DA-P0-12 · 이벤트 → DB 조인 경로 확보 (BigQuery — 기연결 확인됨)

```text
 담당        Alan · Vonn(설계·검증)

 판정        P0 · G3
```

<!-- 원문 PDF 34쪽 -->

```text
설명     §2-3 L2의 핵심 공백 — logEvent() 가 Firebase/Braze로 보내지만 분석 측에서 DB와 조인할 수 없다.
```

★ 2026-07-27 확인: gymboxx-app 의 BigQuery Export는 과거부터 이미 연결돼 있다. 따라서 이 WP는 당초 상정한 "신규 연결"이 아니라 ① 적재 상태 점검 ② 조회 경로(MCP) 확보 ③ DB 조인 성립 증명으로 범위가 축소된다. Wave 1 이전 구간의 이벤트도 이미 보유하고 있으므로 소 실 리스크는 해소됐다. 다만 user_id 부착 여부는 별개 문제다 — 이벤트에 user_id 가 실려 있지 않으면 데이터가 있어도 §1 기준(고객 ID 기준 해석)을 못 맞춘다. 이 검증이 이 WP의 실질 핵심이며, 미부착이면 DA-P1-02(래퍼)로 즉시 넘긴다

```text
선행     GCP 권한 확보 — roles/mcp.toolUser · roles/bigquery.jobUser · roles/bigquery.dataViewer (2026-07-27 Firebase 관리자 권한 확보
```

완료, BigQuery 3종은 별도 부여 필요)

```text
산출물    BigQuery MCP 커넥터 등록 + 적재 시작일·최신일 실측 + 이벤트 종류·볼륨 목록 + user_id 부착률 + DB 조인 샘플 쿼리 + 비용 메모. 설정 절
```

차: BigQuery 확장 등록 가이드

```text
DoD    ① BigQuery MCP 커넥터 등록 완료 — 클로드가 직접 조회 가능한 상태 ② 적재 실측 기록 — events_* 최초·최신 날짜, 이벤트 종류별 30일 볼
```

륨 ③ user_id 부착률 실측 — 미부착이면 DA-P1-02를 선행으로 승격 ④ DB 조인 샘플 분석 1건 성립 — "현재 불가능한 것이 가능해졌음"의 증 명 ⑤ 쿼리 비용·보존 정책 메모 ⑥ 데이터 국외 이전 판단을 DA-P0-16 법무 의뢰에 포함(데이터셋 리전 확인 포함)

```text
규모     S (기연결 확인으로 M → S 축소)

주의 중   신규 — 기존 티켓 없음. Braze 발송 경로는 그대로 유지한다(§6-1)
```

복 제거

DA-P0-13 · 스크린 레지스트리 v1

```text
담당     Vonn(작성) · Rothy(검토 — 개편 Figma 대조) · Harvey(QA 리젝 규칙 운영)

판정     P0 · G4

설명     §6-7. screen_name enum의 단일 원천. 원천 3종을 취합한다 — ① UserApp Index(플로우 PRD 40종) + IA 개요 ② Figma 최신 개편 디자인
```

③ 1단계 6기능의 신규 화면. 레지스트리가 없으면 각 Wave가 screen_name 을 제각각 지어 붙이고, 그 순간 화면 축 분석이 영구히 불가능해진 다

```text
선행     —

산출물     20_Areas/gymboxx/UserApp/스크린 레지스트리.md     미정 (경로 확정 필요) — 화면ID · 화면명 · 진입 경로 · 포함 버튼/인터랙션 목록


DoD    ① 현행 화면 전수 등재(IA 개요의 온보딩 + 탭바 5개 + 플로우 PRD 40종 커버) ② screen_name enum 초판 확정 ③ "등록되지 않은 screen_
```

name 은 QA 리젝" 규칙을 6개 개발계획의 DoD에 삽입 ④ Rothy 검토 완료 서명(개편 디자인과의 차이를 <span class='undecided'>미정</ span> 로 표기)

```text
규모     M

주의 중   신규. 각 Wave의 계측 티켓( WR-CL-17 · SET-CL-12 · CAL-OPS-1 · SUM-OPS-1 · PUSH-CL-5 · TUT-* )은 이 레지스트리를 소비만 하므로 잔존
```

복 제거

DA-P0-14 · 이벤트 명세 대장 개설 + 6단계 게이트 가동

```text
담당     Vonn

판정     P0 · G4

설명     §10-2. 명세 기록 없이 dev 착수 금지를 실제로 강제할 물리적 장치. 이벤트 명세와 유저 프로퍼티 명세를 각각 위키 문서로 개설하고, 각 이벤트
```

의 게이트 진행 상태(설계 → 데이터 검토 → 명세 기록 → dev 반영 → QA → prod 반영)를 컬럼으로 관리한다. 목적은 하나 — "코드에만 존재 하는 이벤트"를 만들지 않는다

```text
선행     DA-P0-13 ( screen_name enum이 프로퍼티 규격에 들어간다)

산출물    이벤트 명세 대장(97종) + 유저 프로퍼티 명세(§6-5 4유형)
```

<!-- 원문 PDF 35쪽 -->

```text
 DoD     ① §6-4의 97종 전부 행이 존재 ② P0 시점 최소 필수 컬럼(이벤트명 · 네임스페이스 · 소유 Wave · 게이트 상태)이 채워짐 ③ 프로퍼티 타입 규
```

칙(§6-2-7)과 enum 사전 등록제가 대장 서식에 반영 ④ 6개 개발계획의 계측 티켓 DoD에 "명세 대장 상태 = 명세 기록 이상"을 삽입

```text
 규모      S

 주의 중    신규
```

복 제거

DA-P0-15 · 심야·광고성 푸시 즉시 차단 + 법무 의뢰 (P-7a · P-1a)

```text
 담당     Vonn(법무 의뢰) · Alan(스케줄 조정·인벤토리)

 판정     P0 · G2

 설명     실측 — 7일 기준 00~05시 2,536건 · 21~23시 16,498건 발송. 광고성이면 정보통신망법 위반 소지다. 동의 게이트는 sendAppPush( 179개 호
```

출부 중 2곳(1.1%)만 확인하고, app_push_agreement=false 인 50,956명에게도 발송될 개연이 있다. Wave 5(조용시간 정식 구현)까지 기다리 면 그 기간 내내 리스크가 누적된다. P0 범위는 "즉시 멈추는 것"까지이고 정식 구현은 DA-P1-13

```text
 선행     —

 산출물    ① batch cron 시각 조정 PR ② 179 호출부 인벤토리 ③ 법무 의뢰서

 DoD    ① 야간에 발화하는 배치 스케줄( serverless.yml cron)을 KST 08:00~21:00 창으로 이동 — 코드 로직 변경 없이 스케줄만 조정 ② D+7 실측
```

야간(21:00~08:00 KST) 발송 0건. 단 거래성·CS 예외 경로는 목록으로 사전 승인 ③ 179 호출부 인벤토리 완성(경로 · 트리거 · 광고성 추정 · 동 의 확인 여부) ④ 법무 의뢰 접수 확인 — 의뢰 항목: (a) COMEBACK 등 트리거의 광고성 분류 (b) 거래성 푸시가 app_push_agreement 를 무시해도 되는가 (c) 야간 21~08시 규정 적용 범위

```text
 규모     M

 주의 중   PUSH-PRE-2 삭제. PUSH-BT-* 의 조용시간 정식 구현은 DA-P1-13으로 이관
```

복 제거

DA-P0-16 · 신체정보·PII 법무 의뢰 + PII 대장 갱신

```text
 담당     Vonn

 판정     P0 · G2

 설명     §10-3. 신체정보( height_cm · weight_kg )는 개인정보 동의문에 항목 자체가 없다 — Wave 2가 user_body_metric 을 신설하는 순간 미고지
```

수집이 된다. Clarity custom user id 주입과 요약 이미지 셀피 마스킹도 처리방침 반영 여부가 미확인이다. DA-P0-12의 이벤트 국외 이전 판단 도 같은 의뢰에 묶는다

```text
 선행     — (DA-P0-12와 병행)

 산출물    법무 의뢰서 3건 + 지표_테이블맵 PII 목록 갱신

 DoD    ① 법무 의뢰 접수 확인 3건 — (a) 신체정보 동의 항목 신설 (b) Clarity custom id · 셀피 마스킹의 처리방침 반영 (c) 이벤트 데이터 국외 이전
```

(BigQuery/Firebase) ② 지표_테이블맵 PII 목록에 신규 3종 등재 — user_body_metric.height_cm · weight_kg · notification.type (채팅 방 자유기재) · 요약 이미지 셀피 ③ 회신 전까지 신체정보 수집 플래그 OFF를 Wave 2 DoD에 못 박음

```text
 규모     S

 주의 중    GOAL-PRE-4 삭제. SUM-QA-5 (셀피 미유출 실기 검증)는 Wave 4 잔존 — 정책이 아니라 검증 실행이다
```

복 제거

<!-- 원문 PDF 36쪽 -->

DA-P0-17 · P0 지표 정의 용어사전 등재

```text
담당       Vonn

판정       P0 · G4

설명       §2-4 답변 규칙("지표 질문은 정의부터")의 실행. P0에서 확정된 정의를 용어사전에 등재하지 않으면 Wave 1~6이 각자 해석한다. P0 범위는 6
```

항목이고 나머지 전량은 DA-P1-25

```text
선행       DA-P0-01 · DA-P0-02 · DA-P0-09

산출물      용어사전 6항목

DoD      ① 주 경계 · 운동 시간(started_at 기준) · 기록 보유 세션 · 총 무게 · source(GYM/OUTSIDE) 분리 규칙 · 북극성 = 주간 방문 횟수
```

(재확인) 등재 ② 각 항목에 계산식 · 제외 조건 · 검증 쿼리 병기 ③ §9 R5(북극성에 OUTSIDE 미포함 / 목표 달성률에는 포함)의 비대칭을 명시 적으로 기술

```text
규모       S

주의 중        WR-DOC-1 · SUM-DOC-1 · CAL-DOC-1 의 용어사전 등재분 중 위 6항목만 삭제. 각 문서의 mechanics·API Index 갱신분은 잔존
```

복 제거

### 12-2. P1 · 병렬 — Wave 1~6과 동시 진행 (27건)

P0와 달리 표 형식으로 둔다. 티켓 발행 시 각 행이 그대로 Linear 이슈 1건이 된다. 선행이 비어 있으면 즉시 착수 가능.

A. 계측 실행 인프라 (7건)

```text
                                                                                                                  규   주의 중복
키       제목            담당          설명 (무엇을 · 왜)                                        선행       산출물 · DoD
                                                                                                                  모   제거


DA-     이벤트 택소        Vonn        DA-P0-14가 만든 대장의 빈칸을 채운다 — 트리거·프                    DA-      97종 전부 게이트 상태      L   각 Wave
P1-01   노미 97종 명                  로퍼티·타입·enum 값·소유 Wave. §6-4의 요약 서술                  P0-14    명세 기록 이상 · 프           계측 티켓
        세 완성 +                    을 실행 가능한 명세로 전개                                              로퍼티 타입 규칙              은 소비만
        Wave 배분                                                                                (§6-2-7) 위반 0건 ·       — 잔존
```

enum 값 사전 등록 완 료

```text
DA-     logEvent()    Jenna       현행 CLIENT/src/utils/log.ts:7-10 은 인자를 그대            DA-      래퍼 도입 + 기존 호출      M   신규
P1-02   공통 프로퍼                    로 통과시킨다. §6-5의 전 이벤트 공통 프로퍼티( us                    P0-12    부 전수 치환 · user_
        티 자동 주입                   er_id · session_id · gym_id · screen_name · app_             id 미부착 이벤트 0건
        래퍼                        version · os · event_time (KST)· feature_flag_* )            (BigQuery 검증 쿼리)
                                  를 개별 호출부가 빼먹지 않도록 래퍼가 자동 주입한                                 · WR-CL-17 보다 먼저
                                  다. 이게 없으면 97종 × 8속성을 손으로 붙이다 반드                              완료
```

시 누락된다 — DA-P0-12의 DB 조인은 user_id 부 착이 전제

```text
DA-     화면×이벤트        Vonn ·      §6-7-3. 모든 화면 = 최소 screen_view 1개, 모든               DA-      매트릭스 문서 · 릴리       M   신규
P1-03   커버리지 매        Rothy(검     버튼 = 별도 이벤트 또는 button 프로퍼티 값으로 귀                    P0-13,   스마다 diff 리뷰 절차
        트릭스           토)          속. 매트릭스 공란 0 = 계측 QA 통과 조건                          DA-      등재 · 공란 0
```

P1-01

```text
DA-     계측·데이터        Alan        §10-4. ① enum 드리프트 감지(신규 값 등장 알림 —                  DA-      4종 가동 + 각 1회 의     M   신규
P1-04   QA 자동화 4                  notification.type 오염 전례) ② user_id 결측률              P0-12    도적 실패 주입으로 알
        종                         임계 알림(기존 테이블 대상) ③ 이벤트 수신량 급변 알                              림 도달 확인
```

림 + tutorial_anchor_missing 알람(일 3배 또는 s tep_view 의 20% 초과) ④ 배치 건강(처리 건수

- duration·적체·좀비 → CloudWatch + 슬랙,

```text
                                  BATCH/utils.ts   sendSlackMessage 기존 패턴)
```

<!-- 원문 PDF 37쪽 -->

```text
                                                                                                                          규    주의 중복
 키       제목              담당          설명 (무엇을 · 왜)                                        선행          산출물 · DoD
                                                                                                                          모    제거


 DA-     이벤트↔DB          Vonn ·      DA-P0-12가 경로를 열었다면 이 WP는 그 경로로 실                    DA-         트레이스 3종 재현 쿼         M    신규
 P1-05   조인 리허설 +        Alan        제 답이 나오는지를 증명한다. §17-2 트레이스                         P0-12,      리 + 결과 · 실패 지점
         지표 재현 3종                    A·B·C를 BigQuery + DB 조인으로 재현                        DA-         을 §18에 등재
```

P1-02

```text
 DA-     Clarity 화면      Jenna       §4-4 실측 — 방문 URL 전량 빈값(22.9만 세션),                   DA-         화면 이름이 Clarity 대     M    신규.
 P1-06   태깅 ·                        custom user id 미연결. 화면 이름 태깅 + 내부                   P0-13,      시보드에 표시 ·                 SUM-
         custom id ·                 user_id 의 해시 주입(원값 금지) + 요약 이미지 셀피                  DA-         custom id로 세션 조           QA-5 (미
         셀피 마스킹                      화면 마스킹 강제                                           P0-16 법     회 성립 · 셀피 화면 리            유출 검증)
         (I-5a · N-12)                                                                   무 회신        코딩에 이미지 미포함               는 Wave
                                                                                                     (실기 확인)                   4 잔존

 DA-     analyticsL      Alan        MSG:145-147 이 'push_lambda' 로 고정돼 전 푸시가             DA-         Firebase 콘솔에서 트      S    PUSH-
 P1-07   abel → tr                   한 덩어리다. 한 줄 변경으로 Firebase 콘솔에 트리거                   P1-11       리거별 분해 확인                 MSG-2 삭
         igger_type                  별 전송·열람이 열린다 — 투입 대비 이득이 가장 큰 항                                                           제
         (I-3)                       목
```

B. 계측 공백 해소 (2건)

규

```text
 키       제목              담당       설명 (무엇을 · 왜)                                  선행             산출물 · DoD             주의 중복 제거
```

모

```text
 DA-     온보딩 퍼널          Jenna    gbx_step1~3_click 3개가 전부이고 welcome-           DA-            7종 수신 검증 · 퍼      M   Wave 6 TUT-ON-* 은
 P1-08   계측 신설                    new-member 이후 0건이다. onboarding_* 7종을          P1-01          널 리포트 1건 산출           온보딩 기능 구현 —
         (I-1)                    심어 "어디서 새는가"를 답할 수 있게 한다                                                           잔존. 본 WP는 현행
```

온보딩에 대한 계측만

```text
 DA-     목표 등록 웹         Jenna    목표 등록 퍼널이 전량 웹뷰라 앱 계측과 단절돼                    DA-            flow_id 로 앱↔      M   신규. TUT-WEB-1 (온
 P1-09   뷰 계측 + f        · Alan   있다. goal_wv_* 8종을 웹에서 직접                      P1-01,         웹 퍼널이 하나로             보딩 flow_id 반향)
         low_id 조                 Firebase로 발송(postMessage 브리지 위임 금             DA-            이어지는 쿼리 1건            은 Wave 6 잔존
         인 키 (I-2)                지 — 유실 위험)하고 flow_id 로 앱 이벤트와 조               P1-02          성립 · 8종 수신 검
                                  인한다                                                          증
```

C. 푸시·알림 결함 (6건)

규

```text
 키       제목               담당       설명 (무엇을 · 왜)                             선행            산출물 · DoD                     주의 중복 제거
```

모

```text
 DA-     푸시 동의 게이         Alan     DA-P0-15가 만든 인벤토리를 바탕으로 sen              DA-           179곳 전부 게이트 통과         L      신규(2단계 → P1
 P1-10   트 전수 교정                   dAppPush( 179개 호출부 전부에 동의 확인을            P0-15,        또는 거래성 예외 목록에                 승격)
         179곳 (P-1b)               강제한다. 현재 확인하는 곳은 2곳(1.1%). 원             법무 회          등재(예외는 근거 명시) ·
                                   래 2단계 과제였으나 결함 49건 전부 DA 트랙              신              app_push_agreement=
                                   처리 결정으로 P1로 당겼다                                        false 대상 발송 0건
```

(D+7 실측)

```text
 DA-      notification    Alan     enum 선언에도 채팅방 이름 약 150종이 저               4.30.0        신규 행의 type 이           M      PUSH-MSG-3 의 t
 P1-11   .type 신규 오                장된다(원천 COMM/                             열차            enum 값만 · trigger_            rigger_type 저장
         염 차단 + tr                 notification.service.ts:44,58,67 ). 자유                 type 저장 · type 기준             분과 통합 — 그쪽
         igger_type                기재라 PII 위험이기도 하다. 신규 저장을 차단                            집계 금지를 §9 M1에                 삭제
         저장 (P-3a)                 하고 집계는 trigger_type 으로 전환                              반영

 DA-      read_at 추       Alan     is_read 5중 결함으로 실측 읽음률이                  DA-            read_at 기록 · 배너 직     M      PUSH-SV-9 의 re
 P1-12   가 + is_read               1.58%~53.35%(34배 차이)다 — 이건 "열            P1-11         접 탭 시 read 호출 · 리             ad_at 분 삭제
         지표 배제                     람률"이 아니라 "알림함 방문률"이다. read_                            포트에서 is_read 배제               (IDOR 소유자 검증
         (P-4)                     at 을 추가하고 지표 정본은 push_opened 이                         가 §9 M1과 용어사전에                은 Wave 5 잔존)
                                   벤트로 고정                                                 명시
```

<!-- 원문 PDF 38쪽 -->

규

```text
키       제목             담당       설명 (무엇을 · 왜)                             선행            산출물 · DoD                     주의 중복 제거
```

모

```text
DA-     조용시간 · 발       Alan     DA-P0-15는 cron 시각 이동이라는 임시 조치            4.30.0        상한 초과 발송 0건 · 야           L     PUSH-BT-6 (구 s
P1-13   송 상한 · de               다. 정식 구현은 push_schedule 의                열차            간 발송 0건 · dedup_              endWorkoutAlarm
        dup_key 정식               uq_dedup + 조용시간(21:00~08:00 KST 기                     key 중복 0건 · 차단 사              경로 폐기) 삭제 —
        구현 (P-6 ·               본) + 일 2 · 주 7 상한. 실측 30일 1인 최대                        유가                              CAL-PRE-3 을 대체
        P-7b)                   249건, 30건 초과 2,969명                                    push_delivery_log.b           하던 티켓이므로 여
                                                                                       lock_reason 에 남음              기서 최종 소유

DA-     OS 권한 동기       Jenna    동의율 86.6%인데 OS 권한이 60.1% → 실도            —             NULL 잔존 1% 미만 · 온         M   신규
P1-14   화 + 도달 KPI     · Alan   달 53.4%(203,871 / 381,526). system_pu                  보딩 KPI를 "OS 권한 허
        재정의 (P-5)               sh_agreement IS NULL 50,062명(13.1%)                    용률"로 재정의해 용어
                                미동기화                                                   사전 등재 · NULL은
```

false 취급 규칙 명시

```text
DA-     메가폰 배지 중       Alan     동의 토글 반복으로 706명 · 2,155행 중복 적            —             createUserBadge 선조        M     PUSH-SV-6 ·
P1-15   복 방지 · 1회               재. 회수가 물리 DELETE라 §9 R3 위반이다.                          회 가드 · 중복 2,155행                PUSH-DB-2 삭제
        정리 · soft               원래 soft delete 전환은 2단계였으나 P1로                          1회 정리 · 물리
        delete 전환               당겼다                                                    DELETE → status='
        (P-8)                                                                          INACTIVE' 전환 · 배지
```

총량 재측정

D. 운동기록·데이터 구조 결함 (6건)

```text
                                                                                                                          규    주의 중
키       제목                                            담당       설명 (무엇을 · 왜)               선행        산출물 · DoD
                                                                                                                          모    복 제거


DA-     운동기록 잔여 결함 9건                                 Alan ·   P0에서 걷어낸 나머지.              DA-       9건 전부 §13 대장          L    WR-
P1-16   (E-2b·E-5b·E-6·E-7·E-8·E-11·E-12·E-13·E-14)   Jenna    E-2b started_at 서버         P0-11     의 검증 기준 통과                 SV-2 ~ SV
                                                               채우기 구현 · E-5b uq_                                               -4 ·
                                                               session_round 활용 +                                              WR-
                                                                PUT .../replace 원자                                             SV-8 ~ SV
                                                               화 · E-6 "운동 삭제 후                                                -10 ·
                                                               종료"가 실제로 삭제하                                                    WR-
                                                               게(현재 DELETE 호출 0                                                CL-7 · CL
                                                               건) · E-7 이전 기록 조회                                               -8 · CL-1
                                                               에 is_deleted · end_                                             1 · CL-1
                                                               at · is_done 필터 추                                               4 · CL-1
                                                               가( dao.ts:314-330 ) ·                                           6 · WR-
                                                               E-8 3시간 하드 만료 제                                                 CL-15
                                                               거 + 12h 서버 마감 배                                                 잔재분
                                                               치 · E-11~14 위생 4건                                               삭제

DA-     외부 기록 기능 결합 (E-1b)                            Alan ·   DA-P0-11이 access_          DA-       source='OUTSIDE'      L    WR-
P1-17                                                 Jenna    history_id 를               P0-11     세션 생성·조회·종료                PRE-2 · WR
                                                               nullable로 만들었다면,                     성립 · WR-                   -
                                                               이 WP가 실제로 출석 없                       PRE-2 (DTO                 SV-1 · WR
                                                               이 기록할 수 있게 한다                        optional화)와 통합             -
                                                               — source 분기 API ·                    · OUTSIDE 세션의              CL-1 ~ CL
                                                               활동 탭 진입점 · 세션 목                      gym_id NULL 정              -4 · CL-1
                                                               록 화면. Wave 1 기능                      책(N-2) 확정                  0을본
                                                               범위와 겹치지만 E-1의                                                   WP로 통
                                                               완결 책임은 DA다                                                      합
```

<!-- 원문 PDF 39쪽 -->

```text
                                                                                                             규   주의 중
 키       제목                                     담당     설명 (무엇을 · 왜)             선행       산출물 · DoD
                                                                                                             모   복 제거


 DA-     추천↔실제 수행 연결 키 (S-8)                    Alan   exercise_recommenda      DA-      추천 경유 세션의 t         M   SET-
 P1-18                                                 tion_log 와 실제 수행         P0-11    emplate_id 채움률          SV-14 (값
                                                       을 잇는 키가 없어 "추천                    측정 가능 · 추천 이            채우기)
                                                       대로 했는가"를 DB로                      행률 쿼리 1건 성립             삭제
```

추적 불가하다. templ ate_id · program_slot_ id (DA-P0-11이 이미 컬럼을 추가)를 실제로 채운다

```text
 DA-     세션 마감 배치 + end_at / rpe 결측 개선 (S-2 ·   Alan   end_at IS NULL           DA-      배치 가동 후 D+30        M   WR-
 P1-19   S-3)                                          17.8%(32,241건) — 6       P1-16    신규 세션의 end_             SV-9 삭
                                                       건 중 1건은 운동 시간을                    at 결측 5% 미만 ·           제
                                                       그릴 수 없다. rpe IS                   자동 마감 식별 규칙
                                                       NULL 44.6%. 12h 서버                확정( rpe IS NULL
                                                       마감 배치로 신규분을 개                     AND end_at IS NOT
                                                       선하고, 자동 마감분을                      NULL 로 충분한지) ·
                                                       지표에서 구분할 식별 규                     rpe 는 "있을 때만
                                                       칙(N-4)을 확정한다                      표시" 규칙 명문화

 DA-     기록 보유 세션 8.4% — 베이스라인·추적 계측 (S-1)      Vonn   90일 세션 180,649건          DA-      기록 보유 세션 정          M   신규
 P1-20                                                 중 운동 1개 이상 담은            P0-17,   의·계산식 용어사전
                                                       세션 15,189건(8.4%).        DA-      등재 · 주간 추적 쿼
                                                       12건 중 1건이다. 요약           P1-01    리 고정 · P0 수정
                                                       이미지 V1의 존재 이유                     (E-3·E-4·E-9) 반
                                                       가 흔들린다. 개선은                       영 후 재측정 기준선
                                                       Wave 1 기능이 하지만,                   확보
```

무엇을 개선으로 볼지의 정의와 계측은 DA가 소 유한다

```text
 DA-     프로필·신체 원천 신설 (S-5a · S-6)              Alan   S-5: user_exercise_      4.29.x   두 테이블 가동 · 듀        M   Wave 2
 P1-21                                                 metadata 가 PK= user_     열차,      얼 라이트 정합성 검             GOAL-
                                                       id 단일 · 시간 컬럼 없          DA-      증 · 신체정보 수집             LIB-1 · G
                                                       음 → 이력 불가. 실측            P0-16    은 법무 회신 전까지             OAL-
                                                       23,765행 = 전체 회원의         법무 회     플래그 OFF                 DB-1 의
                                                       6.0%만 목적 등록, l           신(신체                             해당 엔
                                                       evel 은 2/5/7 딱 3값.       정보)                              티티 2종
                                                       user_exercise_prof                                        만 DA 소
                                                       ile 신설 + 듀얼 라이트                                           유, 나머
                                                       (추천 모듈이 직접 읽으                                             지 7종은
                                                       므로 폐기 불가). S-6: u                                         Wave 2
                                                       ser 테이블에 키·체중                                             잔존
```

컬럼이 0건이라 결과 목 표의 진행 지표를 그릴 수 없다 → user_body_ metric 신설

E. 기구 카탈로그 · 성능 · 정의 (6건)

<!-- 원문 PDF 40쪽 -->

```text
                                                                                                             규   주의 중복 제
키       제목                        담당       설명 (무엇을 · 왜)                           선행       산출물 · DoD
                                                                                                             모   거


DA-     기구 대체 매핑 + 카탈로그 결         Alan     M-1 대체 매핑 저장소 없음 → machine_s           4.29.x   배치 가동 + 커버리       L   SET-
P1-22   함                                  ubstitute · M-2 CARDIO·STRETCHING      열차       지 실측(전역 후보            BT-1 · SET-
        (M-1·M-2·M-4·M-5·M-6)              세부부위 없음(대체 커버리지 0%, 슬롯 298                      132종 → 지점 내           BT-2 · SET-
                                           건 전부 미커버) → source='RULE_CARDIO'                평균 5.0종) · 멱등         QA-2 삭제.
                                           별도 규칙 · M-4 CABLES 모델당 21.3개 운                  upsert로 트레이너          SET-
                                           동 → 가중치 조정 · M-5 gym_machine 이 실                검수분( source='         SV-13 (조회
                                           물 대수 단위(6,079대 = 모델 1,082종) →                   TRAINER' ) 보존 검       API)· SET-
                                           분석 단위를 machine (모델)로 강제 · M-6                   증 · 분석 단위 규칙          CL-10 (UI)
                                           exercise_machine 에 status · created_            을 §9-1에 등재            은 Wave 1
                                           at 없음 → N:M을 정본으로 확정                                                  잔존

DA-     기구 마스터 데이터 보강 —           Harvey   FREE_WEIGHT 148개 모델 중 108개가 운          DA-      108종 매핑 보강 또      L   신규
P1-23   FREE_WEIGHT 매핑 108종 +              동 매핑 없음(27.0%만 매핑) — 대체 후보의            P1-22    는 대체 대상 제외
        QR 미부착 실사 (M-3)                    진짜 구멍이다. 추가로 QR( unique_code )                  판정 · QR 미부착
                                           미부착이 CARDIO 1,541대(98.8%) ·                     실사 결과 + 부착 계
                                           FREE_WEIGHT 747대(80.6%) — QR 운동                 획 미정 · 결과를
                                           추가 동선이 카디오·프리웨이트에서 사실상                          카탈로그 실측에 등
                                           동작하지 않는다. 코드가 아니라 운영 데이터                        재
```

작업이다

```text
DA-     성능 3건 (Q-1 · Q-2 · Q-3)   Alan     Q-1 access_history (user_id,           캘린더      Q-1 인덱스 판정(추      M   PUSH-
P1-24                                      created_at) 복합 인덱스 부재(15.1M) —         D+14     가 또는 LIMIT 가          PRE-5 삭제.
                                           user_id 단일 인덱스로 평균 51.6행 스캔,           실측       드 유지) · Q-2 배치        캘린더 D-4
                                           극단 유저는 30일 10,790행. 캘린더 D-4 =                   집계 결과 테이블로            · 요약이미
                                           요약이미지 D-13 동일 사안이므로 한쪽에서                        대체 · Q-3 DBA 사        지 D-13 양
                                           만 결정(→ 여기) · Q-2 지점×기구 교차 커                     전 확인(INPLACE          쪽에서 삭제
                                           버리지 쿼리 26초 → 배포 검증 1회만, 상시                      폴백 시 KST 04~06        하고 여기로
                                           모니터링 금지 · Q-3 notification 12.8M                시, 실패 시 컬럼 추          통합
                                           ALTER가 INSTANT로 안 잡히면 장시간 락                     가 포기하고 push_
```

delivery_log 만으 로 진행)

```text
DA-     용어사전 전량 등재 (N-15 잔        Vonn     DA-P0-17의 6항목 외 전량 — 목표 달성률            각        13항목 등재 · 각 항     M   SUM-
P1-25   여)                                 · 행동/결과 목표 · 계획된 운동일 ·                 Wave     목에 계산식·제외 조           DOC-1 · CAL
                                           이행/미이행 · 주간 약속 · 내 운동 세트 ·             확정       건·검증 쿼리               -DOC-1 · P
                                           추천 플랜 · 플랜 완주율 ·                                                      USH DOC의
                                           발송/도달/열람/차단 · 조용한 시간대 · 빈                                             용어사전분
                                           도 상한 · 트리거 . 정의 없이 수치를 뽑으면                                            삭제
```

"같은 지표 다른 수치"가 재발한다

```text
DA-     고객 ID 연결성 — GUEST 정       Vonn ·   §4-2. payment_history 9.3%             —        ① GUEST 식별 정      M   신규
P1-26   책 확정 + access_history     Alan     (ONE_DAY_BUY 14,752 + FOOD_BUY                  책 확정(게스트 ID
        NULL 원인 분해                         7,529) · food_order 5.0% · access_hi            발급 vs buyer_t
                                           story 1.4%(10,400건, 원인 미확인).                    ype 컬럼) — 설계
                                           NULL은 "비회원"과 "유실"을 구분하지 못                       까지, 구현은 P2 ②
                                           한다. 출석은 북극성 지표의 원천이라 1.4%                       access_history
                                           의 정체를 모른 채로 둘 수 없다                              NULL 1.4% 원인
```

분해 결과(게스트 출입 / 단말 오류 / 기타 비율)

```text
DA-     데이터 자산화 운영 리듬 ·           Harvey   ① §11-5의 이관 주석을 6개 개발계획에 실             —        6개 문서 이관 주석       S   신규
P1-27   Wave 티켓 이관 반영                      제 반영(P0 기간 내 완료) ② 주간 운영 리듬                     반영 완료 · 주간 리
                                           개설 — 결함 대장(§13) 상태 갱신 · P0/P1                   뷰 정례화 · §13 대
                                           진척 · QA 알림 처리 · 원천↔리포트 대사                       장이 살아 있는 문서
```

로 유지(주 1회 갱신 로그)

<!-- 원문 PDF 41쪽 -->

### 12-3. P2 · 후속 — 지금은 불가능 (12건)

착수 조건이 충족되기 전에는 티켓을 발행하지 않는다. 조건 컬럼이 곧 발행 트리거다.

단

```text
키       제목                       담당       설명                                                        착수 조건 (= 발행 트리거)
```

계

```text
DA-     DW·제품분석·CDP 도구           Vonn     §8-4 (a)SaaS / (b)자체 / (c)하이브리드. 현재 구조가 이미 (c)            예산 승인 + 데이터 국외 이        3단
P2-01   선정                                에 가깝다                                                     전 법무 회신(DA-P0-16) +     계
                                                                                                    팀 역량 판단                 진
```

입

```text
DA-     L3 DW 구축 — 스테이징          Alan     §7-2. dim_user 중심 8테이블. 원천이 정리되기 전에 만들면                   DA-P2-01 완료 + Wave      3단
P2-02   → dim/fact → 마트                   결함을 그대로 복제한다                                              1~6 배포 + D+30 안정화 +     계
```

§7-1 진입 조건 5건 전부 충족

```text
DA-     지표 레이어 (metric as        Vonn ·   지표를 SQL 정의로 코드화하고 용어사전과 1:1 연결. 정의 변경                     DA-P2-02 + DA-P1-25(용   3단
P2-03   code)                    Alan     은 PR 리뷰로만                                                 어사전 전량 등재)              계

DA-     L4 CDP — 세그먼트 원천         Alan     §8-2. 발송 인프라( push_schedule )는 이미 있다. 배치 코드 안             DA-P2-02 + DA-P1-13(상   4단
P2-04   을 DW로 이관                          에 있는 세그먼트 정의를 DW로 옮기는 일                                   한·조용시간 정식화)             계

DA-     결제 도메인 분리 — ord          Alan     §5-5. 권고 (c) 표준 원장 신설 + 원천 유지. payment_history            옵션 (a/b/c) 결정(Vonn +    시
P2-05   er_ledger 신설                      5.65M · 35종 혼재                                            서버 리뷰) + fact_order     점
                                                                                                    착수 시점                   미
```

정

```text
DA-     비회원 GUEST 식별 구현          Alan     DA-P1-26이 확정한 정책의 구현. 일일권 키오스크 UX 영향                      DA-P1-26 정책 확정 + 키오     시
P2-06                                                                                               스크 UX 검토                점
```

미 정

```text
DA-     notification.type 과      Alan     약 150종 채팅방 이름이 이미 저장돼 원본 복원이 불가능하다.                       DA-P2-02                3단
P2-07   거분 처리 (P-3b)                      유형별 집계는 영구 불가 — DW 적재 시 마스킹·제외로만 처리                                               계

DA-     user_inbody 재가동 · 유      Alan     user_inbody 는 JSON blob + 2024-11-22 적재 정지. 재가동           인바디 장비 연동 결정 + 유        시
P2-08   령 테이블 9종 정리 (S-7 ·                은 인바디 장비 연동이 선행. user_workout_alarm (100행)은 유             령 테이블 정리 방침 확정          점
        유형 ⑥)                             지 확정(캘린더 병행 동기화)                                                                  미
```

정

```text
DA-     정식 A/B 인프라               Alan     현재는 자연 대조군( SENT vs BLOCKED(CAP) )으로 대체 중이며               DA-P2-01(도구 선정)         2단
P2-09                                     무작위가 아니라 보조 지표로만 쓴다                                                               계

DA-     user_exercise_metadata   Alan     듀얼 라이트는 한시적 조치다. 오래 두면 이중 진실이 고착된다.                       추천 모듈이 user_exerci      2단
P2-10   폐기 (S-5b) · user_exe              추천 모듈 이관이 선행. S-4는 세트를 값 오브젝트로 취급하는 현                     se_profile 로 이관 완료      계
        rcise_set_history 시계              설계의 재검토
```

열 (S-4)

```text
DA-     Clarity 웹뷰 별도 설치         Jenna    목표 등록 퍼널이 전량 웹뷰라 세션이 분리된다                                 DA-P1-06 결과 + 법무 회신     2단
P2-11   (I-5b)                                                                                                              계

DA-     기존 데이터 위생 일괄             Alan     enum 오염 과거분( COMPLETE / COMPLETED · REFUND / REFUN        DA-P2-02(DW 적재 시 정규     3단
P2-12   (§4-6 잔여)                         DED · "SMALL_COMPANY " ) · zero-date 862건 · device_id 형   화 규칙과 함께 결정)            계
```

식 3종 · sales.type ↔ payment_history.type 불일치 · loc ker_order_id_list varchar 콤마 리스트

<!-- 원문 PDF 42쪽 -->

## 13. 결함 49건 실행 대장

§4-5의 49건을 전건 P0/P1/P2에 배치한 실행 대장이다. 필요한 경우 한 건을 쪼갰다( E-1a / E-1b 형식). P0 배치 판단 기준: §11-3의 G1 (지금도 오염 중) · G2 (법적·보안) · G3 (스키마 선행 정합화) · G4 (전사 정의). 이 표는 살아 있는 문서다 — 주 1회 Harvey가 상태를 갱신 한다(DA-P1-27).

### 13-0. 이 대장을 읽는 법 ★

```text
트랙    열은 누가 티켓을 발행하는가를 뜻한다. 우선순위 정의와 판정 기준 G1 ~ G4 는 §11-3, 티켓 소유권 원칙은 §11-5가 정본이다 —
```

여기서 다시 정의하지 않는다.

```text
표시                  티켓                            누가·언제


P0 · P1 · P2         DA-Pn-xx 신규 발행               DA 트랙 (P0 = Wave 1 착수 전 / P1 = Wave와 병렬 / P2 = 3·4단계 후속)

W                   발행하지 않는다. DA는 검증만             각 Wave 개발 중
```

W 가 왜 필요한가 — E-6(삭제 미동작)·E-7(이전 기록 필터)은 Wave 1이 운동 기록을 개편하면서 어차피 손대는 코드다. 여기에 DA 티켓을 따 로 내면 같은 파일을 두 사람이 건드린다. 그래서 DA는 "이 결함이 Wave 1 완료 시 해소되었는가" 만 검증한다. 전체 목록은 §13-9.

### 13-1. A. 운동 기록 (E, 14건 → 17행)

```text
ID      결함 · 영향                        심각   트랙   담당           WP       재현 방법                         수정 검증 기준


E-1a     access_history_id NOT NULL    높    P0   Alan         DA-       INSERT INTO                  컬럼이 nullable · 출석 없
        (스키마).                         음    G3                P0-11    user_exercise_session         는 세션 INSERT 성공
        영향: 출석 없이는 세션을 만들 수                                            (user_id, ...) VALUES (...)
        없어 외부 운동 기록 자체가 불가                                             — access_history_id 없이 →
        능                                                              오류

E-1b    외부 운동 기록 기능 결합                 높    P1   Alan·Jenna   DA-      활동 탭에서 출석 없이 "기록 시            source='OUTSIDE' 세션
                                       음                      P1-17    작" → 세션 생성 400( NaN 전송)       생성·조회·종료 전 구간 성
```

립

```text
E-2a     started_at 의미 미확정 — 출석        높    P0   Vonn         DA-       SELECT                       정의·clamp·경계 상수가
        시각을 복사해 운동 시간 평균               음    G4                P0-02    AVG(TIMESTAMPDIFF(MINUTE,     문서 3곳에 확정
        111분, 3시간 초과 1,431건.                                           started_at, end_at)) FROM
        영향: 요약 이미지가 대외 노출물                                             user_exercise_session WHERE
        이라 잘못된 숫자가 SNS에 박제                                             end_at IS NOT NULL → 약 111
        된다                                                             분

E-2b     started_at 서버 채우기 구현          높    P1   Alan         DA-      위와 동일                         신규 세션의 운동 시간 중
                                       음                      P1-16                                  앙값이 정상 범위 · 3시간
```

초과 신규 발생 0건 · 과거 행 소급 보정 없음

```text
E-3     detail 진입만 해도 이전 세트가           높    P0   Jenna        DA-      이전 기록 있는 운동 추가 →              같은 시나리오에서 세트 행
        오늘 기록으로 서버 저장                  음    G1                P0-07    detail 진입 → 무입력 뒤로가기          0건 · 수동 적용 경로는 계
        ( detail/index.tsx:267-268 →                                   → user_exercise_set_history   속 저장
         PUT .../set ).                                                에 오늘 행 생성
```

영향: 하지 않은 운동이 기록에 남 는다. 총 세트·총 무게·작성률이 전 부 오염

<!-- 원문 PDF 43쪽 -->

```text
ID     결함 · 영향                         심각   트랙   담당           WP       재현 방법                          수정 검증 기준


E-4    lb 이중 변환 ( detail:100 ) —       높    P0   Jenna        DA-      weight_type='lb' 계정에서 60       3회 재진입 후 값 불변 · 라
       DB는 kg인데                        음    G1                P0-08    입력 → 저장 → 재진입 27.2 →           벨과 값 단위 일치
       weight_type='lb' 면 다시 kg 변                                      재진입 12.3
```

환. 영향: 불러올 때마다 ×0.4536 되 어 사용자 무게가 계속 줄어든다. 표시부도 kg 값에 lbs 라벨

```text
E-5a   round_number 중복 데이터 — 운         중    P0   Alan         DA-      GROUP BY session_id,           위 쿼리 0행 · 스크립트 멱
       동 교체 시 1,2,2 발생, 삭제             간    G3                P0-10    round_number HAVING            등
       API가 -1 감소시켜 충돌.                                                COUNT(*)>1
```

영향: 서버 데이터만으로 순서 복 원 불가

```text
E-5b   uq_session_round + replace      중    P1   Alan         DA-      운동 교체 2회 반복 → 1,2,2 발          UNIQUE 위반 없이 교체
       API                             간                      P1-16    생                              성공 · 서버 데이터만으로
```

순서 복원 가능

```text
E-6    "운동 삭제 후 종료"가 아무것도              중    P1   Jenna        DA-      미완료 운동 있는 상태로 [삭제 후            DELETE 호출 발생 · rem
       삭제 안 함 — DELETE 호출 0건,          간                      P1-16    종료] → 네트워크 탭에 DELETE           oveIncompleteExercises(
       removeIncompleteExercises()                                     호출 0건, is_done=0 행 잔존          ) 실제 호출 · 이전 기록
       호출부 0건.                                                                                        프리필에 미완료 행 미포함
```

영향: is_done=0 잔여가 계속 쌓 이고 이전 기록에도 잡힌다

```text
E-7    이전 기록 조회에                       중    P1   Alan         DA-      삭제·미완료 세션이 있는 계정에서             is_deleted=0 · end_at
       is_deleted · end_at · is_done   간                      P1-16    이전 기록 조회 → 섞여 나옴               IS NOT NULL · status='
       필터 전무 ( dao.ts:314-330 ).                                                                      ACTIVE' · is_done=1 필
       영향: 삭제·미완료·중단 세션이 프                                                                            터 적용
```

리필에 섞인다

```text
E-8    3시간 하드 만료 후 재개 불가 ·             중    P1   Jenna·Alan   DA-      세션 시작 후 3시간 방치 → 앱이            하드 만료 제거 · 6시간 초
       RPE 미수집 · 앱 이탈 세션은              간                      P1-16,   강제 종료 · 재개 불가. SELECT          과 시 비차단 배너 · 12h
       end_at NULL 영구 방치(정리 배                                 DA-      COUNT(*) ... WHERE end_at IS   서버 마감 배치 가동
       치 없음).                                                 P1-19    NULL → 32,241
```

영향: 세션 데이터 품질 전반

```text
E-9    summary 총무게가 MINUTE 운           높    P0   Jenna        DA-      MINUTE 운동 포함 세션에서              summary = complete =
       동까지 합산 ( summary:86-92 ) —      음    G1                P0-09    complete 화면과 summary 화         서버 3값 일치(픽스처 10
       weight × count 에                                                면 총무게 비교 → 불일치                 종)
```

unit·null· is_done 필터 전무. 영향: 20분 러닝이 weight×1200 . MINUTE 포함 세션 2,777건 = 기록 보유 세션의 18.3%(5건 중 1건). complete 화면과 값이 다르다

```text
E-10   타인의 access_history_id 로 세       높    P0   Alan         DA-      A의 JWT + B의                    400 반환 · 회귀 테스트 ·
       션 생성 가능 — 소유자 검증 없음             음    G2                P0-06    access_history_id 로 POST /     과거 오염 건수 실측 기록
       ( service.ts:186-195 ).         (보                              exercise-session → 201
       영향: 현재도 재현 가능한 보안 결             안)
```

함

```text
E-11   exerciseHistoryId! non-null     낮    P1   Jenna        DA-      exerciseHistoryId 가            filter(e =>
       단언 → /history/undefined 호       음                      P1-16    undefined인 운동으로 종료 시도          e.exerciseHistoryId !=
       출                                                               → /history/undefined 요청        null) 선행 · undefined
```

요청 0건

<!-- 원문 PDF 44쪽 -->

```text
ID     결함 · 영향                             심각       트랙    담당            WP           재현 방법                             수정 검증 기준


E-12   order 파라미터 대소문자 불일                  낮        P1    Alan          DA-          클라가 order=asc 전송 → 400            @Transform 적용 · asc /
       치 (클라 asc vs 서버 @IsIn(['            음                            P1-16                                          ASC 양쪽 200
```

ASC','DESC']) ). 영향: 호출 시 400

```text
E-13   프로덕션 디버그 console.log                낮        P1    Jenna         DA-           dashboard:157,160 · _layout:     grep 결과 0건
       잔존 3곳                               음                            P1-16        58


E-14   getSingleMachineId 헬퍼 4개            낮        P1    Jenna         DA-           grep -rn "getSingleMachineId"    정의 1개 · import 전수 치
       파일 중복 정의                            음                            P1-16        CLIENT/ → 4개 정의                   환
```

### 13-2. B. 데이터 희소·구조 (S, 8건 → 9행)

```text
                                                심    트
ID     결함 · 영향                                             담당     WP          재현 방법                                        수정 검증 기준
                                                각    랙


S-1    기록 보유 세션 8.4% — 90일 세션                   높    P1    Vonn   DA-         90일 세션 대비 user_exercise_session_h            정의·계산식 등재 + 주
       180,649건 중 15,189건(12건 중 1               음                 P1-20       istory 1건 이상 보유 세션 비율                        간 추적 고정. 개선 자체
       건).                                                                                                                 는 Wave 1 기능 성과로
       영향: 요약 이미지 V1의 존재 이유가                                                                                               판정
```

흔들린다(LITE 레이아웃으로 방어). Wave 1 기록률 개선이 실질 선행조건

```text
S-2    end_at IS NULL 17.8%(32,241).            중    P1    Alan   DA-         SELECT COUNT(*) FROM                         마감 배치 가동 후
       영향: 6건 중 1건은 운동 시간을 그릴                   간                 P1-19       user_exercise_session WHERE end_at IS        D+30 신규분 결측 5%
       수 없다                                                                   NULL                                         미만(과거분 미보정)

S-3    rpe IS NULL 44.6%(80,508).               낮    P1    Vonn   DA-         위와 동일 컬럼                                     "있을 때만 표시" 규칙
       영향: 운동 강도는 절반이 없다                        음                 P1-19                                                    명문화 · 지표 분모에서
```

제외 규칙 등재

```text
S-4    user_exercise_set_history 에 cr           중    P2    Alan   DA-         DESCRIBE user_exercise_set_history →         의도적 미해소. 2단계
       eated_at 없음 + PUT 전량 교체.                 간                 P2-10       시간 컬럼 없음                                     레벨링 시 재검토
       영향: 세트 단위 시계열 추적 불가                                                                                                 ( 미정 N 신규)

S-5a   user_exercise_profile 신설 + 듀얼            중    P1    Alan   DA-         DESCRIBE user_exercise_metadata →            신규 테이블 가동 · 듀얼
       라이트. 현행 user_exercise_metad              간                 P1-21       PK= user_id 단일, 시간 컬럼 없음. SELECT             라이트 정합성 100% ·
       ata 는 PK= user_id 단일·시간 컬럼                                             COUNT(*) = 23,765(전체 회원의 6.0%), S            active_flag
       없어 이력 불가                                                               ELECT DISTINCT level = 2/5/7(사실상 3단          UNIQUE 동작
```

계 enum)

```text
S-5b   user_exercise_metadata 폐기 (추천            중    P2    Alan   DA-         추천 모듈이 직접 읽는 코드 경로 확인                        추천 모듈 이관 완료 후
       모듈이 직접 읽으므로 즉시 폐기 불가)                    간                 P2-10                                                    읽기 참조 0건

S-6    user 테이블에 키·체중 컬럼 0건 ( %                 중    P1    Alan   DA-         SHOW COLUMNS FROM user LIKE '%height%'       user_body_metric 가
       height% · %weight% 매칭 없음).               간                 P1-21       · '%weight%' → 0행                            동 · weight_kg 항상
       영향: 결과 목표의 진행 지표를 그릴 수                                                                                              kg · 법무 회신 전까지
       없다                                                                                                                  수집 플래그 OFF

S-7    user_inbody 가 JSON blob +                중    P2    Alan   DA-         SELECT MAX(created_at) FROM                  미해소. 어댑터 자리( s
       2024-11-22 적재 정지.                        간                 P2-08       user_inbody → 2024-11-22                     ource='INBODY' )만 확
       영향: SQL 집계 불가 + 최신값 없음                                                                                              보 — 그 사실을 §5-4
```

에 명시 유지

```text
S-8    추천                                       중    P1    Alan   DA-         exercise_recommendation_log 와 user_e         template_id · progr
       ( exercise_recommendation_log ) ↔        간                 P1-18       xercise_session 사이 공통 키 부재                   am_slot_id 채움 · 추
       실제 수행 연결 키 없음.                                                                                                      천 이행률 쿼리 성립
```

영향: "추천대로 했는가"를 DB로 추 적 불가

<!-- 원문 PDF 45쪽 -->

### 13-3. C. 기구·카탈로그 (M, 6건)

```text
                                                    심        트
ID    결함 · 영향                                                       담당          WP       재현 방법                           수정 검증 기준
                                                    각        랙


M-1   기구↔기구 대체 매핑 저장소 없음                            중        P1     Alan        DA-      대체 후보를 담는 테이블이                  machine_substitute 가동 ·
                                                    간                           P1-22    스키마에 없음                         지점 교집합 조회 성립

M-2   CARDIO·STRETCHING에 세부부위 없음 → 자                중        P1     Alan        DA-      슬롯 298건 전부 미커버                  source='RULE_CARDIO' 별
      극 벡터 산출 불가, 대체 커버리지 0%(슬롯 298                 간                           P1-22                                    도 규칙 적용 · 커버리지 > 0 ·
      건 전부 미커버)                                                                                                          카피로 방어("비슷한 유산소
```

기구"). 정교화는 2단계 미정

```text
M-3   FREE_WEIGHT 148개 모델 중 108개가 운동                중        P1     Harvey      DA-       machine × exercise_ma          108종 매핑 보강 또는 대체
      매핑 없음(27.0%만 매핑).                             간                           P1-23    chine LEFT JOIN에서               대상 제외 판정 — 어느 쪽이
      영향: 대체 기능의 진짜 구멍                                                                   FREE_WEIGHT 미매핑 카운              든 판정 근거 기록
```

트

```text
M-4   CABLES는 모델당 21.3개 운동 — 후보 과다 노                낮        P1     Alan        DA-      대체 후보 조회 시                      가중치 조정 후 상위 후보 품
      출                                             음                           P1-22    CABLES에서 과다 노출                  질 검증 · machine_swap_ap
```

ply 의 rank 분포 확인

```text
M-5    gym_machine 은 실물 대수 단위(A기구 5대 = 5            중        P1     Alan        DA-       SELECT COUNT(*) FROM           분석 단위를 machine (모델)
      행). 실물 6,079대 = 모델 1,082종.                    간                           P1-22    gym_machine vs COUNT(DI         로 강제하는 규칙을 §9-1·용
      영향: 대수로 세면 기구 종류 수가 왜곡된다                                                           STINCT machine_id)              어사전에 등재

M-6    exercise_machine 에 status · created_at       낮        P1     Alan        DA-       DESCRIBE                       N:M( machine_body_part )
      없음(복합 PK만) · machine.body_part                음                           P1-22    exercise_machine → 복합           을 정본으로 확정하고
      varchar가 machine_body_part N:M과 병존.                                                PK만                             varchar 컬럼은 읽지 않는 규
      영향: 이력·비활성 개념이 없다                                                                                                  칙 등재. 스키마 변경은 하지
```

않음

```text
(참    QR( unique_code ) 미부착 — CARDIO 1,541          중        P1     Harvey      DA-       SELECT COUNT(*) FROM           실사 결과 + 부착 계획 미정 .
고)    대(98.8%) · FREE_WEIGHT 747대(80.6%).           간                           P1-23    gym_machine WHERE               위 사실을 기능 기획에 반영
      영향: QR 운동 추가 동선이 카디오·프리웨이트                                                         unique_code IS NULL 유형
      에서 사실상 동작하지 않는다                                                                    별
```

### 13-4. D. 시간대·배치 (T, 5건)

심

```text
ID    결함 · 영향                                       트랙            담당       WP           재현 방법                               수정 검증 기준
```

각

```text
T-1   challenge_calendar.start_at 이 KST         높   P0            Alan     DA-P0-05     SELECT id, start_at FROM            신규 round의
      09:00을 가리킨다 — challenge-                  음       G1                              challenge_calendar ORDER BY id        start_at = KST 00:00
      handler.ts:515-516   moment().startOf('                                           DESC LIMIT 5 → UTC 00:00.           = UTC 전일 15:00
      day') 가 TZ 미설정(이 핸들러에 tz.setD                                                     round 219 = 2026-07-20
      efault 없음).                                                                       00:00:00
```

영향: 캘린더가 이 값을 쓰면 매주 9시간 어 긋난다

```text
T-2   pt.dao.ts:230-232 요일은 UTC·시각은             높   P1            Alan     DA-P1-13     KST 00:00~08:59 발송 대상 조회            경로 폐기( pt.yaml:
      KST 혼용.                                   음                                       → 전날 요일로 조회되어 미발송                   39-44   enabled:
      영향: KST 00:00~08:59 알림이 전날 요일로                                                                                        false ) · 신규 경로가 u
      조회되어 미발송                                                                                                              ser_workout_day_patt
```

ern 을 원천으로 동작

<!-- 원문 PDF 46쪽 -->

심

```text
ID     결함 · 영향                                       트랙       담당       WP         재현 방법                              수정 검증 기준
```

각

```text
T-3    스트릭이 서버 로컬 TZ에 의존 — DAO는                 중    P0       Alan     DA-P0-04    TZ=UTC + KST 월 00:30 고정 →         3케이스(월 00:30 / 월
       KST 변환 주차를 만드는데 서비스는                     간       G1                        홈 "N주 연속"이 지난 주 기준                 09:30 / 일 23:30) 값 일
       dayjs() ( user.service.ts:4314-4317 ).                                                                        치 · 수정 후 사용자 수치
       영향: 서버가 UTC면 KST 월요일                                                                                          가 바뀌므로 CS 사전 공
       00:00~08:59에 "이번 주"가 지난 주가 된                                                                                  유 완료
```

다. 홈 "N주 연속"이 이미 틀렸을 수 있다

```text
T-4    getOnGoingChallengeCalendar 가 id 최댓      높    P0       Alan     DA-P0-05   종료된 캘린더를 최신 id로 삽입 →               상태 픽스처 4종에서 진
       값을 반환(상태 조건 없음).                         음       G1                        해당 건 반환                            행 건만 반환 · 캘린더 독
       영향: 잘못된 캘린더 1건이 전 사용자 주 경                                                                                     립 계산 이중 방어 적용
```

계를 오염

```text
T-5    app-server에 @nestjs/schedule 의존성         —    규범       Alan     DA-         grep -rn "@Cron" app-server/      결함이 아니라 확정 사실.
       없음( @Cron 사용처 0건).                                              P0-03(문    → 0건                               위 결론을 §9-1에 유지
       결론: 모든 스케줄 작업은 gymboxx-user-                                    서화)                                           하고 PR 리뷰 체크리스트
       app-batch (Serverless cron)가 유일 선택                                                                            에 삽입
```

### 13-5. E. 푸시·알림 (P, 8건 → 11행)

```text
ID      결함 · 영향                                     심각       트랙      담당           WP      재현 방법                        수정 검증 기준


P-1a    동의 게이트 부재 — sendAppPush( 179개 호             높        P0      Vonn·Alan    DA-      grep -rn "sendAppPush("     인벤토리 완성 · 법무
        출부 중 동의를 보는 곳 2곳(1.1%) ( BATCH/             음        G2                   P0-15   → 179곳, 동의 확인 2곳             의뢰 접수 확인
        challenge-handler.ts:66,105 뿐). 광고성 판       (법
        정 + 인벤토리.                                   적)
```

영향: app_push_agreement=false 50,956명 에게도 발송될 개연

```text
P-1b    동의 게이트 전수 교정 179곳                           높        P1      Alan         DA-     위와 동일                        179곳 전부 게이트 통
                                                    음                             P1-10                                과 또는 예외 등재 · a
                                                    (법                                                                 pp_push_agreement=
                                                    적)                                                                 false 대상 발송 0건
```

(D+7)

```text
P-2     유일한 시각 기반 푸시가 사망 — type='운동                 중        P1      Alan         DA-      SELECT COUNT(*),            버그 수정이 아니라 경
        알림' 누적 12건, 마지막 2025-03-31(약 16             간                             P1-13   MAX(created_at) FROM         로 폐기. 신규 경로로
        개월 전). user_workout_alarm ACTIVE 63                                               notification WHERE           대체 후 ACTIVE 63행/
        행/14명.                                                                            type='운동 알림' → 12            14명 대상 정상 발송
        원인: T-2 + 분 완전일치 + 동의 미확인 3중 결                                                    건 / 2025-03-31               확인
```

함

```text
P-3a     notification.type 신규 오염 차단 — enum          높        P1      Alan         DA-      SELECT DISTINCT type        신규 행의 type 이
        선언에도 채팅방 이름 약 150종이 그대로 저장                  음                             P1-11   FROM notification → 채        enum 값만 · trigg
        ( "강남2호점 퇴근팟" 등). 원천 COMM/                                                        팅방 이름 약 150종                 er_type 저장 · type
        notification.service.ts:44,58,67 .                                                                             기준 집계 금지 명문화
```

영향: 유형별 집계가 영구적으로 불가 + 자유기 재라 PII 위험

```text
P-3b     notification.type 과거분                      높        P2      Alan         DA-     위와 동일                        복원 불가. DW 적재 시
                                                    음                             P2-07                                마스킹·제외(PII 위험
```

포함)

<!-- 원문 PDF 47쪽 -->

```text
ID     결함 · 영향                                  심각    트랙     담당             WP      재현 방법                       수정 검증 기준


P-4     is_read 5중 결함 — ① 배너 직접 탭 시             높     P1     Alan           DA-     트리거별 is_read 비율 조            read_at 기록 · 배너
       read 미호출 ② "모두 읽기"가 한 번에 전부 1            음                           P1-12   회 → 34배 편차                  직접 탭 시 read 호출 ·
       ③ app_push_only=true 면 행 자체가 없음 ④                                                                        지표 정본은 push_o
       type 오염으로 분해 불가 ⑤ read_at 없음.                                                                            pened , is_read 는
       영향: 실측 읽음률 1.58%~53.35%(34배 차                                                                            리포트 배제
```

이) 는 "열람률"이 아니라 "알림함 방문률" 이 다

```text
P-5    실도달 53.4% — 동의율 86.6%인데 OS 권한            중     P1     Jenna·Alan     DA-         SELECT COUNT(*) FROM    NULL 1% 미만 ·
       이 60.1%. system_push_agreement IS NULL   간                           P1-14   user WHERE                  KPI를 "OS 권한 허용
       50,062명(13.1%) 미동기화.                                                         system_push_agreement IS    률"로 재정의 ·
       영향: 도달 가능 203,871명 / 381,526명                                                NULL → 50,062               NULL은 false 취급

P-6    발송 피로 — 30일 1인 최대 249건, 30건 초과           중     P1     Alan           DA-     30일 사용자별 발송 건수 분            일 2 · 주 7 상한 초과
       2,969명, 60건 초과 489명(1인 평균 7.72건/         간                           P1-13   포                           0건 · dedup_key 중
       30일)                                                                                                     복 0건

P-7a   심야 발송 즉시 정지 — 7일 기준 00~05시               높     P0     Alan           DA-     시간대별 발송 건수 집계               D+7 실측 야간 발송 0
       2,536건, 21~23시 16,498건.                  음      G2                   P0-15                               건(승인된 거래성 예외
       영향: 광고성이면 정보통신망법 위반 소지                   (법                                                              제외)
```

적)

```text
P-7b   조용시간 정식 구현 (21:00~08:00 KST 기본)          높     P1     Alan           DA-     위와 동일                       조용시간 차단이
                                                음                           P1-13                                push_delivery_log.
                                                (법                                                              block_reason 에 기록
                                                적)                                                              · 지연 발송 정상 동작

P-8    메가폰 배지 중복·물리 삭제 — 동의 토글 반복               중     P1     Alan           DA-     동의 토글 반복 → 배지 행             중복 방지 가드 ·
       으로 706명·2,155행 중복 적재. 회수는 물리             간                           P1-15   중복 생성                       2,155행 1회 정리 ·
       DELETE(§9 R3 위반). 배지 총량 166,596                                                                          soft delete 전환(원
```

래 2단계 → P1 승격)

### 13-6. F. 계측·인프라 (I, 5건 → 6행)

```text
                                           심    트
ID     결함 · 영향                                       담당             WP      재현 방법                   수정 검증 기준
                                           각    랙


I-1    온보딩 퍼널 계측 사실상 없음 — gbx_             중    P1   Jenna          DA-     Firebase 콘솔에서            onboarding_* 7종 수신 검증 · 퍼널
       step1~3_click 3개가 전부, welcome-      간                        P1-08    welcome-new-member     리포트 1건 산출
       new-member 이후 0건                                                     이후 이벤트 조회 →
```

0건

```text
I-2    목표 등록 퍼널 전량이 웹뷰 — 앱 계측과             높    P1   Jenna·Alan     DA-     웹뷰 구간에서                  goal_wv_* 8종 수신 · flow_id 로 앱
       단절.                                 음                        P1-09   Firebase 이벤트 미          ↔웹 퍼널 조인 쿼리 성립(웹에서 직접
       영향: "왜 등록을 완료하지 않는가"를 영                                              수신                      Firebase 발송, postMessage 위임 금
       영 알 수 없다                                                                                     지)

I-3    analyticsLabel 이 'push_lambda' 로    낮    P1   Alan           DA-     Firebase 콘솔 푸시          트리거별 전송·열람 분해 확인
       고정 ( MSG:146 ) — 전 푸시가 한 덩어리.       음                        P1-07   리포트 → 전체가 한
       기회: trigger_type 으로 바꾸면 한 줄                                          덩어리
```

변경으로 Firebase 콘솔에 트리거별 전 송·열람이 열린다

```text
I-4    AsyncStorage·MMKV 없음 — expo-        낮    P1   Jenna          DA-      grep -rn               결함이 아니라 제약. 튜토리얼이
       secure-store 가 유일 로컬 저장소(직접         음                        P1-02   "SecureStore"           SecureStore 캐시로 설계됨을 확인하
       호출 약 38곳, 래퍼 1개뿐)                                                    CLIENT/ → 약 38곳         고, DA-P1-02 래퍼 도입 시 저장소 접
```

근을 1개 래퍼로 수렴

<!-- 원문 PDF 48쪽 -->

```text
                                                심      트
ID     결함 · 영향                                                   담당             WP      재현 방법              수정 검증 기준
                                                각      랙


I-5a   Clarity 한계 지속 — 방문 URL 전량 빈              중      P1        Jenna          DA-     Clarity 대시보드에서     화면 이름 표시 · custom id 조회 성립
       값 · custom user id 미연결 · 셀피 마스           간                               P1-06   방문 URL 조회 →        · 셀피 화면 리코딩 미포함
       킹.                                                                               22.9만 세션 전부 빈
       신규 요구: 요약 이미지 셀피의 Clarity                                                        값
```

마스킹 강제

```text
I-5b   Clarity 웹뷰 세션 분리                         중      P2        Jenna          DA-     웹뷰 구간 세션이 앱        별도 설치 여부 결정( 미정 N-12)
                                                간                               P2-11   세션과 분리
```

### 13-7. G. 성능 (Q, 3건)

```text
                                  심    트
ID     결함 · 영향                                  담당         WP         재현 방법                        수정 검증 기준
                                  각    랙


Q-1    access_history (user_id,   중    P1       Alan       DA-           EXPLAIN 으로 user_id 단일 인   캘린더 D-4 = 요약이미지 D-13. D+14 실측 후
       created_at) 복합 인덱스         간                        P1-24      덱스 사용 확인 — 평균 51.6행 스        한쪽에서만 결정. 추가 시 온라인 DDL 알고리즘
       부재 (15.1M)                                                     캔 후 필터, 극단 유저 30일            ·소요시간 기록. 미추가 시 LIMIT 가드 유지 근
                                                                      10,790행                      거 기록

Q-2    지점×기구 교차 커버리지              낮    P1       Alan       DA-        해당 쿼리 실행 → 26초               배포 검증 1회만 실행. 상시 모니터링 금지 — 배
       쿼리 26초                     음                        P1-24                                   치가 집계 결과를 테이블/파일로 남기고 리포트
```

는 그것을 읽는다

```text
Q-3    notification 12.8M         중    P1       Alan       DA-        스테이징에서 ALTER ...             DBA 사전 확인 완료. INPLACE 폴백 시 KST
       ALTER가 INSTANT로 안 잡        간                        P1-24      ALGORITHM=INSTANT 시도         04~06시 실행. 실패 시 컬럼 추가를 포기하고 p
       히면 장시간 락                                                                                    ush_delivery_log 만으로 진행(대안 존재)
```

### 13-8. 배치 요약

```text
군                    총 건수                   P0                                               P1     P2                 규범/참고


E 운동 기록              14 (17행)               7 (E-1a·E-2a·E-3·E-4·E-5a·E-9·E-10)              10     0                  —

S 데이터 희소·구조          8 (9행)                 0                                                6      3 (S-4·S-5b·S-7)   —

M 기구·카탈로그            6 (+QR 참고) (7행)        0                                                7      0                  —

T 시간대·배치             5 (5행)                 3 (T-1·T-3·T-4)                                  1      0                  1 (T-5 = 확정 사실)

P 푸시·알림              8 (11행)                2 (P-1a·P-7a)                                    8      1 (P-3b)           —

I 계측·인프라             5 (6행)                 0                                                5      1 (I-5b)           —

Q 성능                 3 (3행)                 0                                                3      0                  —

합계                   49건 (58행)              12행                                              40행    5행                 1행
```

### 13-9. W — Wave 기능 개발로 자연 해결되는 결함 ★

아래 결함은 해당 Wave의 기능을 만들면 함께 사라진다. DA 트랙에서 별도 티켓을 발행하지 않고, Wave 완료 시점에 DA가 검증만 한다. 혼선을 막기 위해 여기 모아 표시한다.

<!-- 원문 PDF 49쪽 -->

해소되는

```text
결함            요약                                            왜 자연 해결인가                         DA의 역할
```

Wave

```text
E-1b          외부 운동 기록 기능 결합                       Wave 1   source='OUTSIDE' 기록은 Wave 1의      스키마(E-1a) 선제 제공 +
                                                            기능 그 자체다                          완료 검증

E-2b          started_at 서버 채우기 구현                 Wave 1   세션 생성 로직을 Wave 1이 다시 쓴다           정의(E-2a) 선제 확정 + 값
```

검증

```text
E-5b          uq_session_round + replace API       Wave 1   순서 관리가 Wave 1 설계에 포함              데이터 정합화(E-5a) 선제 +
```

제약 검증

```text
E-6           "삭제 후 종료"가 아무것도 안 지움                 Wave 1   종료 플로우를 Wave 1이 재작성               잔여 is_done=0 행 0건 검
```

증

```text
E-7           이전 기록 조회 필터 전무                       Wave 1   '불러오기'가 Wave 1 핵심 기능              필터 4종 적용 검증

E-8           3시간 하드 만료·재개 불가                      Wave 1   세션 생명주기 정책을 Wave 1이 재정            마감 배치 가동 검증
```

의

```text
E-11~E-14     코드 위생 4건(non-null 단언·대소문자· cons      Wave 1   같은 파일을 Wave 1이 이미 수정한다            배포 전 grep 검증
```

ole.log ·중복 정의)

```text
S-2 · S-3     end_at NULL 17.8% · rpe NULL 44.6%   Wave 1   세션 마감·RPE 수집 정책이 Wave 1 범         신규 발생률 추이 검증
```

위

```text
S-8           추천 ↔ 실제 수행 연결 키 없음                   Wave 1   template_id · program_slot_id 가   조인 성립 검증
```

Wave 1 산출물

```text
M-1 · M-4 ·   기구 대체 매핑 저장소·후보 과다·실물 단위             Wave 1   기구 대체가 '내 운동 세트'의 기능              매핑 품질·커버리지 검증
```

M-5

```text
P-2           시각 기반 푸시 사망                          Wave 5   예약 발송 인프라를 Wave 5가 신설             구 경로 폐기 확인

P-5 · P-6 ·   실도달률·발송 피로·조용시간                      Wave 5   게이트·상한이 Wave 5 설계에 포함             정책 값 일치 검증
```

P-7b

```text
I-1 · I-2     온보딩 퍼널 계측 공백                         Wave 6   온보딩 화면을 Wave 6이 신설                이벤트 수신 검증
```

운동기록 개발 계획을 세울 때 — 위 W 항목 중 Wave 1 소속 결함이 곧 "운동 기록 기능을 어디까지 뜯어야 하는가"의 목록이다. 각 결함의 재 현 방법·검증 기준은 §13-1~§13-2에 있으므로, 개발 계획은 그 표를 그대로 요구사항으로 옮기면 된다.

P0 17 WP의 구성 — 결함 교정이 10건(DA-P0-02·04·05·06·07·08·09·10·11·15 → 결함 12건 · 12행), 기반 구축이 7건(DA-P0-01 정의

- 03 시간 헬퍼 · 12 BigQuery · 13 레지스트리 · 14 명세 대장 · 16 법무 · 17 용어사전). 즉 P0 = 오염 차단 10 + 기반 7이다.

결함 12건 중 7건(E-3·E-4·E-9·E-10·T-1·T-3·T-4)은 전부 P0이고, 5건(E-1·E-2·E-5·P-1·P-7)은 선행 부분만 P0이며 나머지는 P1으 로 이어진다.

<!-- 원문 PDF 50쪽 -->

## 14. 인프라 구축 항목 — "1~4단계 전체 대응"을 무엇으로 담보하는가

PO 범위 정의 2번("현재 상태가 아니라 로드맵 1~4단계 전체에 대응 가능한 데이터 수집·분석 인프라")에 대한 답이다. 판단 기준은 하나 — 2·3·4단계에서 얹을 것을 지금 얹지는 않되, 그때 가서 지금 만든 것을 뜯어고칠 일이 없어야 한다. 이를 "재작업 0 조건"이라 부르고 §14-3에 서 항목별로 검증한다.

### 14-1. 이벤트를 DB와 조인 가능한 형태로 내리는 경로 ★

문제: logEvent() 가 Firebase Analytics + Braze로 보내지만(§6-1), 이벤트는 그 안에 갇혀 DB와 조인할 수 없다(§2-3 L2). "이 기능 을 쓴 사람이 실제로 결제했는가"를 답할 수 없다는 뜻이다.

```text
 구성 요소    지금 하는 것                                   WP              왜 지금인가


 적재 경로    Firebase Analytics → BigQuery Export 연결   DA-P0-12        연결 시점 이후 데이터만 적재된다. 늦게 켜면 그 구간은 영구 소실

 조인 키     전 이벤트에 user_id 필수 부착                      DA-P1-02        래퍼가 자동 주입하지 않으면 97종 × 8속성에서 반드시 누락된다

 비로그인     anonymous_id 발급 → 로그인 시 병합(identity       DA-P1-02        비회원 결제 9.3%·G오더 5.0%(§4-2)와 같은 구멍을 이벤트 층에
 처리       resolution)                                               서 반복하지 않기 위해

 조인 증명    BigQuery events_* × gymboxx DB user       DA-P0-12, DA-   "가능해졌다"를 선언이 아니라 쿼리로 증명한다
          샘플 분석                                     P1-05

 법무       데이터 국외 이전 판단                              DA-P0-16        리드타임이 길다. 3단계 도구 선정(DA-P2-01)의 선행 조건이기도 하
```

다

주의 Braze 경로는 유지한다. 이미 logEvent 에 연결되어 있고(§8-4 (a)), CDP 후보이기도 하다. BigQuery는 분석용 사본이며 발송 경로를 대체하지 않는다.

### 14-2. 확장성을 담보하는 장치 4종 — 정본 위치와 담당 WP

아래 넷은 2~4단계에서 화면·이벤트·지표가 대거 늘어나도 지금 만든 것을 뜯지 않게 하는 장치다. 각 장치의 내용은 앞 장이 정본이므로 여기서는 어디에 있고 누가 만드는지만 가리킨다.

```text
 장치                무엇을 막나                                                       정본              WP


 이벤트 명명·확장 규       접두 의미 변경·이름 길이 초과(40자)·진입점마다 이벤트 분화 → 택소노미 붕괴                §6-2 · §6-3 ·   DA-P0-14
 칙                                                                              §6-6

 스크린 레지스트리         화면이 늘 때 screen_name 충돌 → 화면 축 분석이 영구 불가(소급 정정 수단 없           §6-7            DA-P0-13
```

음)

```text
 지표 정의 단일화         같은 지표가 문서·리포트마다 다르게 계산되는 것                                   §10-1 · 용어사전    DA-P0-17 · DA-
```

P1-25

```text
 QA 자동화            enum 오염· user_id 결측·이벤트 유실이 아무도 모르게 진행되는 것                   §10-4           DA-P1-04
```

이 문서에서 새로 정하는 확장 규칙 2조 — 위 정본들에 없던 것이라 여기서 확정한다.

```text
 규칙        내용                               왜 필요한가


 프로퍼티는     기존 프로퍼티의 삭제·의미 변경 금              의미를 바꾸면 과거 데이터의 해석이 조용히 달라진다. 알아차렸을 때는 이미 어느 시점부터 뜻이 바
 추가만       지. 바꿔야 하면 새 이름을 만든다              뀌었는지 복원할 수 없다
```

<!-- 원문 PDF 51쪽 -->

```text
규칙           내용                               왜 필요한가


정의에 검증       용어사전 항목마다 계산식 + 제외 조             쿼리가 있으면 3단계 dbt 이식이 재정의가 아니라 복사가 된다. 서술만 남기면 전 지표를 3단계에서
쿼리 병기        건 + 실행 가능한 검증 쿼리                 다시 만들어야 한다 — DA-P0-17·DA-P1-25의 DoD에 검증 쿼리를 넣은 이유다
```

### 14-3. 2~4단계에서 얹을 것 — 재작업 0 조건 ★

단

```text
     얹을 것               그때 필요한 전제             지금 무엇이 그것을 담보하나                               담보 실패 시 재작업
```

계

```text
2    레벨링 — xp_l         과거 행동을 소급 산정할         ① 행동이 user_id ·시각· source 로 원자 단위 보존          이벤트에 user_id 가 없으면 소급 산정 자
단    edger · user_l     수 있어야 XP를 0부터 시       (DA-P0-12·DA-P1-02) ② soft delete로 과거 행동      체가 불가 — 레벨링을 전원 0부터 시작해
계    evel · quest · u   작하지 않는다               이 사라지지 않음 (§9 R3, DA-P1-15) ③ 스냅샷 불           야 한다
     ser_quest                                변 (§9 G1)

2    공유 링크 삽입           공유 대리 지표( share_      summary_image_share_tap 계측 (§6-4 E) + §9      기준선 없이 링크만 넣으면 개선 여부를 영
단    → 공유 성사 측          tap )의 기준선이 있어야       M2("측정 불가능한 것을 KPI로 정의하지 않는다")                영 판정 못 함
계    정                  개선 여부를 판정

3    L3 DW — 스테이        원천이 단일 시간 규율·단        ① KST 단일 헬퍼 (DA-P0-03) ② weight 항상 kg         started_at 의미가 흔들리고(E-2) 총무게
단    징 → dim/fact       일 단위·enum 정합          (§9 R1, DA-P0-08) ③ count 는 unit 종속 (§9 R2,   산식이 틀린(E-9) 상태로 fact_workout
계    → 마트               ·JSON 집계 0이어야 결       DA-P0-09) ④ enum 사전 등록제·드리프트 감지               을 만들면 잘못된 숫자에 정본 지위를 부여
                        함을 복제하지 않는다           (DA-P0-14·DA-P1-04) ⑤ JSON 집계 금지 (§9 J1       하게 된다
```

— 신규 21종 JSON 집계 컬럼 0건)

```text
3    지표 레이어             용어사전 항목마다 실행          DA-P0-17 · DA-P1-25의 DoD가 "계산식 + 제외 조         서술만 있으면 전 지표를 3단계에서 다시
단    (metric as         가능한 검증 쿼리가 있어         건 + 검증 쿼리"                                    정의해야 한다
계    code)              야 이식이 된다

4    L4 CDP 본격화         ① 세그먼트 원료(윈도우         ① §6-5 User Property 4유형 설계 + is_low_vis      동의 상태가 부정확하면 세그먼트가 법적으
단                       상태 User Property) ②   itor_30d 등 (DA-P1-01) ② push_delivery_log =   로 발송 불가한 대상을 포함한다. 발송 인프
계                       발송 결과 정본 ③ 동의         지표 정본, is_read 배제 (DA-P1-12) ③ 동의 게이          라( push_schedule )는 이미 있으므로 4단
                        상태 정합                 트 전수 교정 (DA-P1-10) + OS 권한 동기화 (DA-           계 CDP는 "인프라 신설"이 아니라 "세그
                                              P1-14)                                        먼트 원천을 DW로 옮기는 일"이다

전    화면 증가              screen_name 충돌 없음     스크린 레지스트리 + 미등록 리젝 (DA-P0-13)                 이름이 제각각이면 화면 축 분석이 영구 불
단                                                                                           가 — 소급 정정 수단이 없다
```

계

<!-- 원문 PDF 52쪽 -->

## 15. 역할과 RACI

### 15-1. 팀 구성과 이 트랙에서의 책임 범위

```text
사람          역할       이 트랙에서의 책임 범위                                                                    담당 WP 수


Vonn        PO · 기   정의 최종 결정 — Wave 티켓 이관 반영 · 주 경계· started_at ·지표 정의·이벤트 택소노미·PII 정책. 용어사전 등       P0 7 · P1 7 ·
            획        재. 스크린 레지스트리·이벤트 명세 대장 작성. 게이트 예외 승인 단독                                          P2 2

Harvey      PM       게이트 판정 주체. 결함 대장(§13) 주간 갱신, 운영 리듬, CS 사전 공유 조율, 기구 마스터 데이터 보강(운영 작              P0 1(공동) ·
                     업), 법무 의뢰 주체                                                                     P1 2

Rothy       Design   계측 정의 협업만 — 화면 인벤토리·스크린 레지스트리 검토(개편 Figma 대조). 산출물이 있는 태스크 없음                    검토 2건

Jenna       FE       클라이언트 오염원 수정(E-3·E-4·E-9), logEvent 래퍼, Clarity 태깅·마스킹, 웹뷰·온보딩 계측, OS 권한 동기화     P0 3 · P1 6

Alan        BE       스키마·릴리스 열차의 소유자(DA-P0-11). TZ 헬퍼·TZ 버그 3건, 보안 핫픽스, BigQuery 경로, 푸시 결함 6건, 운      P0 8 · P1 15
                     동기록 잔여 9건, 기구 매핑, 성능 3건. DBA·인프라 역할 겸임                                           · P2 8

(사외) 법      협조       광고성 판정 · 신체정보 동의 항목 · Clarity custom id · 데이터 국외 이전                              회신 3건
```

무

```text
(사내) CS     협조       스트릭 수치 변경 사전 공지(DA-P0-04)                                                        1건
```

### 15-2. 주요 의사결정 RACI

Responsible(실행) · Accountable(최종 책임, 1명) · Consulted(사전 협의) · Informed(사후 통보)

```text
#      의사결정 · 산출물                                 Vonn         Harvey          Rothy   Jenna   Alan    사외


1      주 시작 요일 확정 (DA-P0-01)                      A/R          C               —       I       C       —

2       started_at 의미·채우기 규칙 (DA-P0-02)           A            I               —       C       R/C     —

3      P0 게이트 통과 판정 (§11-4)                       A(예외 승인)     A/R             I       I       C       —

4      스키마 변경· gymboxx-lib 릴리스 열차 (DA-P0-11)      C            I               —       I       A/R     DBA C

5      이벤트 택소노미·명명 규칙 (DA-P0-14·P1-01)            A/R          I               C       C       C       —

6      스크린 레지스트리 (DA-P0-13)                       A/R          C(QA 리젝 운영)     C(검토)   C       I       —

7      이벤트 적재 경로(BigQuery) (DA-P0-12)             A/C          I               —       I       R       법무 C

8      지표 정의·용어사전 등재 (DA-P0-17·P1-25)             A/R          I               —       I       C       —

9      PII·신체정보 수집 판정 (DA-P0-16)                  A/R          I               —       C       C       법무 C

10     광고성 분류·조용시간 정책 (DA-P0-15·P1-13)            A            C               —       I       R       법무 C

11     클라이언트 오염원 수정 (DA-P0-07·08·09)              I            C               —       A/R     C       —

12     보안 핫픽스 (DA-P0-06)                          I            I               —       I       A/R     —

13     온라인 DDL 판정 (Q-1·Q-3, DA-P1-24)             I            I               —       —       A/R     DBA C

14     Wave 티켓 이관 반영 (§11-5)                      C            A/R             I       I       I       —
```

<!-- 원문 PDF 53쪽 -->

```text
#    의사결정 · 산출물                                  Vonn        Harvey         Rothy    Jenna   Alan   사외


15   기구 마스터 데이터 보강 (DA-P1-23)                    C           A/R            —        —       C      트레이너 C

16   결함 대장 상태 갱신 (§13)                           I           A/R            —        C       C      —

17   CS 사전 공유(스트릭 수치 변경)                         I           A/R            —        —       C      CS C

18   DW·CDP 도구 선정 (DA-P2-01)                     A/R         C              —        I       C      법무 C

19   결제 도메인 분리 옵션 (a/b/c) (DA-P2-05)             A           I              —        —       R/C    —

20   GUEST 식별 정책 (DA-P1-26)                      A/R         C              —        I       C      —
```

### 15-3. 에스컬레이션

```text
상황                            처리


P0 WP가 예상 규모를 2배 초과           Harvey → Vonn. 게이트를 늦출지, 범위를 P1로 내릴지를 Vonn이 결정. 임의 축소 금지

법무 회신이 P0 기간 내 도착하지           예상된 상황이다(§11-4). P0는 "의뢰 접수"로 통과, 회신은 Wave 2·5 블로커로 승계(§18)
```

않음

```text
DA WP와 Wave 티켓이 같은 파일         DA WP가 우선. Wave 티켓 담당자가 DA WP 머지를 기다린다(§11-5 소유권 단일)
```

에서 충돌

```text
Alan 1인에 P0 8건이 몰려 병목         §16-5 리스크 R1. 클라 3건(DA-P0-07·08·09)은 Jenna 독립 병렬, 정의 4건은 Vonn 독립 병렬로 설계했으나 잔여
```

병목은 순서 조정으로만 해소

<!-- 원문 PDF 54쪽 -->

## 16. 일정

주의 날짜를 근거 없이 못 박지 않는다. 아래는 소요 기간 추정 + 선후 관계이며, 확정 일자는 착수 후 첫 주 리뷰에서 정한다( <span class='undecided'>미정</span> ). 착수일만 확정 — 2026-07-28.

### 16-1. P0 의존 그래프

[정의 트랙 — Vonn 독립 병렬] DA-P0-01 주 경계 ──┬──────────────────────────▶ DA-P0-17 용어사전 6항목

```text
   DA-P0-02 started_at ┘                          ▲
                       └──────────────────┐                      │
 [시간 규율 트랙 — Alan]                        │        │
```

DA-P0-01 ──▶ DA-P0-03 KST 헬퍼 ──┬──▶ DA-P0-04 스트릭 TZ(T-3) └──▶ DA-P0-05 챌린지 TZ(T-1·T-4) [스키마 트랙 — Alan · 임계경로 <span class='star'>★</span>] DA-P0-10 round 정합화 ──┬──▶ DA-P0-11 lib 4.29.0 + ALTER ──▶ █ Wave 1 착수 가능 DA-P0-02 ───────────────┘ [오염원 즉시 차단 — Jenna 독립 병렬] DA-P0-07 E-3 ｜ DA-P0-08 E-4 ｜ DA-P0-09 E-9 ────────────────▶ DA-P0-17 [보안 — Alan 독립 · 최우선] DA-P0-06 E-10 (선행 없음, D+1 착수) [계측 인프라 트랙] DA-P0-12 BigQuery (독립) ｜ DA-P0-13 레지스트리 ──▶ DA-P0-14 명세 대장 [법무 트랙 — Vonn 독립 · 즉시 발송] DA-P0-15 심야 차단 + 광고성 의뢰 ｜ DA-P0-16 신체정보·PII 의뢰 └─(회신)─▶ Wave 2 · Wave 5 블로커로 승계 (P0 게이트 아님)

임계경로: DA-P0-10 → DA-P0-11 (round 정합화 → lib 4.29.0 + ALTER, S + L). 여기에 DA-P0-02 (started_at 규격이 DTO에 들어감)가 합 류한다. P0 전체 소요는 이 경로가 결정한다.

### 16-2. 주차별 배치 (착수 2026-07-28 기준, 영업일)

주

```text
       구간         배치                                                                       산출
```

차

```text
 W1    D+1 ~      DA-P0-06(보안, 최우선) · DA-P0-01·DA-P0-02(정의) · DA-P0-15·DA-P0-16(법무 의뢰      보안 핫픽스 배포 · 정의 2건 확정 · 법무
       D+5        발송) · DA-P0-07·DA-P0-08(클라 즉시) · DA-P0-10 실측 시작 · DA-P0-12 착수            의뢰 3건 접수 · 야간 발송 정지

 W2    D+6 ~      DA-P0-03(KST 헬퍼) → DA-P0-04·DA-P0-05(TZ 3건) · DA-P0-09(총무게) · DA-P0-10   TZ 결함 3건 해소 · 오염원 3건 전부 차
       D+10       완료 · DA-P0-12 완료 · DA-P0-13 착수                                           단 · BigQuery 조인 증명

 W3    D+11 ~     DA-P0-11(lib 4.29.0 + DDL, 스테이징 → 프로덕션) ★ · DA-P0-13 완료 → DA-P0-14 ·     스키마 열차 출발 · 계측 거버넌스 가동 ·
       D+15       DA-P0-17                                                                 용어사전 6항목

 W4    D+16 ~     P0 게이트 판정(Harvey) → Wave 1 착수 · P1 본격 가동                                 게이트 판정 기록(§16-4)
```

미정 확정 일자: P0 완료 목표일 · Wave 1 착수일 · 각 WP 기한 — 착수 후 첫 주 리뷰에서 확정한다.

### 16-3. P1 배치 원칙 (Wave 1~6과 동시)

날짜가 아니라 트리거로 관리한다. Wave 일정이 아직 확정 전이므로 고정 주차를 부여하지 않는다.

```text
 P1 묶음                 착수 트리거                                                     완료 목표 시점


 계측 실행 인프라             P0 게이트 통과 직후                                               각 Wave의 계측 티켓보다 먼저 — 특히 DA-P1-02는
 A(01~05)                                                                         WR-CL-17 이전


 계측 공백 B(08·09)        DA-P1-01 완료                                                Wave 2(목표 웹뷰)·Wave 6(온보딩) 배포 전
```

<!-- 원문 PDF 55쪽 -->

```text
P1 묶음                 착수 트리거                                                 완료 목표 시점


푸시 C(10~15)           4.30.0 열차 편성 시 · 법무 회신 도착 시                            Wave 5 배포와 동시

운동기록·구조               DA-P0-11 완료 직후                                         Wave 1 배포와 동시
```

D(16~21)

```text
카탈로그·성능·정의            DA-P1-27(운영 리듬)은 P0 기간 내 착수, 나머지는 4.29.x 열차 후 · Q-1    Wave 3 배포 전
E(22~27)              은 캘린더 D+14 실측 후
```

### 16-4. 게이트 판정 기록 (Harvey 갱신)

```text
P0 WP                                   담당          상태                       DoD 충족 근거               판정일


DA-P0-01 ~ DA-P0-17                     —           미정 미착수                    미정                         미정
```

착수 후 이 표를 17행으로 전개해 WP별로 갱신한다. 17행 전부 충족 이 되기 전에는 Wave 1을 시작하지 않는다.

### 16-5. 일정 리스크

```text
#     리스크                       영향                       완화


R1    Alan 1인에 P0 8건 집중 —       임계경로 지연이 곧 Wave          정의 4건(Vonn)·클라 3건(Jenna)을 독립 병렬로 분리 설계 완료. 잔여 병목은 W1
      DBA·인프라 역할까지 겸임           1 지연                     에 DA-P0-06 (S, 독립)을 먼저 빼고 DA-P0-10 실측을 병행해 흡수

R2      DA-P0-11 온라인 DDL이 예상    임계경로 직격                  스테이징에서 알고리즘·소요시간을 먼저 계측하고 그 값으로 프로덕션 창을 잡는다.
      보다 오래 걸림                                           INSTANT 불가 시 KST 04~06시 창 확보

R3    법무 회신 지연                  Wave 2(신체정보)·Wave        P0 DoD를 "의뢰 접수"로 정의해 게이트에서 분리(§11-4). 회신 대기 중에는 신체
                                5(광고성) 블로커               정보 수집 플래그 OFF로 진행

R4    Wave 티켓 이관이 반영되지 않        같은 작업을 두 사람이 함 ·         DA-P1-27을 P0 기간 내 착수로 못 박음. 이관 주석이 6개 문서에 반영될 때까지 해
      아 중복 작업 발생                배포 충돌                    당 Wave 티켓을 Blocked 로 둔다

R5    P0가 길어져 "병렬"이 아니라         PO 정의 위반                 P0는 17건으로 고정. 추가 편입은 Vonn 승인 필요하고, 편입 시 다른 항목을 P1로
      "선행 전부"가 됨                                         내려 총량을 유지한다

R6    결함 49건 전건 소유로 DA 트랙       P1이 끝나지 않음               P1은 Wave와 동시 진행이 전제다. 완료 판정은 각 Wave 배포와 묶어서 한다
      이 비대해짐                                             (§16-3 트리거 방식)
```

<!-- 원문 PDF 56쪽 -->

## 17. 완결성 검증

### 17-1. As-Is 문제 → To-Be 해소 매핑

유형별 (§4-1의 7유형)

```text
유형                 해소 위치                                트랙                                          상태


① 도메인 혼합           §5-5 매핑 딕셔너리 + 원장 → §7-2 f           P2 (DA-P2-05)                               설계 완료, 옵션 결정 대기
저장                 act_order


② SQL 집계 불         §9 J1(신규 금지) · 신규 21종 JSON 집         신규 차단 = 완료 / 기존 = P2(DA-P2-08·12)           신규 차단 완료 / 기존
가 타입               계 컬럼 0건                                                                          ( user_inbody · food_statistics )
```

미해소

```text
③ enum 오염          §6-2-6 사전 등록제 · §9 X1 · §10-4        신규 = P0(DA-P0-14) / 감지 = P1(DA-P1-04) /     신규 차단 P0로 승격
                   드리프트 감지 · §9 M1                      과거분 = P2(DA-P2-07·12)

④ 시간 무결성           §9 C1·C2 단일 헬퍼 + T-1·T-3·T-4 교       P0(DA-P0-03·04·05) / T-2 = P1(DA-P1-13)     Wave 3·4·5 → P0로 당김 ★
```

정

```text
⑤ 단위 혼재            §9 R1(항상 kg)·R2(unit 종속) +           P0(DA-P0-08·09)                             Wave 1/4 → P0로 당김 ★
```

E-4·E-9 교정

```text
⑥ 적재 정지·유          user_workout_alarm 유지 확정 ·           P2(DA-P2-08)                                부분 — 정리 방침 미결
령 테이블              user_inbody 어댑터 자리만


⑦ 키 연결성            §9 S1·R4 제약 강제 + S-8 해소 + fl         P0(DA-P0-11 UNIQUE) / P1(DA-P1-18·09) /     핵심 해소는 P0~P1, 기존
                   ow_id 앱↔웹 조인                         기존 = P2(DA-P2-12)                           ( device_id · sales.type ) 미해소
```

유형 ④·⑤가 P0인 이유: 둘 다 G1 (지금도 오염 중)에 해당한다. 시간·단위가 틀린 채 쌓인 행은 나중에 되살릴 수 없으므로 착수 3주 내에 차단 한다.

결함 대장별 (49건) → §13-8 배치 요약이 정본이다. 군별 P0/P1/P2 건수를 여기에 다시 적지 않는다 — 같은 수치를 두 곳에 두면 반드 시 어긋나기 때문이다. 판정 결과만 말하면 미배치 0건이다.

계층 공백별

```text
문제                             해소 위치                              트랙                              상태


 user_id 결측(§4-2)              GUEST 체계(§5-5) · 이벤트               정책 = P1(DA-P1-26) / 구현 =        설계 → 정책 확정으로 진전. 구현 미착수
                               anonymous_id 병합(§6-5)              P2(DA-P2-06)

행동 계측 공백(§4-3)                 §6 전체 97종 + §6-7 스크린 레지스트          P0(레지스트리·명세) + P1(실행)           거버넌스 P0 확보 · Wave별 배포
```

리

```text
이벤트가 분석 저장소에 없                 ~~§7 DW fact_engagement ~~ →       P0(DA-P0-12)                    ★ 3단계 대기 → P0로 당김. 늦게 켜면 영
음(§2-3 L2)                     BigQuery Export                                                    구 소실이라는 이유

Clarity 한계(§4-4)               §8-5 재배치 + 태깅·custom id·마스킹        P1(DA-P1-06) / 웹뷰 = P2(DA-      미해소 + 마스킹 신규 요구
```

P2-11)

### 17-2. 트레이스 검증

설계가 실제 질문에 끝까지 답하는지, 계층을 관통해 확인한다. ★는 P0 게이트가 성립시키는 부분이다.

<!-- 원문 PDF 57쪽 -->

트레이스 A — "G오더: 누가·언제·무엇을·몇 개 샀나"

계

```text
     답                                                                                                                   트랙
```

층

```text
L1    order_ledger (또는 매핑 뷰): user_id (GUEST 구분)· paid_at · food_id · count · gym_id · amount — 원천에서 이미 4문 모             P2 (DA-
     두 답변 가능(§4-2 실측: 품목·수량·지점 결측 0)                                                                                     P2-05)

L2    gorder_set_view→add→checkout 퍼널로 "사기 전 무엇을 봤나"까지 확장                                                                P1

L3    fact_order (domain='GORDER') × dim_user × dim_date                                                                 P2

L4   "운동 직후 G오더 미구매 고객" 세그먼트 → 쿠폰 푸시 → coupon_used →매출 귀속                                                                P2

판    완료 성립. "누가"의 5%(비회원)는 GUEST 정책 확정(★ DA-P1-26으로 P1 승격) 전까지 공백                                                        —
```

정

트레이스 B — "이번 주 운동 목표를 지킨 사람은 누구인가"

계

```text
     답                                                                                                        트랙
```

층

```text
L1   user_goal (ACTIVE 1건 강제) × user_goal_action (스냅샷 산식) × user_goal_weekly_progress ( gym_value / o         ★ 헬퍼는 P0(DA-P0-03),
     utside_value 분리· capped_value · is_final ) — 주 경계는 kstWeekRange() 단일 헬퍼                                  테이블은 Wave 2

L2   goal_week_achieved ( week_start_on · streak_weeks ) · goal_first_progress_of_week · 서버 goal_progress_    P1
```

finalized

```text
L3   fact_goal_progress × dim_user × dim_date                                                                 P2

L4   "2주 연속 미달성" 세그먼트 → 목표 하향 조정 제안 푸시                                                                        P2

판    완료 L1·L2 성립(Wave 2 배포 시). ★ "주 시작 요일 전사 확정이 선행되지 않으면 L1부터 무너진다"는 리스크가                                    —
정    P0(DA-P0-01)로 해소된다
```

트레이스 C — "푸시를 보냈더니 실제로 왔나"

계

```text
     답                                                                                                                   트랙
```

층

```text
L1   push_delivery_log (정본): 발송·차단·차단사유·판정 스냅샷 6컬럼                                                                       Wave 5

L2   push_opened (정확하나 배너 미탭 시 누락) · push_received (포그라운드만)                                                              P1

L3   fact_push × fact_visit — "T1 수신군 당일 출석률 vs 자연 대조군"                                                                  P2

L4   상한·조용시간· dedup_key 로 피로 제어, 동의 철회율이 브레이크                                                                            ★ P1(DA-
```

P1-13)

```text
판    주의 "열람률"은 구조적으로 정확히 측정 불가(§6-8 ⑤). is_read 는 배제(§9 M1). 후속 행동을 최종 판정으로 삼는다 — §9 M2의                                 —
정    실제 적용 사례. ★ 다만 "발송 자체가 합법인가"는 DA-P0-15(즉시 정지) → DA-P1-10(전수 교정)로 트레이스보다 먼저 답해야 하는
```

질문이 됐다

★ 트레이스 D (신규) — "Wave 1 기능을 쓴 사람이 실제로 더 오래 다니는가"

이번 실행편이 새로 성립시키는 질문이다. 이벤트가 DB와 조인되지 않으면 영원히 답할 수 없는 유형이다.

```text
계층    답                                                                                                  트랙


L1       access_history (방문) × user_exercise_session ( source · template_id ) × user (가입월차)              기존 + DA-P0-11
```

<!-- 원문 PDF 58쪽 -->

```text
계층   답                                                                                 트랙


L2   BigQuery events_* 에서 workout_record_session_end · template_load 등을 user_id 로 추출   ★ DA-P0-12·DA-P1-02

조인   events_*.user_id ↔ gymboxx DB user.id                                             ★ DA-P0-12의 DoD 그 자체

판정   불가 현재 불가 → 완료 P0 완료 시 가능. 이것이 DA-P0-12를 P0에 둔 유일한 이유다                             —
```

<!-- 원문 PDF 59쪽 -->

## 18. 미결 사항

### 18-1. 해소된 것 (누적)

```text
항목                               결론


이벤트 네이밍 체계                       완료 기능네임스페이스_대상_행동 snake_case + 기능별 접두 7종(§6-2·§6-3)

계측 SDK·인프라                       완료 신규 인프라 없음. logEvent() 가 Firebase + Braze 동시 발송(§6-1)

스케줄 실행처                          완료 gymboxx-user-app-batch (Serverless cron) 유일 — app-server에 @nestjs/schedule 없음(T-5)

스트릭 원천                           완료 신설 불필요. consecutive_attendance_week 재사용 + TZ 버그 1건 수정(§5-4·T-3)

R&R                              완료 완전 해소 — §15 RACI 20건으로 5인 책임 범위 확정

★ 이벤트를 DB와 조인할 경로                완료 BigQuery Export로 확정(DA-P0-12). 3단계 DW를 기다리지 않는다

★ 결함 49건의 소유권                    완료 전건 데이터 자산화 트랙 소유. 다른 Wave에 위임하지 않는다(2026-07-27 PO 확정)

★ 선행/병렬의 경계                      완료 P0/P1/P2 + 판정 기준 G1~G4로 확정(§11-3). Wave 1 착수 게이트 = P0 17건
```

### 18-2. 잔존 — 계층 전체에 걸친 큰 결정

```text
#     항목                                 왜 중요한가                                                 결정권자        트랙


1     결제 도메인 분리 옵션 (a/b/c) — 권고          L1 유형 ①의 유일한 해소책이자 fact_order 의 원천                     Vonn +      DA-P2-05
      (c)                                                                                       Alan

2     DW·제품분석·CDP 도구 선정                  3단계 진입의 필수 선행. 예산·데이터 국외 이전(법무)·팀 역량                   Vonn + 법    DA-P2-01
```

무

```text
3     비회원(GUEST) 식별 정책                   NULL이 "비회원"과 "유실"을 구분 못 한다. 일일권 키오스크 UX                Vonn +      정책 P1(DA-P1-26) / 구
                                         영향                                                     Alan        현 P2

4     access_history   user_id NULL      출석은 북극성 지표의 원천이다                                       Vonn +      DA-P1-26
      1.4% 원인 분해                                                                                Alan

5     유령 테이블 9종·정지 통계 테이블 정리             부분 진전: user_workout_alarm (100행) = 유지 확정 · user_i      Alan        DA-P2-08
      방침                                 nbody = 어댑터 자리만


6     Clarity custom id 주입의 개인정보 처       요약 이미지 셀피 마스킹이 신규 필수 요구                                법무          DA-P0-16(의뢰) → DA-
      리방침 반영                                                                                                P1-06
```

### 18-3. 1단계에서 생긴 미결 — 데이터 구조·지표 정의 영향분 ( N- )

번호는 v2와 동일하게 유지한다(다른 문서가 N-1 등으로 참조 중). 트랙 컬럼을 추가했다.

```text
#           항목                                        왜 데이터 문제인가                                결정권자        트랙 · WP


완료          주 시작 요일 전사 확정                             목표·스트릭·챌린지·캘린더가 다른 경계를 쓰면                 Vonn        P0 · DA-P0-01
N-1                                                   모든 주간 지표가 어긋난다

 미정         OUTSIDE 세션의 gym_id NULL 허용 범위             통계 귀속 방식이 갈리고 추천 API fallback에도           Vonn +      P1 · DA-P1-17
N-2                                                   영향                                        Alan
```

<!-- 원문 PDF 60쪽 -->

```text
#      항목                                      왜 데이터 문제인가                           결정권자      트랙 · WP


미정     OUTSIDE 이행 인정 여부 · OUTSIDE_RATIO 상한     실측 0건이라 구조만 만들고 값은 배포 후 결정.          Vonn      배포 후
N-3    값                                       환경변수/Remote Config로 재배포 없이 조정

미정     자동 마감 세션 식별 컬럼 ( rpe IS NULL AND        지표에서 "정상 완료"와 구분해야 한다                Alan      P1 · DA-P1-19
N-4    end_at IS NOT NULL 로 충분한가)


완료      started_at 의미 전환 경계                    시계열 지표에 구조적 단절. 용어사전 등재 + G          Vonn +    P0 · DA-P0-02·17
N-5                                            ROUP BY source 강제                    Alan

미정      access_history 복합 인덱스 (15M 온라인 DDL)    캘린더·요약이미지 공통. 한쪽에서만 결정               Alan +    P1 · DA-P1-24
N-6                                                                                 DBA

미정      notification ALTER의 INSTANT 가능 여부      불가 시 컬럼 추가 포기하고 push_delivery_       DBA       P1 · DA-P1-24
N-7    (12.8M)                                 log 만으로 진행


미정     보존 기간 — push_delivery_log 90일 / push_   개인정보 보존기간 정책과 정합. 신체정보는 동            Vonn·법    P0 의뢰(DA-P0-16) →
N-8    schedule 30일 / notification 24개월 / 신체   의문에 항목 자체가 없다                        무         회신 후
```

정보

```text
미정     광고성 판정 — COMEBACK 분류, 거래성 푸시가 a         광고성이면 모수가 39.9%로 축소. 법 위반 여부         법무        P0 의뢰(DA-P0-15) →
N-9    pp_push_agreement 를 무시해도 되는가            가 갈린다                                          P1(DA-P1-10)

미정      machine_substitute.source enum 확장 승인   반려 시 similarity IS NULL 을 암묵 식별자로    Alan      P1 · DA-P1-22
N-10                                           써야 한다(비권장)

미정      user_exercise_metadata 폐기 시점           듀얼 라이트는 한시적. 오래 두면 이중 진실이 고          Alan      P2 · DA-P2-10
N-11                                           착

미정     Clarity 웹뷰 별도 설치 + 요약 이미지 화면 마스킹        목표 등록 퍼널이 전량 웹뷰라 세션이 분리된다            Vonn·법    마스킹 P1(DA-P1-06) /
N-12                                                                                무         웹뷰 P2(DA-P2-11)

미정      device_tier 유저 속성 승격                   저사양 성능 분석의 전제                        Jenna +   P1 · DA-P1-01
N-13                                                                                Vonn

미정     MySQL CHECK 제약 사용 여부 ( source ↔ acc     무결성 강제 수준. 애플리케이션 레벨로 시작             Alan +    P0 · DA-P0-11
N-14   ess_history_id 정합)                                                           DBA

미정     용어사전 등재 일괄                              정의 없이 수치를 뽑으면 "같은 지표 다른 수            Vonn      P0 6항목(DA-P0-17) +
N-15                                           치"가 재발                                         P1 잔여(DA-P1-25)

미정     2-pass 순서 재부여 알고리즘 공용화 여부               운동기록 history와 운동세트 template          Alan      P1 · DA-P1-16
N-16                                           item이 동일 로직(§5-3 ⑧)
```

### 18-4. ★ 이번 실행편에서 새로 생긴 미결 ( D- )

```text
#      항목                   왜 중요한가                                                            결정권자       기한


미정     스크린 레지스트리 문          20_Areas/gymboxx/UserApp/ 하위가 유력하나, 개편 후 화면이 늘면 UserApp Index와    Vonn       DA-P0-13
D-1    서 경로 확정              의 역할 경계가 애매해진다. screen_name 단일 원천의 위치가 흔들리면 QA 리젝 규칙이                        착수 전
```

성립하지 않는다

```text
미정     BigQuery 비용·보존       무료 티어(일 100만 이벤트) 대비 현재 볼륨 추정이 없다. 초과 시 과금 구조와 보존 기간              Vonn       DA-P0-12
D-2    기간                   (장기 보관 vs 90일)을 정해야 한다                                                       DoD

미정     §5-2 규칙 1 정밀화        DA-P0-11이 규칙 1을 "ALTER는 1회, CREATE는 후속 마이너 합류 가능"으로 정밀화했          Vonn +     P0 W3
D-3    반영                   다. §5-2 본문에 반영해야 하며, 반영 전까지 두 해석이 병존한다                            Alan

미정     "기록 보유 세션 8.4%       S-1은 요약 이미지 V1의 존재 이유를 흔든다. 몇 %가 되면 성공인가가 정의되지 않았다.               Vonn       DA-P1-20
D-4    개선"의 목표치             정의 없이는 Wave 1 성과를 판정할 수 없다
```

<!-- 원문 PDF 61쪽 -->

```text
#     항목             왜 중요한가                                                           결정권자     기한


미정    P1 완료 판정 시점    P1은 Wave와 동시 진행이라 "언제 끝났다"고 말할 기준이 없다. Wave 배포와 묶는 방식            Harvey   P0 게이트
D-5                  (§16-3)을 채택했으나, Wave 일정이 미확정이라 실효성 검증이 필요하다                               판정 시

미정    거래성 푸시 예외 목록   DA-P0-15가 야간 발송을 정지하되 "거래성·CS 예외"를 허용한다. 예외 목록이 없으면 정            Vonn +   DA-P0-15
D-6                  지가 서비스 장애가 된다                                                    Harvey   착수 전

미정    전담 데이터 인력 부재   Alan 1인이 BE·DBA·인프라·데이터를 겸한다(§15-1). P1 15건 + P2 8건은 이 구성으로      Vonn     3단계 진입
D-7                  소화 가능한 양이 아닐 수 있다. 3단계 DW 착수 전에는 반드시 결론이 필요하다                             전

미정    과거 데이터 소급 보정   E-2( started_at )·E-3(허위 세트)·P-8(배지 중복)은 과거 행이 이미 오염돼 있다. E-2는   Vonn     P0 W2
D-8   범위             "보정하지 않음"이 확정됐으나 나머지는 미정이다. 보정 여부에 따라 모든 과거 지표의 해
```

석이 달라진다

<!-- 원문 PDF 62쪽 -->

## 19. 출처

PO 확정 근거 (2026-07-27) - PO 확정 사항 — 데이터 자산화의 병렬 트랙 승격 · 업무 범위 3항 · 결함 49건 전건 DA 트랙 처리 · Design(Rothy) 계측 정의 협업 한정 · 착수일 2026-07-28 (vonn, 2026-07-27) - 실행 대장·WP 분해의 1차 근거는 본 문서 §4-5(결함 49건) · §5(To-Be L1) · §6(택소노미 97종) · §9(운영 원칙 14조) · §10(거버넌스)

1단계 확정 산출물 (본 문서의 1차 근거) - Wave 1 공통 데이터모델 — 스키마 정본 - 운동 기록 개발계획 · 내 운동 세트·추천 플랜 개발계 획 · 운동 목표 개발계획 · 캘린더 개발계획 · 요약 이미지 개발계획 · 푸시 알림 개발계획 · 코치마크·튜토리얼 개발계획 → 주의 §11-5의 이관 대상 티켓이 이 7개 문서에 반영되어야 한다(DA-P1-27) - 1단계 상세기획 준비계획

DB 실측 - 본문 수치는 프로덕션 read-only 레플리카( mysql-gymboxx ) 2026-07-19 / 2026-07-26 조회. 재현 쿼리는 각 개발계획 본문 에 병기 - 2026-07-19 조회: DESCRIBE payment_history · food_order , 최근 30일 user_id 결측률 4건, user 인구통계 결측률, Clarity 대시 보드 라이브 5건 - 운동·기구 카탈로그 실측 (2026-07-26) - 신규 코호트 출석빈도-잔존 임계값 분석 주의 검수 전 — 주 2회 6주 지속 시 잔존 70.9%, 주 3회 이후 한계수익 체감 - gymboxx_db · DB 활용 가이드 · 지표_테이블맵 · DB 분석 업무방식

현행 기능 정본 (mechanics) - 운동 기록 시스템 · 화면 코드 대조 · 배지 시스템 · 챌린지 시스템 - UserApp Index · IA 개요 — 스크린 레지스트리 원천(DA-P0-13)

아키텍처·코드 온톨로지 - 시스템 온톨로지 개요 · 서비스 상호작용 그래프 · gymboxx 데이터 백본(lib 버전 스큐) · 기술 아키텍처 개요 (UTC 타임존 함정) - 코드 기준 — app-server main(2026-07-21) / supplies-apps production(2026-07-23) / gymboxx-lib 4.28.7 / batch lib 4.28.5 / HQ·branch-admin 4.28.5 / pass-server 3.6.1 / messaging-lambda 미정

상위·계승 - 짐박스 하반기 목표 달성 기획안(Habit OS) · 2026H2 로드맵 · 2026-roadmap - 용어사전 G섹션(북극성 = 주간 방문 횟수, 외부 기록 미포함) · 운동 효과 근거 자료집 - 운동하는 재미 기획안 부록 B·C 주의 검수 전 — 이벤트 택소노미·DB 설계의 최초 문제 제기 - 이벤트 설계 규칙(§6-2·§6-5·§6-6·§10-2): 「이벤트 택소노미 설계 가이드」(event_taxonomy_design.pdf) — Event/User Property 2층 · 경제성 원칙 · entry_point · 타입 규칙 · 명세 6단계 게이트
