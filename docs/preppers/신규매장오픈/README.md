# 신규 매장 오픈

EasyPrep 신규 매장을 생성하고 OWNER 및 관리자 접근 권한을 설정할 때 사용하는 체크리스트다.

반복 업무를 문서 기반으로 운영할지 Codex 스킬로 만들지에 대한 논의는 [`DISCUSSION.md`](./DISCUSSION.md)를 참고한다.

## 작업 순서

1. `store` 생성 여부와 매장 정보를 확인한다.
2. 매장 OWNER용 `employee`와 `employee_store_access`를 확인한다.
3. 요청된 관리자 `employee`가 모두 존재하고 `ACTIVE`인지 확인한다.
4. 관리자별 `employee_store_access`를 생성하거나 기존 비활성 행을 활성화한다.
5. 대상 인원, 중복 행, 최종 상태를 검증한 후 커밋한다.

운영 DB 조회는 [`docs/ai/db.md`](../../ai/db.md)의 읽기 전용 계정을 사용한다. 실제 변경은 별도의 쓰기 권한 계정으로 실행한다.

## 사전 검증

비밀번호와 전화번호는 조회 결과에 포함하지 않는다.

```sql
-- 매장 확인
SELECT
    id,
    store_unique_id,
    name,
    address,
    is_franchise,
    open_date,
    owner_name,
    status,
    created_at
FROM store
WHERE name = :store_name;

-- OWNER 및 현재 접근 권한 확인
SELECT
    e.id AS employee_id,
    e.name,
    e.role,
    e.is_all_store_access,
    e.status AS employee_status,
    esa.id AS access_id,
    esa.status AS access_status
FROM employee_store_access esa
JOIN employee e ON e.id = esa.employee_id
WHERE esa.store_id = :store_id
ORDER BY esa.id;

-- 요청된 관리자 계정 확인
SELECT id, name, role, is_all_store_access, status
FROM employee
WHERE name IN (:employee_names)
ORDER BY id;
```

다음을 모두 확인한 뒤 변경한다.

- 매장이 정확히 1개 조회된다.
- 요청된 직원이 모두 정확히 1명씩 조회된다.
- 직원의 `role`과 `status`가 기대값과 일치한다.
- 동일한 `(employee_id, store_id)` 접근 행이 여러 개 존재하지 않는다.

`employee_store_access`에는 `(employee_id, store_id)` 유니크 제약이 없으므로 단순 `INSERT`를 반복 실행하면 중복 행이 생길 수 있다.

## 송도학원가점 요청

- 요청일: 2026-07-21
- 근거: [Slack 요청 및 스레드](https://w1622455415-twy380170.slack.com/archives/C0A0H4MNS1W/p1784594452259019)
- 매장: 송도학원가점 (`store.id = 42`)
- 요청 관리자: Green, Jessie, Sia, Jackie
- 실행 SQL: [`송도학원가점.sql`](./송도학원가점.sql)

2026-07-21 운영 DB 사전 검증 결과:

- 매장과 OWNER 계정은 이미 생성돼 있다.
- OWNER `employee.id = 79`의 매장 접근 권한은 `ACTIVE`다.
- 네 관리자 계정은 모두 `MANAGER`, `ACTIVE`다.
- Green(`13`), Jessie(`16`), Sia(`33`), Jackie(`73`) 모두 송도학원가점의 매장별 접근 행이 없다.
- Jackie는 `is_all_store_access = 1`이지만, 기존 운영 데이터에서는 다른 매장에도 매장별 접근 행을 함께 보유한다. 이번 요청도 네 명 모두 동일하게 추가한다.

## 완료 검증

```sql
SELECT
    e.id AS employee_id,
    e.name,
    e.role,
    e.is_all_store_access,
    e.status AS employee_status,
    esa.id AS access_id,
    esa.status AS access_status,
    esa.created_at
FROM employee e
LEFT JOIN employee_store_access esa
    ON esa.employee_id = e.id
   AND esa.store_id = :store_id
WHERE e.id IN (:employee_ids)
ORDER BY e.id, esa.id;
```

각 직원별로 `ACTIVE` 접근 행이 정확히 1개인지 확인한다.
