# 17. 부록 — 테이블·컬럼 변경 명세와 개체 관계도 작성 근거

> [전체 목차](README.md) · [통합 원문](../DB_구조_업그레이드_방안.md)
>
> 2026-09-03 갱신 — `personal_record_type` 명세 삭제(참조 테이블 → `record_kind` enum) · 이력 테이블 명세 교체 · `measure_type` → 플래그 3종 · `weight_unit`·`weight_kg` 신설 취소 · `performed_at` → `done_at` · 근거: [최고 기록 종류 enum 변경 명세](최고기록_종류_enum_변경_명세.md)

테이블·컬럼 단위 변경 명세와 개체 관계도 작성 근거

## 17-1. 한 장 요약

|순위<br>#|대상 테이블|무엇을 하는가|기대효과|착수 전 확인|
|---|---|---|---|---|
|1<br>1|`exercise_function` →<br>`exercise_effect`<br>·<br>`exercise_recommend_tag`|성격 태그를 효과 축·추천용 두 테이블로 분리·근력<br>`STRENGTH`·순발력<br>`PLYOMETRIC` 값 추가·주<br>효과 구분·상태·시각 컬럼 신설|근력 판정이 하나<br>로 확정·효과 축<br>조건이 DB 제약으<br>로 강제|앱 코드 참조 지점 전수<br>조사(유일한 쿼리 비호환<br>항목)|
|2<br>7|`exercise_body_part`·<br>`exercise_body_part_detail`|부분 고유 제약 추가·세부부위 매핑 대리키 전환|부위 이중 계상 차<br>단·정정 이력 보<br>존|기본키 해제 시 외래키 지<br>지 인덱스 동시 교체|
|3<br>2·3|`body_part`·<br>`exercise`|축 구분 컬럼<br>`axis` 추가·유산소 강도 컬럼<br>`cardio_intensity` 신설|새 부위 추가 가능<br>·유산소 시간 목<br>표의 환산 계수 확<br>보|없음(각각 명령 1~2건)|
|4<br>9·<br>10·<br>11|`user_exercise_set_history`|단위·환산 무게·대리키·수행 시각·세트 강도를 한<br>작업으로 추가|랭킹 성립·세트간 휴식 분석·세트 후반 품질 분석|30만 행 테이블·잠금 시간 산정·세트 강도 입력<br>수요 의견 취합(화면 한<br>정)|
|5<br>4|`exercise`|측정 방식 플래그<br>`has_duration`·<br>`has_reps` 신설<br>(`measure_type` 신설 취소)|세트 데이터 단독<br>해석·오염 입력<br>차단·성립 조건을<br>AND 로 표현|`unit` 기준 백필의 트레<br>이너 검수(`chk_measure`<br>CHECK 는 그 뒤·보류)|
|6<br>12|`user_personal_record_history`<br>(1개만 신설)|최고 기록 이력 테이블 신설·기록 종류는<br>`record_kind` enum<br>(참조 테이블 신설 취소)|기간 내 최고 기록<br>달성 수 산출·랭킹<br>조회 경량화|4 완료 필수(9는 소멸·10<br>은 완료)·초기 적재 시점|
|7<br>5·6|`exercise`·<br>`exercise_body_part_detail`|장비 분류 12종 병행 컬럼·부위 기여도 컬럼 추가|지점별 가능 운동<br>판정·부위 목표<br>단위 일치|소도구 42종 재배치 판례<br>·부하율 변경 시 기여도<br>재산출 절차|
|8<br>8|`exercise`|동작 양식<br>`movement_pattern`을 정식 분류 축으<br>로 선언|이완·순발력 식별<br>근거 확보|없음(스키마 변경 없음)|

## 17-2. 신설 테이블 3종 — 구조 정의

### 가. **`exercise_effect`** — 운동 효과 축 (계산용)

|컬럼|자료형|제약|설명|
|---|---|---|---|
|`id`|`int unsigned`|기본키·자동 증가|대리키|
|`exercise_id`|`int`|외래키 →<br>`exercise.id`·NOT<br>NULL|대상 운동|
|`effect_tag`|`enum('STRENGTH','ENDURANCE','MOBILITY','BALANCE','PLYOMETRIC')`|NOT NULL|근력·지구력·이완·균형·순<br>발력|
|`is_primary`|`tinyint(1)`|NOT NULL·기본값 0|주 효과 1개 + 부가 효과<br>여러 개|
|`status`|`enum('ACTIVE','INACTIVE')`|NOT NULL·기본값<br>`ACTIVE`|태그 해제를 비활성 처리<br>로|
|`active_key`|생성 열|`status='ACTIVE'`면 0,그 외<br>`id`|부분 고유 제약용|

|컬럼|자료형|제약|설명|
|---|---|---|---|
|`created_at`|`timestamp`|NOT NULL·기본값 현재 시각|부여 시각|
|`updated_at`|`timestamp`|NOT NULL·갱신 시 현재 시각|상태 변경 시각|

고유 제약 — `UNIQUE(exercise_id, effect_tag, active_key)` · 사용 중 1행 + 비활성 이력 여러 행을 동시에 허용 · 예상 행수 약 290행

### 나. **`exercise_recommend_tag`** — 추천용 태그

|컬럼|자료형|제약|설명|
|---|---|---|---|
|`id`|`int unsigned`|기본키·자동 증가|대리키|
|`exercise_id`|`int`|외래키 →<br>`exercise.id`·NOT NULL|대상 운동|
|`tag`|`enum('FAT_LOSS','RECOVERY')`|NOT NULL|감량(회원 목적) ·회복(운동 용도)|
|`status`|`enum('ACTIVE','INACTIVE')`|NOT NULL·기본값<br>`ACTIVE`|해제를 비활성 처리로|
|`active_key`|생성 열|위와 동일|부분 고유 제약용|
|`created_at`·<br>`updated_at`|`timestamp`|NOT NULL|부여·변경 시각|

- `is_primary` 가 없는 것이 효과 축 테이블과의 유일한 구조 차이 · 감량·회복에는 주 효과·부가 개념이 없음 · 예상 행수 24행

### 다. **`user_personal_record_history`** — 개인 최고 기록 이력

**`personal_record_type` 참조 테이블은 신설하지 않는다(2026-09-03).** 기록 종류는 이력 테이블의 `record_kind` enum 이며, 표기명 · 단위 · 정렬 순서 · 유효 범위는 서버 상수가 단일 출처다([12](12_개인_최고_기록_이력.md)).

|컬럼|자료형|제약|설명|
|---|---|---|---|
|`id`|`bigint unsigned`|기본키·자동 증가|대리키|
|`user_id`|`int unsigned`|외래키 →<br>`user.id`·NOT NULL|회원|
|`exercise_id`|`int`|외래키 →<br>`exercise.id`·NOT NULL|종목|
|`record_kind`|`enum('MAX_WEIGHT','MAX_REPS','MAX_SET_VOLUME','MAX_DURATION')`|NOT NULL|기록 종류·표기명·단위·유효 범위는 서버 상수가 규정|
|`record_value`|`decimal(12,4)`|NOT NULL|기록 값(숫자 1개) ·단위는 종류가 규정|

|컬럼|자료형|제약|설명|
|---|---|---|---|
|`weight`|`decimal(10,7)`|NULL 허용|근거 세트의 중량(kg)·`weight_kg` 에서 개칭(세트 무게가 이미 kg 고정이라 환산 컬럼이라는 이름이 사실과 다름)|
|`reps`|`int unsigned`|NULL 허용|근거 세트의 횟수|
|`duration_second`|`int unsigned`|NULL 허용|근거 세트의 수행 시간(초)·계획 문서에 없던 신설·`MAX_DURATION` 의 근거를 남길 자리|
|`source_set_id`|`int unsigned`|외래키 →<br>`user_exercise_set_history.id`·NULL 허용|근거 세트 참조·**세트 대리키가 이미 있으므로 초기 적재분도 채운다**|
|`achieved_at`|`timestamp`|NOT NULL|달성 시각|
|`is_approximate`|`tinyint(1)`|NOT NULL·기본값 0|초기 적재분의 근사 시각 표시|
|`is_current`|`tinyint(1)`|NOT NULL·기본값 1|현재 최고값 여부|
|`created_at`|`timestamp`|NOT NULL·기본값<br>`CURRENT_TIMESTAMP`|적재 시각|
|~~`current_key`~~|—|—|**보류(2026-09-03)**—현재값 1행을 DB 로 강제하는 부분 고유 제약을 이번 범위에서 넣지 않는다·`is_current` 만 두고 불변식은 서버 책임·넣을 때는 `tinyint` 생성 열 `IF(is_current = 1, 1, NULL)` + `UNIQUE(user_id, exercise_id, record_kind, current_key)` 형태를 쓴다|

인덱스 — `KEY (user_id, achieved_at)` 이력·기간 조회용 · `KEY (exercise_id, record_kind, is_current, record_value)` 랭킹용. `current_key` 를 나중에 넣을 때 랭킹 인덱스도 `current_key` 판으로 교체한다.

갱신은 기존 행 수정이 아니라 행 추가 · 이전 행의 `is_current` 를 0으로 내린 뒤 새 행을 넣는다. 🔴 이 순서를 강제하는 DB 제약이 없으므로(위 `current_key` 보류) 어기면 조용히 현재값이 2행이 된다 — 서버 책임이며 주기 감사 쿼리가 유일한 검출 수단이다.

`user.id` · `exercise.id` · `user_exercise_set_history.id` 의 실제 타입에 맞춰 위 자료형을 최종 확인해야 한다

## 17-3. 기존 테이블 변경 — 컬럼 추가·수정·제거

|테이블|구분|컬럼|자료형·값|근거|
|---|---|---|---|---|
|`body_part`(8행)|추가|`axis`|`enum('MUSCLE','MODALITY') NOT NULL`—근육 부위 6종<br>`MUSCLE`·유산소·스트레칭 2종<br>`MODALITY`|§2|
|`body_part`|유지|`part`|`varchar(30)`—값 8종 그대로·테이블명 변경은 후속(외래키 5개)|§2|
|`exercise`(273행)|추가|`cardio_intensity`|`enum('MODERATE','VIGOROUS') NULL`—유산소 주 효과 종목만<br>필수|§3|
|`exercise`|추가|`has_duration`·<br>`has_reps`|`tinyint(1) NOT NULL DEFAULT 0` 각각—`has_weight`(기존)와<br>합쳐 플래그 3종·**`measure_type` enum 신설은 취소**(단일값으로는<br>"무게+시간" 조합과 AND 성립 조건을 표현 못 함)|§4|
|`exercise`|추가<br>(보류)|`chk_measure` CHECK|`has_weight + has_duration + has_reps >= 1`—셋 다 0인 종목<br>차단·enum 이 `NOT NULL` 단일값으로 보장했던 것을 대체·**보류<br>(2026-09-03)**—백필·검수 중 값 수정이 제약에 막히므로 검수 완료 후<br>별도 마이그레이션|§4|
|`exercise`|추가|`equipment_type`|`enum(12`종`)`—구 컬럼과 병행 생성|§5|
|`exercise`|제거<br>(후<br>속)|`type`|`varchar(30)` 현행 6종—병행 대조 검증 후 폐기|§5|
|`exercise`|유지|`fatigue_level`·<br>`difficulty_level`|`float`—강도 컬럼과 독립 운영·추천 알고리즘 전용|§3|
|`exercise`|유지·<br>선언|`movement_pattern`|`enum(8`종`)` 그대로·스키마 변경 없이 정식 축으로 선언|§8|
|`exercise_body_part`(376행)|추가|`active_key` + 고유 제약|생성 열 +<br>`UNIQUE(exercise_id, body_part_id, active_key)`|§7|
|`exercise_body_part_detail`(514행)|추가|`contribution`|`enum('DIRECT','ASSIST') NOT NULL`—상대 기준(최댓값의<br>60% 이상)일괄 부여|§6|
|`exercise_body_part_detail`|추가·<br>수정|`id` 대리키|자연키 복합 기본키를 대리키로 이관 + 부분 고유 제약|§7|
|`exercise_body_part_detail`|유지|`load_ratio`|`float` 원값 보존—기여도 사후 재산출·3단계 척도 전환의 근거|§6|
|`user_exercise_session_history`<br>(136,087행)|유지|`weight_type`|`enum('kg','lb')` 원값 보존·값을 세트 행으로 복사|§9|
|`user_exercise_set_history`|추가·|`id` 대리키|기본키를 대리키로 이관·기존 자연키 조합은 고유 제약으로 유지·전|§10|
|(301,572행)|수정||건 부여||
|`user_exercise_set_history`|~~추가~~<br>**취소**|~~`weight_unit`~~|**신설하지 않음(2026-09-03)**—`weight` 를 kg 고정으로 확정해<br>세트 행에 단위 컬럼을 두지 않는다|§9|

|테이블|구분|컬럼|자료형·값|근거|
|---|---|---|---|---|
|`user_exercise_set_history`|~~추가~~<br>**취소**|~~`weight_kg`~~|**신설하지 않음(2026-09-03)**—`weight` 자체가 이미 kg 이라 환산<br>열이 중복·입력 경로에서 kg 으로 환산한 값만 저장한다|§9|
|`user_exercise_set_history`|추가|`duration_second`|`int unsigned NULL`—수행 시간(초) ·시간 측정 종목만·**반영 완료**<br>·과거 행은 `count` 의 초값을 계수 없이 이관|§4|
|`user_exercise_set_history`|추가|`done_at`|`timestamp NULL`—세트 수행 시각·신규 기록만 채움·**반영 완료**<br>·계획 문서의 `performed_at` 에서 개칭|§10|
|`user_exercise_set_history`|추가|`created_at`·|`timestamp`—서버 기준 저장·수정 시각|§10|
|||`updated_at`|||
|`user_exercise_set_history`|추가<br>(보류)|`rpe`|`tinyint unsigned NULL` 1~10—세션과 동일한 자각 강도 척도·<br>**보류(2026-09-03)**·필요해질 때 단독 마이그레이션|§11|
|`exercise_function`(87행)|제거|테이블 전체|두 테이블로 이관 후 삭제·백업 테이블은 유지|§1|

컬럼 제거는 2건뿐이며 둘 다 즉시 삭제가 아님 — `exercise.type` 은 병행 대조 검증 후, `exercise_function` 은 앱 코드 전환 확인 후 · 그 외 변경은 전부 추가이므로 되돌리기가 쉬움

## 17-4. 연결 구조 — 어떤 컬럼끼리 무엇을 위해 연결되는가

### 가. 외래키 연결 (현행 유지)

|자식·컬럼|부모·컬럼|무엇을 위한 연결|
|---|---|---|
|`body_part_detail.body_part_id`|`body_part.id`|세부부위 21종을 상위 부위 8종에 소속|
|`exercise_body_part.exercise_id`|`exercise.id`|운동에 부위 라벨 부여|
|`exercise_body_part.body_part_id`|`body_part.id`|부위 라벨 사전 참조·<br>**`axis='MUSCLE'`** 조<br>건으로 부위 집계 필터|
|`exercise_body_part_detail.exercise_id`|`exercise.id`|운동에 세부부위 부여|
|`exercise_body_part_detail.body_part_detail_id`|`body_part_detail.id`|세부부위 사전 참조|
|`user_exercise_session.user_id`|`user.id`|세션의 주인·랭킹 모집단·성별·연령 결합점|
|`user_exercise_session.gym_id`|`gym.id`|지점별 집계|
|`user_exercise_session.access_history_id`|`access_history.id`|방문 목표 계산의 원천(출입 1건 = 세션 1건)|
|`user_exercise_session_history.user_exercise_session_id`|`user_exercise_session.id`|세션에서 수행한 운동 1건|
|`user_exercise_session_history.exercise_id`|`exercise.id`|수행 종목·모든 분류 축이 여기서 기록에 연<br>결|
|`user_exercise_session_history.machine_id`|`machine.id`|기구 프리필·지점 기구 매칭|
|`user_exercise_set_history.user_exercise_session_history_id`|`user_exercise_session_history.id`|운동 1건의 세트들|

### 나. 외래키 연결 (신설)

|자식·컬럼|부모·컬럼|무엇을 위한 연결|
|---|---|---|
|`exercise_effect.exercise_id`|`exercise.id`|운동 효과 축 부여·목표 달성률·랭킹·리포트 계산의 진입점|
|`exercise_recommend_tag.exercise_id`|`exercise.id`|추천용 태그 부여·계산 경로는 이 테이블을 읽지 않음|
|`user_personal_record_history.user_id`|`user.id`|회원별 최고 기록|
|`user_personal_record_history.exercise_id`|`exercise.id`|종목별 최고 기록|
|`user_personal_record_history.source_set_id`|`user_exercise_set_history.id`|근거 세트 참조—오염 기록의 개별 무효화와 기준 변경 후 재산출·<br>세트 대리키(§10)가 전제이므로 강제 순서 10 → 12|

### 다. 외래키가 아닌 논리 연결 — 값 대조로만 성립

|연결|방향|무엇을 위한 것인가|왜 외래키가 아닌가|
|---|---|---|---|
|`user_personal_record_history.record_kind` ↔<br>`exercise.has_weight`·<br>`has_duration`·<br>`has_reps`|값 대조|유산소 종목에 최고 중량<br>기록이 생기지 않게 막음|CHECK 제약은 같은 행만 참조하므로 이력 테이블에서<br>`exercise`<br>플래그를 볼 수 없음·서버 검증과 주기 감사 쿼리로 강제·**참조 테이블 안에서도<br>동일한 한계였음**(외래키만으로는 성립 여부를 강제 못 함)|
|`user_exercise_session_history.weight_type` → 표시 단위 역환산|조회 시점 계수|파운드 선호 회원에게 lb<br>로 표시|저장값은 항상 kg·`weight_type`<br>은 표시 단위 선호이지 저장값의 단위가 아님·종전의 세트 행<br>`weight_unit`<br>복사는 취소됨(2026-09-03)|
|`body_part.axis` →<br>`exercise_body_part` 집계 조건|필터|유산소 13종·스트레칭 7<br>종을 부위 운동량에서 제<br>외|조건이지 참조가 아님|
|`exercise_effect.is_primary` → 목표 판정|필터|주 효과만 세는 목표(유산<br>소 시간·균형 세션)의 판정|조건이지 참조가 아님|
|`exercise.cardio_intensity` → 유산소 시간 환산|계수|중강도 시간 + 고강도 시간 × 2 = 주 150분|계수 조회이지 참조가 아님|

## 17-5. 개체 관계도 작성 근거

### 가. 영역 3개로 나눠 배치

|영역|개체|성격|
|---|---|---|
|A.운동<br>정의|`exercise`·<br>`machine`|운동 마스터·273행|
|B.분류|`exercise_effect`(신) ·<br>`exercise_recommend_tag`(신) ·<br>`exercise_body_part`·<br>`exercise_body_part_detail`·|운동에 축을 붙이는 매핑과|
|매핑|`body_part`·<br>`body_part_detail`|사전·전부 1,000행 이하|
|C.회원|`user`·<br>`access_history`·<br>`user_exercise_session`·<br>`user_exercise_session_history`·|회원 기록·최대 30만 행|
|기록|`user_exercise_set_history`·<br>`user_personal_record_history`(신)||

- A는 B와 C를 잇는 축 · B는 A에만 붙고 C는 A를 참조 · B와 C 사이에 직접 연결은 없고 **`exercise`** 를 경유해야 함 · 이 사실이 관계도에서 드러나야 함

### 나. 개체별 표기 정보

|개체|기본키|행수(2026-08-21)|이번 개편 상태|
|---|---|---|---|
|`exercise`|`id`|273|변경—컬럼 3개 추가·1개 제거(후속)|
|`body_part`|`id`|8|변경—<br>`axis` 추가|
|`body_part_detail`|`id`|21|유지|
|`exercise_body_part`|`id`|376|변경—고유 제약 추가|
|`exercise_body_part_detail`|자연키 복합 →<br>`id`|514|변경—기여도 추가·대리키 이관|
|`exercise_function`|`(exercise_id, functional_tag)`|87|제거|
|`exercise_effect`|`id`|약 290(예상)|신설|
|`exercise_recommend_tag`|`id`|24(예상)|신설|
|`user_exercise_session`|`id`|327,844|유지|
|`user_exercise_session_history`|`id`|136,087|유지|
|`user_exercise_set_history`|`(session_history_id, set_number)` →<br>`id`|301,572|변경—대리키 이관 완료·`duration_second`·`done_at`·`created_at`·`updated_at` 추가 완료·`weight_unit`·`weight_kg` 취소·`rpe` 보류|
|`user_personal_record_history`|`id`|초기 적재분|신설|

- `personal_record_type` 행은 삭제했다 — 참조 테이블을 신설하지 않기로 했다(2026-09-03).

### 다. 관계와 다중도 ERD 1 운동 정의와 분류 매핑 — 개체 관계도

> **2026-09-03 정정** — 아래 도식의 `exercise` 개체에 적힌 `+ measure_type` 은 **취소**됐다. `+ has_duration` · `+ has_reps` (기존 `has_weight` 와 합쳐 플래그 3종)로 대체한다.

<!-- Start of picture text -->
A. 운동 정의 B. 분류 매핑<br>1:N<br>exercise 변경 exercise_function 제거 exercise_body_part 변경<br>운동 마스터 · 273행 87행 · 세 축이 한 컬럼에 혼재 부위 매핑 · 376행<br>PK id PK exercise_id PK id<br>name PK functional_tag FK exercise_id<br>type 1:N 이관 87행 → 2개 테이블 FK body_part_id<br>+ equipment_type status<br>+ measure_type exercise_effect 신설 + active_key + UNIQUE<br>+ cardio_intensity 1:N<br>운동 효과 축 · 계산용 · 약 290행<br>movement_pattern PK + id<br>unit / has_weight FK + exercise_id body_part 변경<br>fatigue_level 분류 라벨 사전 · 8행<br>1:N + effect_tag<br>PK id<br>+ is_primary<br>+ status part<br>machine + axis<br>+ active_key<br>지점 기구 · 6,149대 1:N<br>+ created_at / updated_at<br>PK id<br>gym_id body_part_detail<br>exercise_recommend_tag 신설 세부부위 사전 · 21행<br>PK id<br>추천용 태그 · 24행<br>PK + id FK body_part_id<br>FK + exercise_id detail_part<br>1:N<br>+ tag<br>+ status<br>exercise_body_part_detail 변경<br>세부부위 매핑 · 514행<br>PK + id<br>FK exercise_id<br>FK body_part_detail_id<br>load_ratio<br>+ contribution<br><!-- End of picture text -->

<!-- Start of picture text -->
굵은 빨강 테두리 신설 개체 검정 머리글 이번 개편에서 변경 점선 테두리 제거 대상 + 표시 컬럼 신설 컬럼 실선 외래키 연결 점선 값 복사·값 대조(외래키 아님)<br><!-- End of picture text -->

PK 기본키 · FK 외래키 · UK 고유 제약

### ERD 2 회원 기록과 최고 기록 — 개체 관계도

> **2026-09-03 정정 — 아래 도식은 2026-08-21 기준이며 다음 항목이 낡았다.** 다시 그릴 때 반영한다.
>
> |도식의 표기|현재|
> |---|---|
> |`personal_record_type` 개체(초기 3행)|**삭제** — 참조 테이블을 신설하지 않는다|
> |`user_personal_record_history.record_type_id` FK|`record_kind` enum 컬럼|
> |`record_value / weight_kg / reps`|`record_value / weight / reps / duration_second`|
> |`user_exercise_set_history.weight_unit`(상위 행에서 복사)|**취소** — `weight` 는 kg 고정|
> |`user_exercise_set_history.weight_kg`(생성 열·인덱스)|**취소** — `weight` 자체가 kg|
> |`user_exercise_set_history.performed_at`|`done_at`|
> |`user_exercise_set_history.rpe`|**보류**|
> |(없음)|`user_exercise_set_history.duration_second` 추가·`user_personal_record_history.current_key` 생성 열 추가|

<!-- Start of picture text -->
C-1. 회원 기록 C-2. 최고 기록(신설)<br>user access_history personal_record_type 신설<br>성별 405,306 · 생년 405,013 출입 기록 기록 종류 참조 · 초기 3행<br>PK id PK id PK + id<br>gender / birth UK + code<br>1:N 1:1 + display_name<br>+ value_unit<br>user_exercise_session + applies_to_measure<br>세션 · 327,844행 + min_value / max_value<br>PK id + status<br>FK user_id 1:N<br>FK access_history_id exercise  참조<br>FK gym_id<br>rpe ( 자각 강도  1~10 · 57.4%  수집 ) user_personal_record_history 신설<br>started_at / end_at 최고 기록 이력 · 갱신은 행 추가<br>1:N exercise  참조 PK + id<br>FK + user_id<br>user_exercise_session_history FK + exercise_id<br>세션 내 운동 1건 · 136,087행 FK + record_type_id<br>PK id FK + source_set_id<br>FK user_exercise_session_id + record_value / weight_kg / reps<br>FK exercise_id + achieved_at<br>FK machine_id + is_approximate / is_current<br>weight_type (kg / lb)<br>1:0..1<br>1:N<br>user_exercise_set_history 변경<br>세트 · 301,572행<br>PK + id<br>UK session_history_id + set_number<br>count / weight<br>+ weight_unit ( 상위 행에서 복사 )<br>+ weight_kg ( 생성 열  ·  인덱스 )<br>+ performed_at<br>+ rpe ( 자각 강도  1~10)<br>+ created_at / updated_at<br>C-1과-1과1과과 C-2는-2는2는는 직접접 연결되지결되지되지지 않고고 exercise 를 경유 — 부위별유 — 부위별 — 부위별부위별위별별 랭킹이킹이이 3단단 조인이인이 되는는 이유유<br><!-- End of picture text -->

<!-- Start of picture text -->
C-1과-1과1과과 C-2는-2는2는는 직접접 연결되지결되지되지지 않고고 exercise 를 경유 — 부위별유 — 부위별 — 부위별부위별위별별 랭킹이킹이이 3단단 조인이인이 되는는 이유유<br><!-- End of picture text -->

굵은 빨강 테두리 신설 개체 검정 머리글 이번 개편에서 변경 점선 테두리 제거 대상 + 표시 컬럼 신설 컬럼 실선 외래키 연결 점선 값 복사·값 대조(외래키 아님)

PK 기본키 · FK 외래키 · UK 고유 제약

`[A` 운동 정의 `] exercise ──1:N──→ exercise_effect            (` 신설 `·` 효과 축 `) exercise ──1:N──→ exercise_recommend_tag     (` 신설 `·` 추천용 `) exercise ──1:N──→ exercise_body_part         ←──N:1── body_part exercise ──1:N──→ exercise_body_part_detail  ←──N:1── body_part_detail body_part ──1:N──→ body_part_detail [C` 회원 기록 `] user ──1:N──→ user_exercise_session ──1:N──→ user_exercise_session_history │ 1:N ▼ user_exercise_set_history access_history ──1:1──→ user_exercise_session [A ↔ C] exercise ──1:N──→ user_exercise_session_history machine  ──1:N──→ user_exercise_session_history [` 최고 기록 `] user                      ──1:N──→ user_personal_record_history exercise                  ──1:N──→ user_personal_record_history user_exercise_set_history ──1:0..1──→ user_personal_record_history  (` 근거 세트 `)`

### 다-1. 다중도 판정 근거

|관계|다중도|근거|
|---|---|---|
|`exercise` →<br>`exercise_effect`|1:N|운동 1건에 효과 태그 여러 개·주 효과는 그중 1개(<br>`is_primary`)|
|`exercise` →<br>`exercise_body_part`|1:N|데드리프트처럼 여러 부위 등록이 정상·고유 제약이 막는 것은 같은 조합의 중복<br>뿐|
|`access_history` →<br>`user_exercise_session`|1:1|출입 1건당 세션 1건·방문 목표 계산의 근거|
|`user_exercise_session_history` →<br>`user_exercise_set_history`|1:N|운동 1건에 세트 여러 개·평균 2.2세트(301,572 ÷ 136,087)|
|`user_exercise_set_history` →<br>`user_personal_record_history`|1:0..1|대부분의 세트는 최고 기록이 아님·최고 기록 1건은 세트 1건을 근거로 지목|

### 라. 관계도 표기 규칙

- 신설 개체 — 굵은 테두리 + 신설 표시

- 변경 개체 — 변경된 컬럼만 별도 표기하고 미변경 컬럼은 생략 제거 개체 — 점선 테두리 + 이관 방향 화살표( `exercise_function` → 두 신설 테이블)

- 외래키 연결 — 실선

- 논리 연결(값 복사·값 대조) — 점선 · 17-4-다의 4건 · 실선과 반드시 구분해야 함(외래키로 오해하면 참조 무결성이 있다고 착각)

- 강제 순서 — 화살표에 순서 번호 표기 · **남은 것은 `4 → 12` 하나뿐**(`10 → 12` 는 대리키 반영으로 소멸 · `9 → 12` 는 kg 고정 정책으로 소멸 · [13](13_실행_순서와_의존_관계.md)) 행수 구간 — 개체 하단에 표기하고 30만 행 이상은 강조(변경 작업의 잠금 위험 지점)

### 마. 관계도에 반드시 드러나야 할 4가지

1. **`exercise_function`** 하나가 두 테이블로 갈라지는 것 — 이번 개편의 핵심이며, 효과 축은 계산 경로에 연결되고 추천용은 연결되지 않는다는 사실

2. 분류 매핑(B)과 회원 기록(C)이 직접 연결되지 않고 **`exercise`** 를 경유하는 것 — 부위별 랭킹·부위 커버리지가 3단 조인이 되는 이유

3. 무게가 세트 행에 **kg 고정**으로 저장되고 상위 행의 `weight_type` 은 표시 단위 선호일 뿐이라는 것 — 종전에 이 도식이 담아야 했던 "단위를 세트로 복사"는 취소됐고(2026-09-03), 이제 드러나야 할 것은 두 값이 같은 축이 아니라는 사실이다

4. 최고 기록이 세트 대리키를 참조하는 것 — 대리키가 없으면 이 연결이 성립하지 않는다는 것이 강제 순서의 근거

---

[이전](16_변경_후_검증.md) · [목차](README.md) · [다음](99_원문_페이지별_보기.md)
