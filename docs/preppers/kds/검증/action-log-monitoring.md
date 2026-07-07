# kds_order_action_log 모니터링 결과

## 조회 기준

- DB: `kds_dev`
- 조회 시각: `2026-07-07 09:58:28 UTC`
- DB timezone: `@@session.time_zone = UTC`, `@@global.time_zone = UTC`
- 대상 테이블: `kds_order_action_log`
- 비교 테이블: `kds_order`

이 문서는 `kds_order_action_log`가 이상 없이 기록되는지 확인하기 위해 사용한 쿼리와 결과를 정리한다.

## 요약

조회 시점 기준 `kds_order_action_log`는 총 374건이었다.

| 항목 | 결과 |
| --- | ---: |
| 전체 로그 수 | 374 |
| id 범위 | 1 ~ 374 |
| 최초 로그 시각 | 2026-06-17 06:17:17.138038 |
| 마지막 로그 시각 | 2026-07-07 09:54:39.782407 |

액션별 분포는 아래와 같다.

| action | count | first_at | last_at |
| --- | ---: | --- | --- |
| COMPLETE_POSITION | 309 | 2026-06-17 06:17:17.138038 | 2026-07-07 09:54:39.782407 |
| CHANGE_STATUS | 36 | 2026-06-30 14:57:24.960624 | 2026-07-07 09:13:24.811642 |
| SET_URGENT | 13 | 2026-06-30 15:03:59.888165 | 2026-07-07 04:17:02.664326 |
| REVERT_POSITION | 10 | 2026-06-30 14:54:02.283795 | 2026-07-07 05:54:44.240150 |
| SET_SERVICE_TYPE | 6 | 2026-07-02 01:30:38.653429 | 2026-07-07 09:13:24.828143 |

## 발견된 이상 후보

### 1. kds_order 참조가 끊긴 로그

`kds_order_action_log.kds_order_id`로 `kds_order.id`에 조인되지 않는 로그가 38건 있었다.

추가로 `store_id + order_id` 기준으로도 현재 `kds_order`에 남아있는 주문이 없었다. dev DB에서 주문 row를 정리했거나 재생성한 결과일 수 있지만, action log가 감사 로그 역할을 한다면 추적성이 끊긴 상태다.

| check_name | count |
| --- | ---: |
| orphan_by_kds_order_id | 38 |
| mismatch_store_or_order | 0 |
| null_kds_order_id | 0 |
| future_created_at | 0 |
| empty_change_json | 1 |

### 2. 빈 change_json

`change_json`이 비어 있는 로그가 1건 있었다.

| id | store_id | order_id | kds_order_id | action | position | change_json | created_at |
| ---: | ---: | ---: | ---: | --- | --- | --- | --- |
| 6 | 21 | 1097582 | 15667 | COMPLETE_POSITION | PICKUP | `{}` | 2026-06-30 03:10:14.962105 |

### 3. 동일 주문/액션/포지션 중복 로그

`kds_order_id + store_id + order_id + action + position` 기준으로 중복된 로그가 있었다.

| 항목 | 결과 |
| --- | ---: |
| 중복 그룹 수 | 24 |
| 중복 row 수 | 56 |

중복 자체가 항상 오류는 아니다. 예를 들어 `REVERT_POSITION` 후 다시 `COMPLETE_POSITION`하는 정상 흐름이 있을 수 있다. 다만 `PICKUP` 완료가 이미 `COMPLETED`로 기록된 뒤 다시 `before=ACTIVE, after=COMPLETED`로 찍힌 케이스는 재호출 또는 상태 재활성화 후 재완료로 보인다.

## 완료된 주문에 COMPLETE_POSITION 재호출로 보이는 로그

질문에서 언급한 `COMPLETED_POSITION`은 실제 DB action 값 기준으로는 `COMPLETE_POSITION`이다.

아래 목록은 같은 `kds_order_id`에서 이전 `COMPLETE_POSITION / PICKUP` 로그의 `after`가 `COMPLETED`였는데, 이후 다시 `before=ACTIVE, after=COMPLETED`로 `COMPLETE_POSITION / PICKUP`이 기록된 케이스다.

| current_log_id | previous_log_id | kds_order_id | store_id | order_id | position | before | previous_after | after | previous_created_at | current_created_at |
| ---: | ---: | ---: | ---: | ---: | --- | --- | --- | --- | --- | --- |
| 374 | 303 | 37763 | 56 | 1120718 | PICKUP | ACTIVE | COMPLETED | COMPLETED | 2026-07-06 09:05:58.597205 | 2026-07-07 09:54:39.782407 |
| 373 | 365 | 28922 | 56 | 1111828 | PICKUP | ACTIVE | COMPLETED | COMPLETED | 2026-07-07 09:29:25.184877 | 2026-07-07 09:54:38.968300 |
| 372 | 361 | 41965 | 56 | 1124957 | PICKUP | ACTIVE | COMPLETED | COMPLETED | 2026-07-07 09:23:20.549480 | 2026-07-07 09:54:28.395959 |
| 371 | 352 | 16726 | 56 | 1098648 | PICKUP | ACTIVE | COMPLETED | COMPLETED | 2026-07-07 08:17:41.617923 | 2026-07-07 09:54:27.105700 |
| 370 | 362 | 22144 | 56 | 1104805 | PICKUP | ACTIVE | COMPLETED | COMPLETED | 2026-07-07 09:25:50.983232 | 2026-07-07 09:54:09.088298 |
| 369 | 363 | 19049 | 56 | 1101223 | PICKUP | ACTIVE | COMPLETED | COMPLETED | 2026-07-07 09:25:52.165249 | 2026-07-07 09:54:06.895372 |
| 368 | 364 | 16715 | 56 | 1098637 | PICKUP | ACTIVE | COMPLETED | COMPLETED | 2026-07-07 09:29:20.739733 | 2026-07-07 09:54:06.191628 |
| 367 | 355 | 41953 | 56 | 1124943 | PICKUP | ACTIVE | COMPLETED | COMPLETED | 2026-07-07 09:07:10.537837 | 2026-07-07 09:36:54.286021 |
| 366 | 106 | 15799 | 56 | 1097714 | PICKUP | ACTIVE | COMPLETED | COMPLETED | 2026-07-06 09:03:44.790333 | 2026-07-07 09:36:46.949583 |
| 365 | 95 | 28922 | 56 | 1111828 | PICKUP | ACTIVE | COMPLETED | COMPLETED | 2026-07-06 09:03:34.806174 | 2026-07-07 09:29:25.184877 |
| 364 | 85 | 16715 | 56 | 1098637 | PICKUP | ACTIVE | COMPLETED | COMPLETED | 2026-07-06 09:01:11.050036 | 2026-07-07 09:29:20.739733 |
| 363 | 62 | 19049 | 56 | 1101223 | PICKUP | ACTIVE | COMPLETED | COMPLETED | 2026-07-03 03:56:25.347056 | 2026-07-07 09:25:52.165249 |
| 362 | 64 | 22144 | 56 | 1104805 | PICKUP | ACTIVE | COMPLETED | COMPLETED | 2026-07-03 04:31:29.692359 | 2026-07-07 09:25:50.983232 |
| 354 | 99 | 15696 | 56 | 1097611 | PICKUP | ACTIVE | COMPLETED | COMPLETED | 2026-07-06 09:03:39.642090 | 2026-07-07 09:05:17.936253 |
| 352 | 61 | 16726 | 56 | 1098648 | PICKUP | ACTIVE | COMPLETED | COMPLETED | 2026-07-03 03:56:15.380306 | 2026-07-07 08:17:41.617923 |
| 351 | 90 | 15246 | 56 | 1097161 | PICKUP | ACTIVE | COMPLETED | COMPLETED | 2026-07-06 09:01:18.262652 | 2026-07-07 08:03:51.006227 |
| 341 | 83 | 15030 | 56 | 1096936 | PICKUP | ACTIVE | COMPLETED | COMPLETED | 2026-07-06 07:29:46.143606 | 2026-07-06 11:00:25.085379 |

`kds_order_id`별 `COMPLETE_POSITION / PICKUP` 중복 로그 id는 아래와 같다.

| kds_order_id | store_id | order_id | log_ids | count | first_at | last_at |
| ---: | ---: | ---: | --- | ---: | --- | --- |
| 37763 | 56 | 1120718 | 303,374 | 2 | 2026-07-06 09:05:58.597205 | 2026-07-07 09:54:39.782407 |
| 28922 | 56 | 1111828 | 95,365,373 | 3 | 2026-07-06 09:03:34.806174 | 2026-07-07 09:54:38.968300 |
| 41965 | 56 | 1124957 | 361,372 | 2 | 2026-07-07 09:23:20.549480 | 2026-07-07 09:54:28.395959 |
| 16726 | 56 | 1098648 | 61,352,371 | 3 | 2026-07-03 03:56:15.380306 | 2026-07-07 09:54:27.105700 |
| 22144 | 56 | 1104805 | 64,362,370 | 3 | 2026-07-03 04:31:29.692359 | 2026-07-07 09:54:09.088298 |
| 19049 | 56 | 1101223 | 62,363,369 | 3 | 2026-07-03 03:56:25.347056 | 2026-07-07 09:54:06.895372 |
| 16715 | 56 | 1098637 | 85,364,368 | 3 | 2026-07-06 09:01:11.050036 | 2026-07-07 09:54:06.191628 |
| 41953 | 56 | 1124943 | 355,367 | 2 | 2026-07-07 09:07:10.537837 | 2026-07-07 09:36:54.286021 |
| 15799 | 56 | 1097714 | 106,366 | 2 | 2026-07-06 09:03:44.790333 | 2026-07-07 09:36:46.949583 |
| 15696 | 56 | 1097611 | 99,354 | 2 | 2026-07-06 09:03:39.642090 | 2026-07-07 09:05:17.936253 |
| 15246 | 56 | 1097161 | 90,351 | 2 | 2026-07-06 09:01:18.262652 | 2026-07-07 08:03:51.006227 |
| 15030 | 56 | 1096936 | 83,341 | 2 | 2026-07-06 07:29:46.143606 | 2026-07-06 11:00:25.085379 |
| 15667 | 21 | 1097582 | 5,6 | 2 | 2026-06-30 03:09:33.929221 | 2026-06-30 03:10:14.962105 |

## 해석

현재 데이터만 보면 `kds_order_action_log`가 아예 누락되는 상태는 아니다. 다만 아래 이유로 “이상 없이 잘 들어가고 있다”고 보기는 어렵다.

- `kds_order`와 연결되지 않는 action log가 38건 있다.
- `change_json`이 비어 있어 변경 전후를 알 수 없는 로그가 1건 있다.
- 이미 `COMPLETED`로 끝난 `PICKUP` 완료 로그 이후 다시 `ACTIVE -> COMPLETED` 완료 로그가 찍힌 케이스가 있다.
- 일부 주문은 action log 이후 `kds_order.updated_at`이 더 늦게 갱신되며 현재값이 다시 `ACTIVE` 쪽으로 바뀐 흔적이 있었다. action API 외에 `kds_order`를 갱신하는 경로가 있고, 그 경로가 action log를 남기지 않는지 확인이 필요하다.

우선 확인할 내용은 다음과 같다.

1. `COMPLETE_POSITION / PICKUP`이 이미 완료된 주문에 대해 재호출될 수 있는지 확인한다.
2. 완료된 주문을 다시 `ACTIVE`로 되돌리는 배치, polling, projection, 테스트 스크립트가 있는지 확인한다.
3. `kds_order` 삭제 또는 재생성 시 `kds_order_action_log` 보존 정책이 현재 의도와 맞는지 확인한다.
4. `change_json`이 `{}`로 저장되는 경로를 막거나, 변경 없는 액션이라면 로그를 남기지 않도록 정책을 정한다.

## 사용한 쿼리

### timezone 확인

```sql
select
  @@session.time_zone as session_tz,
  @@global.time_zone as global_tz,
  now() as db_now,
  utc_timestamp() as utc_now;
```

### 테이블 구조 확인

```sql
show create table kds_order_action_log\G
show create table kds_order\G
```

### 전체 건수와 액션 분포

```sql
select
  utc_timestamp() checked_at_utc;

select
  count(*) total,
  min(id) min_id,
  max(id) max_id,
  min(created_at) first_created_at,
  max(created_at) last_created_at
from kds_order_action_log;

select
  action,
  count(*) cnt,
  min(created_at) first_at,
  max(created_at) last_at
from kds_order_action_log
group by action
order by cnt desc;
```

### 기본 이상 여부 집계

```sql
select 'orphan_by_kds_order_id' check_name, count(*) cnt
from kds_order_action_log l
left join kds_order ko on ko.id = l.kds_order_id
where l.kds_order_id is not null
  and ko.id is null

union all

select 'mismatch_store_or_order', count(*)
from kds_order_action_log l
join kds_order ko on ko.id = l.kds_order_id
where ko.store_id <> l.store_id
   or ko.order_id <> l.order_id

union all

select 'null_kds_order_id', count(*)
from kds_order_action_log
where kds_order_id is null

union all

select 'future_created_at', count(*)
from kds_order_action_log
where created_at > utc_timestamp() + interval 1 minute

union all

select 'empty_change_json', count(*)
from kds_order_action_log
where change_json is null
   or json_length(change_json) = 0;
```

### orphan 로그 상세

```sql
select
  l.id,
  l.store_id,
  l.order_id,
  l.kds_order_id,
  l.action,
  l.position,
  json_pretty(l.change_json) change_json,
  l.created_at
from kds_order_action_log l
left join kds_order ko on ko.id = l.kds_order_id
where ko.id is null
order by l.id desc
limit 50;
```

### 동일 주문/액션/포지션 중복 집계

```sql
select
  count(*) duplicate_groups,
  sum(cnt) duplicate_rows
from (
  select
    kds_order_id,
    store_id,
    order_id,
    action,
    position,
    count(*) cnt
  from kds_order_action_log
  group by kds_order_id, store_id, order_id, action, position
  having count(*) > 1
) d;
```

### COMPLETE_POSITION / PICKUP 중복 로그 id

```sql
select
  kds_order_id,
  store_id,
  order_id,
  action,
  position,
  group_concat(id order by created_at, id separator ',') log_ids,
  count(*) cnt,
  min(created_at) first_at,
  max(created_at) last_at
from kds_order_action_log
where action = 'COMPLETE_POSITION'
  and position = 'PICKUP'
group by kds_order_id, store_id, order_id, action, position
having count(*) > 1
order by last_at desc;
```

### 완료 후 COMPLETE_POSITION 재호출 의심 로그

```sql
with field_events as (
  select
    id,
    kds_order_id,
    store_id,
    order_id,
    created_at,
    action,
    position,
    json_unquote(json_extract(change_json, '$.displayStatus.before')) before_v,
    json_unquote(json_extract(change_json, '$.displayStatus.after')) after_v
  from kds_order_action_log
  where action = 'COMPLETE_POSITION'
    and json_extract(change_json, '$.displayStatus') is not null
),
sequenced as (
  select
    field_events.*,
    lag(id) over (
      partition by kds_order_id
      order by created_at, id
    ) prev_log_id,
    lag(action) over (
      partition by kds_order_id
      order by created_at, id
    ) prev_action,
    lag(position) over (
      partition by kds_order_id
      order by created_at, id
    ) prev_position,
    lag(before_v) over (
      partition by kds_order_id
      order by created_at, id
    ) prev_before_v,
    lag(after_v) over (
      partition by kds_order_id
      order by created_at, id
    ) prev_after_v,
    lag(created_at) over (
      partition by kds_order_id
      order by created_at, id
    ) prev_created_at
  from field_events
)
select
  id,
  prev_log_id,
  kds_order_id,
  store_id,
  order_id,
  action,
  position,
  before_v,
  prev_after_v,
  after_v,
  prev_created_at,
  created_at
from sequenced
where before_v = 'ACTIVE'
  and after_v = 'COMPLETED'
  and prev_after_v = 'COMPLETED'
order by created_at desc;
```

### change_json before/after 연속성 검사

```sql
with field_events as (
  select
    id,
    kds_order_id,
    store_id,
    order_id,
    created_at,
    action,
    position,
    'displayStatus' field,
    json_unquote(json_extract(change_json, '$.displayStatus.before')) before_v,
    json_unquote(json_extract(change_json, '$.displayStatus.after')) after_v
  from kds_order_action_log
  where json_extract(change_json, '$.displayStatus') is not null

  union all

  select
    id,
    kds_order_id,
    store_id,
    order_id,
    created_at,
    action,
    position,
    'currentPosition',
    json_unquote(json_extract(change_json, '$.currentPosition.before')),
    json_unquote(json_extract(change_json, '$.currentPosition.after'))
  from kds_order_action_log
  where json_extract(change_json, '$.currentPosition') is not null

  union all

  select
    id,
    kds_order_id,
    store_id,
    order_id,
    created_at,
    action,
    position,
    'isUrgent',
    json_unquote(json_extract(change_json, '$.isUrgent.before')),
    json_unquote(json_extract(change_json, '$.isUrgent.after'))
  from kds_order_action_log
  where json_extract(change_json, '$.isUrgent') is not null

  union all

  select
    id,
    kds_order_id,
    store_id,
    order_id,
    created_at,
    action,
    position,
    'serviceType',
    json_unquote(json_extract(change_json, '$.serviceType.before')),
    json_unquote(json_extract(change_json, '$.serviceType.after'))
  from kds_order_action_log
  where json_extract(change_json, '$.serviceType') is not null
),
sequenced as (
  select
    field_events.*,
    lag(after_v) over (
      partition by kds_order_id, field
      order by created_at, id
    ) prev_after_v,
    lag(id) over (
      partition by kds_order_id, field
      order by created_at, id
    ) prev_log_id
  from field_events
)
select
  id,
  prev_log_id,
  kds_order_id,
  store_id,
  order_id,
  field,
  before_v,
  prev_after_v,
  after_v,
  action,
  position,
  created_at
from sequenced
where prev_after_v is not null
  and before_v <> prev_after_v
order by created_at desc
limit 100;
```

### 최신 로그 after 값과 현재 kds_order 값 비교

```sql
with field_events as (
  select
    id,
    kds_order_id,
    store_id,
    order_id,
    created_at,
    action,
    position,
    'displayStatus' field,
    json_unquote(json_extract(change_json, '$.displayStatus.after')) after_v
  from kds_order_action_log
  where json_extract(change_json, '$.displayStatus') is not null

  union all

  select
    id,
    kds_order_id,
    store_id,
    order_id,
    created_at,
    action,
    position,
    'currentPosition',
    json_unquote(json_extract(change_json, '$.currentPosition.after'))
  from kds_order_action_log
  where json_extract(change_json, '$.currentPosition') is not null

  union all

  select
    id,
    kds_order_id,
    store_id,
    order_id,
    created_at,
    action,
    position,
    'isUrgent',
    json_unquote(json_extract(change_json, '$.isUrgent.after'))
  from kds_order_action_log
  where json_extract(change_json, '$.isUrgent') is not null

  union all

  select
    id,
    kds_order_id,
    store_id,
    order_id,
    created_at,
    action,
    position,
    'serviceType',
    json_unquote(json_extract(change_json, '$.serviceType.after'))
  from kds_order_action_log
  where json_extract(change_json, '$.serviceType') is not null
),
latest as (
  select
    field_events.*,
    row_number() over (
      partition by kds_order_id, field
      order by created_at desc, id desc
    ) rn
  from field_events
)
select
  l.id log_id,
  l.kds_order_id,
  l.store_id,
  l.order_id,
  l.field,
  l.after_v log_after,
  case l.field
    when 'displayStatus' then ko.display_status
    when 'currentPosition' then ko.current_position
    when 'isUrgent' then if(ko.is_urgent = 1, 'true', 'false')
    when 'serviceType' then ko.service_type
  end current_value,
  l.action,
  l.position,
  l.created_at,
  ko.updated_at
from latest l
join kds_order ko on ko.id = l.kds_order_id
where l.rn = 1
  and coalesce(l.after_v, '') <> coalesce(
    case l.field
      when 'displayStatus' then ko.display_status
      when 'currentPosition' then ko.current_position
      when 'isUrgent' then if(ko.is_urgent = 1, 'true', 'false')
      when 'serviceType' then ko.service_type
    end,
    ''
  )
order by l.created_at desc
limit 100;
```
