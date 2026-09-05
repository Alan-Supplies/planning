## 개요
장부대장에 있는 매장이름과 구글 시트 탭이름을 매핑한다.

### 문제점
- AsIs
  store.name 과 매핑하는데 store name이 외부로 노출되는 이름이라 관리 포인트가 다르다.
- ToBe
  store.name과 별도 관리

### 판단
- `store.name`은 외부 노출용 표시명이다.
- 장부대장의 매장명과 구글 시트 탭 이름은 운영자가 수동 관리한다.
- 이전에는 `store.name`과 같았지만 이미 값이 틀어진 상태이고, 초기 입력 오류나 표시명 변경으로 다시 틀어질 가능성이 있다.
- 매핑 실패는 단순 누락이 아니라 매출 데이터 오적재로 이어질 수 있다.

따라서 매출시트 매핑은 `store`의 책임으로 두지 않는다.
매출시트 연동 설정은 별도 관리하고, 코드 배포 없이 운영자가 변경할 수 있어야 한다.

### 매핑 기준
구글 시트 입력 과정의 핵심 매핑은 다음과 같다.

```text
jangbuName -> sheetTabName
```

`storeId`는 구글 시트 입력 과정에서 직접 사용하지 않는다.
다만 추후 내부 매출 대조나 운영상 추적에 활용할 수 있으므로 설정값에 함께 둔다.

```json
{
  "storeId": 12,
  "jangbuName": "강남점",
  "sheetTabName": "강남역점"
}
```

### 저장 방식
매출시트 매핑만을 위한 독립 테이블은 현재 범위에 비해 작다.
대신 MySQL에 `configs` 또는 `settings` 성격의 범용 설정 테이블을 두고, `namespace`와 `key`를 컬럼으로 분리해서 관리한다.

예시:

```json
{
  "namespace": "preppers",
  "key": "sales-sheet-mappings",
  "value": [
    {
      "storeId": 12,
      "jangbuName": "강남점",
      "sheetTabName": "강남역점"
    }
  ]
}
```

테이블 형태:

```sql
CREATE TABLE configs (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  namespace VARCHAR(64) NOT NULL,
  `key` VARCHAR(128) NOT NULL,
  value JSON NOT NULL,
  description VARCHAR(255) NULL,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
  PRIMARY KEY (id),
  UNIQUE KEY uq_configs_namespace_key (namespace, `key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

### 새 DB 여부
새 DB를 만드는 것보다는 기존 MySQL DB에 `configs` 테이블을 추가하는 방향이 좋다.

이 설정은 매출시트 연동을 위한 운영 설정이고, 현재 주문/매출 관련 진실의 원천은 MySQL로 정리되어 있다.
별도 DB를 만들면 설정 하나를 위해 연결 정보, 권한, 배포, 백업, 장애 대응 지점이 늘어난다.

새 DB는 다음 조건이 생길 때 다시 검토한다.

- 여러 서비스가 공통 설정 저장소로 사용해야 한다.
- 운영 설정을 도메인 DB와 물리적으로 분리해야 하는 보안/권한 요구가 있다.
- 설정 변경 이력, 승인 플로우, 롤백 등 별도 관리 시스템이 필요해진다.

### TypeORM Entity
엔티티 예시는 [`config.entity.ts`](./config.entity.ts)에 둔다.
