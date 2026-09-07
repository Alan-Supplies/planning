# 기구 분류 참조 — `machine.type` · `machine.type_detail`

> 관련: [05-부록. PROP 42종 재배치 판례](DB_구조_업그레이드_방안_섹션별/05_장비_분류_PROP42_재배치판례.probe) ·
> [05. 장비 분류](DB_구조_업그레이드_방안_섹션별/05_장비_분류.md)

지점 기구 인벤토리의 분류 값을 한글로 매칭하고 각 값이 실제로 무엇을 담고 있는지 정리한 참조 문서.
`exercise.equipment_type` 12종과 지점 인벤토리를 조인해 "이 지점에서 할 수 있는 운동" 을 판정할 때
어느 값을 봐야 하는지 확인하는 용도다.

실측 기준 — 2026-09-04 · 운영 DB `gymboxx` (`db-ro` 리드 레플리카 · [docs/ai/gymboxx.db.md](../ai/gymboxx.db.md))

## 구조

|테이블|역할|규모|
|---|---|---|
|`machine`|기구 **품목 카탈로그** · 브랜드별 모델 단위 · `machine_brand_id NOT NULL`|1,155종|
|`gym_machine`|지점별 **개체** · `unique_code`·`qr_url`·수리 이력 보유|6,420대 (`ACTIVE` 6,243)|
|`exercise_machine`|운동 ↔ 품목 매핑 · 판정의 연결고리|—|

`type` 이 대분류(6종, 오타 1종 포함), `type_detail` 이 소분류(19종, `NULL` 포함 20종)다.
아래 수치는 `gym_machine.status = 'ACTIVE'` 기준이며 전체 지점 수는 64개다.

## 대분류 `machine.type`

|값|한글|설명|품목 종수|
|---|---|---|---|
|`PIN`|핀 머신|핀으로 웨이트 스택 중량을 선택하는 머신|538|
|`PLATE_LOADED`|플레이트 머신|원판을 직접 끼워 부하를 만드는 머신 · 스미스 포함|337|
|`FREE_WEIGHT`|프리웨이트·구조물|덤벨·고정 바벨과 랙·벤치·기능성 체어 등 지지 구조물|167|
|`CARDIO`|유산소 기구|트레드밀·사이클·스텝밀 등 시간 단위 기구|58|
|`CABLES`|케이블|도르래로 부하 방향을 바꾸는 기구|51|
|`FREE_WEIGHTS`|**오타 중복**|`FREE_WEIGHT` 와 같은 뜻 · 품목 4종만 이 값에 있음|4|

`FREE_WEIGHT` 와 `FREE_WEIGHTS` 는 같은 대분류다. 후자에 들어간 4종은 `Back Extension`(id 95) ·
`Flat Bench`(99) · `Olympic Flat Bench`(138) · `Olympic Incline Bench`(139) 이며, `type_detail` 은 정상이므로
**대분류 값만 `FREE_WEIGHT` 로 정정하면 된다.** 정정 전에는 `type` 으로 집계할 때 반드시 두 값을 함께 봐야 한다.

## 소분류 `machine.type_detail`

### 핀 머신 계열

|값|한글|설명|품목 종수|등록 대수|보유 지점|
|---|---|---|---|---|---|
|`PIN`|핀 로디드 머신|핀으로 중량 선택 · 궤도와 대상 부위가 기구에 고정 · 인벤토리 최대 갈래|536|1,802|59|
|`(NULL)`|미분류|`Inner Thigh`(1160) · `Outer Thigh`(1161) 2종 · Precor 제품 · **`PIN` 으로 채워야 함**|2|2|1|

대표 품목 — Leg Press · Shoulder Press · Bicep Curl · Hip Abduction/Adduction · Inner / Outer Thigh

### 플레이트 머신 계열

|값|한글|설명|품목 종수|등록 대수|보유 지점|
|---|---|---|---|---|---|
|`PLATE_LOADED`|플레이트 로디드 머신|원판을 끼우는 머신 · 궤도는 고정, 중량은 원판 · ISO-Lateral 계열 다수|314|1,662|59|
|`SMITH`|스미스 머신|바벨이 수직·사선 레일에 고정된 랙형 기구 · 12종 분류에서 **별도 값**|23|125|59|

`SMITH` 는 대분류가 `PLATE_LOADED` 지만 12종에서는 독립 값이므로, 플레이트 머신을 뽑을 때
`type_detail = 'PLATE_LOADED'` 로 좁혀야 한다. `type = 'PLATE_LOADED'` 로 집계하면 스미스가 섞인다.

### 케이블 계열

|값|한글|설명|품목 종수|등록 대수|보유 지점|
|---|---|---|---|---|---|
|`CABLE_STATION`|케이블 스테이션 (멀티 정글짐)|여러 스테이션이 한 프레임에 붙은 복합 기구 · 5·8스택|24|54|49|
|`DUAL_PULLEY`|듀얼 풀리 (케이블 크로스오버)|좌우 독립 도르래 2개 · 높이 조절식|25|54|39|
|`SINGLE_PULLEY`|싱글 풀리|도르래 1개 · `Hi-Low Pulley` 1종만 등록|1|1|1|
|`CABLES`|**미분류**|대분류와 이름이 같은 값 · 실제 품목은 `Multi-Jungle(6-Stack)`(1069) 1종 · **`CABLE_STATION` 으로 정정 필요**|1|1|1|

### 유산소 계열

|값|한글|설명|품목 종수|등록 대수|보유 지점|
|---|---|---|---|---|---|
|`TREADMILL`|트레드밀 (러닝머신)|걷기·달리기 · 등록 대수 최다 유산소 품목|14|946|58|
|`CYCLE`|사이클|좌식·입식·크랭크 사이클|14|353|57|
|`STEPMILL`|스텝밀 (클라임밀)|계단 오르기 · Gauntlet·Climbmill 계열|12|241|58|
|`CARDIO_ETC`|기타 유산소|일립티컬·스탭퍼·아크 트레이너·로잉 등 위 3종에 안 들어가는 것|18|58|33|

`exercise` 쪽 유산소 기구 11종(트레드밀 런·워크, 인클라인 트레드 밀, 좌식·입식 사이클, 일립티컬,
로잉 머신, 스텝밀, 스탭퍼, 래더밀, 핸드 바이크)이 이 4갈래에 대응한다.

### 프리웨이트 부속

|값|한글|설명|품목 종수|등록 대수|보유 지점|
|---|---|---|---|---|---|
|`DUMBBELL`|덤벨 세트|무게 구간 단위로 1품목 · `Dumbbell Set 2kg - 20kg` 처럼 세트가 한 대로 등록|20|197|45|
|`FIXED_BARBELL`|고정 바벨 세트|무게 고정 바벨·EZ컬 바 세트 · 구간 단위 등록|11|83|42|

덤벨·바벨은 **개별 중량이 아니라 세트 단위**로 등록된다. 그래서 "이 지점에 30kg 덤벨이 있는가" 는
품목명 문자열(`42kg - 60kg`)을 파싱해야 알 수 있고 구조화된 값으로는 답할 수 없다.

### 구조물 — 지점 판정의 근거가 되는 갈래

|값|한글|설명|품목 종수|등록 대수|보유 지점|
|---|---|---|---|---|---|
|`OLYMPIC_BENCH`|올림픽 벤치|바벨 거치대가 붙은 벤치 · 플랫·인클라인·디클라인·숄더|45|171|58|
|`FUNCTIONAL_CHAIR`|기능성 체어|특정 동작 전용 구조물 · 백 익스텐션·레그 레이즈·프리처 컬·AB 벤치·친딥 타워|69|150|52|
|`PLATFORM_RACK`|랙+플랫폼 일체형|`Half Rack with Weightlifting Platform` 1종뿐인데 193대 · 짐박스 표준 설비|1|193|37|
|`RACK`|랙|하프랙·파워케이지 · 스쿼트·벤치프레스 지지 구조물|16|112|22|
|`PLATFORM`|플랫폼|역도 플랫폼·스트레치 플랫폼|3|30|23|
|`BASIC_BENCH`|기본 벤치|거치대 없는 조절식·평벤치 · 등록 대수 최소|6|8|4|

`FUNCTIONAL_CHAIR` 가 구조물 판정의 핵심이다. 철봉·딥스는 파워타워형으로 여기에 들어가고
(`Chin / Dip / Leg Raise` · `Pull-Up / Dip / Leg Raise` · `Chin/Dip/Push-Up Training Tower`),
어시스트 머신형은 `PIN` 에 들어간다(`Chin Dip Assist` 등). **같은 "철봉 운동"이 두 갈래에 흩어져 있다.**

## 벤치의 이중 성격 — 판정 시 주의

벤치는 두 역할을 동시에 한다.

- **바벨·덤벨 운동의 부속** — 벤치 프레스, 인클라인 덤벨 프레스. 이때 부하는 바벨·덤벨이므로
  `equipment_type` 은 `BARBELL`·`DUMBBELL` 이고 벤치는 판정 조건에 추가로 필요한 설비다
- **구조물 종목의 부하 지점** — 벤치 딥스, 벤치 스플릿 스쿼트, 디클라인 크런치. 부하는 체중이고
  벤치가 없으면 성립하지 않으므로 `equipment_type = STRUCTURE` 다

따라서 `OLYMPIC_BENCH`·`BASIC_BENCH` 보유는 구조물 종목만이 아니라 바벨·덤벨 종목의 판정에도 쓰인다.
**`type_detail` 과 `equipment_type` 은 1:1 이 아니다.**

## 12종 `equipment_type` ↔ `type_detail` 대응

|`equipment_type` (제안)|한글|`machine.type_detail`|판정 가능|
|---|---|---|---|
|`PIN`|핀 머신|`PIN` (+ `NULL` 2종)|가능|
|`PLATE_LOADED`|플레이트 머신|`PLATE_LOADED`|가능|
|`SMITH`|스미스|`SMITH`|가능|
|`CABLE`|케이블|`CABLE_STATION` · `DUAL_PULLEY` · `SINGLE_PULLEY` · `CABLES`|가능|
|`CARDIO`|유산소 기구|`TREADMILL` · `CYCLE` · `STEPMILL` · `CARDIO_ETC`|가능|
|`BARBELL`|바벨|`FIXED_BARBELL` · `RACK` · `PLATFORM_RACK` · `PLATFORM`|가능 (중량 구간은 불가)|
|`DUMBBELL`|덤벨|`DUMBBELL`|가능 (중량 구간은 불가)|
|`STRUCTURE`|구조물|`FUNCTIONAL_CHAIR` · `OLYMPIC_BENCH` · `BASIC_BENCH` · `RACK` · `PLATFORM`|가능|
|`KETTLEBELL`|케틀벨|**없음**|**불가**|
|`BAND`|밴드|**없음**|**불가**|
|`PROP`|소도구|**없음**|**판정 불필요** — 전 지점 보유|
|`BODYWEIGHT`|맨몸|해당 없음 (설비 불필요)|판정 불필요|

케틀벨·밴드·소도구는 `machine` 카탈로그에 품목이 없다 — 품목명 검색
(`kettle|band|foam|roll|ball|stick|bosu`)이 0행이다. 다만 **소도구는 전 지점이 보유하므로
판정이 필요 없고**(업무 확인 2026-09-04) 실제 미해결은 케틀벨·밴드뿐이다. 자세한 내용과 대안은
[판례 문서 §6](DB_구조_업그레이드_방안_섹션별/05_장비_분류_PROP42_재배치판례.probe) 참고.

## 정정 대상 4건

|대상|현재|정정|
|---|---|---|
|`machine.type`|`FREE_WEIGHTS` 4종 (id 95·99·138·139)|`FREE_WEIGHT`|
|`machine.type_detail`|`NULL` 2종 (id 1160·1161 · Inner/Outer Thigh)|`PIN`|
|`machine.type_detail`|`CABLES` 1종 (id 1069 · Multi-Jungle 6-Stack)|`CABLE_STATION`|
|—|`SINGLE_PULLEY` 1종·1대|`DUAL_PULLEY` 통합 검토|

앞의 3건은 값 오류이므로 정정하면 대분류·소분류 집계가 각각 5종·17종으로 정리된다.

## 조회 쿼리

```sql
-- 대·소분류 전체 현황 (이 문서의 표 원본)
SELECT m.type,
       IFNULL(m.type_detail, '(NULL)')  AS type_detail,
       COUNT(DISTINCT m.id)             AS 품목종수,
       COUNT(gm.id)                     AS 등록대수,
       COUNT(DISTINCT gm.gym_id)        AS 보유지점
  FROM machine m
  LEFT JOIN gym_machine gm
         ON gm.machine_id = m.id AND gm.status = 'ACTIVE'
 GROUP BY m.type, m.type_detail
 ORDER BY 등록대수 DESC;
```

```sql
-- 특정 소분류의 대표 품목 확인
SELECT id, name, type, type_detail
  FROM machine
 WHERE type_detail = 'FUNCTIONAL_CHAIR'
 ORDER BY name;
```

```sql
-- 정정 대상 3건 확인
SELECT id, name, type, type_detail FROM machine WHERE type = 'FREE_WEIGHTS';
SELECT id, name, type, type_detail FROM machine WHERE type_detail IS NULL;
SELECT id, name, type, type_detail FROM machine WHERE type_detail = 'CABLES';
```

```sql
-- 지점별 가능 운동 판정 (구조물·머신·케이블·유산소만 성립)
SELECT DISTINCT e.id, e.name, e.type
  FROM gym_machine gm
  JOIN machine m           ON m.id  = gm.machine_id
  JOIN exercise_machine em ON em.machine_id = m.id
  JOIN exercise e          ON e.id  = em.exercise_id
 WHERE gm.gym_id = ?          -- 판정 대상 지점
   AND gm.status = 'ACTIVE'
   AND e.status  = 'ACTIVE'
 ORDER BY e.type, e.name;
```

마지막 쿼리는 `exercise_machine` 매핑이 있는 종목만 나온다. 현재 매핑 보유율은 케이블 100% ·
머신 88.3% · 바벨 16.1% · 맨몸 9.8% · 소도구 7.1% · 덤벨 1.8% 이므로, 이 쿼리로 판정되는 범위는
사실상 머신·케이블뿐이다.
