# ADR: BigQuery 기반 실시간 매출 데이터 반영 아키텍처

- 상태: 채택
- 결정일: 2026-08-13

# 배경

현재 데이터 자산화는 Lakehouse → Warehouse → Mart 구조로 구성하며, Lakehouse와 Warehouse 모두 BigQuery를 사용한다. 실시간 정보에 대한 요구가 있을 것을 대비해서 (예를 들어 현재 시간대 매출) 반영할 수 있는 방법을 검토 한다. 가능한 아키텍처를 모두 검토하면 원본 이벤트 스트림, 운영 DB CDC, Lakehouse 증분, Warehouse 증분 및 이벤트 발행 등 경우의 수가 지나치게 많아진다.
그래서 다음과 같은 제한을 두고 찾는다.
- 실시간은 수초 단위가 아니라 **1~5분 이내 반영되는 준실시간**을 의미한다. 
- Warehouse를 SSOT로 사용하고, 결제 승인·취소·환불 등 모든 상태 변화는 기존 행을 수정하거나 삭제하지 않고 고유한 이벤트 행으로 추가한다.
- 원본 이벤트 시스템이나 운영 DB에서 직접 데이터를 받는 방식은 이번 범위에서 제외한다.

# 검토한 선택지

- **A안: Warehouse 증분 조회 후 Mart 갱신**  
BigQuery Warehouse의 적재 시각, 이벤트 시각 또는 처리 커서를 기준으로 변경분을 주기적으로 조회하고 집계 결과를 `MERGE`한다. SSOT에서 직접 계산하므로 지표 정의와 정합성을 관리하기 쉽고 1~5분 마이크로배치 구현이 단순하다. 반면 스케줄 주기만큼 지연이 발생하며, 커서·중복 처리·실패 후 재실행을 직접 관리해야 한다.

- **B안: Warehouse Continuous Query 기반 연속 처리**  
append-only Warehouse 테이블의 신규 행을 BigQuery `APPENDS()`와 Continuous Query로 지속 처리하여 실시간 Mart에 반영하거나 Pub/Sub으로 발행한다. 신규 데이터 반영 지연을 줄일 수 있고, 수정·삭제가 없는 이벤트 모델과 잘 맞는다. 반면 취소·환불도 반드시 별도 보정 이벤트로 기록해야 하며, 고유 `event_id`, 멱등성, 늦게 도착한 이벤트의 원래 시간대 반영, 재처리 및 장애 복구 정책이 필요하다. Pub/Sub을 사용하면 전송과 소비 계층의 운영 복잡성과 비용도 추가된다.

- **C안: Lakehouse 변경분에서 실시간 Mart 생성**  
Warehouse 적재를 기다리지 않고 BigQuery Lakehouse의 신규 데이터를 증분 또는 연속 처리한다. Warehouse 반영 지연이 큰 경우 더 빠른 잠정값을 만들 수 있고 원본 보존과 재처리가 쉽다. 그러나 Warehouse SSOT와 별도 계산 경로가 생겨 잠정값과 확정값의 대사·보정이 필요하며, 동일 지표 로직을 두 경로에서 유지할 가능성이 있다.

- **D안: 원본 이벤트 또는 운영 DB 직접 처리** — Pub/Sub 원본 이벤트나 DB CDC를 직접 받아 가장 낮은 지연시간을 달성할 수 있다. 하지만 이번 목표인 1~5분 SLA에는 과도하며, 데이터 수집과 분석 처리 경로가 분리되어 운영 복잡성 및 정합성 관리 비용이 커진다. 이번 검토 범위에서는 제외한다.

# 결정

**BigQuery Warehouse를 SSOT이자 실시간 처리의 기본 원천으로 사용하고, append-only 이벤트 테이블을 Continuous Query로 처리하여 운영용 실시간 Mart를 생성한다.**
예를 들어 결제 승인·취소·부분 환불 등 모든 상태 변화는 새 이벤트 행으로 기록하며 기존 이벤트 행은 수정하거나 삭제하지 않는다.

Continuous Query는 Warehouse에 새로 추가된 행을 `APPENDS()`로 읽는다. 단순 집계는 BigQuery 안에서 처리하고, 여러 소비자에게 이벤트 전달이나 별도 애플리케이션 처리가 필요한 경우에만 Pub/Sub 발행을 추가한다. 초기에 Pub/Sub을 필수 구성요소로 두지 않는다.

현재 시간대 매출은 `매장 × 영업일 × 시간대 × 채널` 단위의 **잠정값**으로 제공한다. 늦게 도착한 이벤트와 보정 이벤트를 반영해 해당 시간대를 다시 계산하고, 영업 마감 기준을 통과하면 동일한 Warehouse 상세 이벤트에서 재집계한 값을 **확정값**으로 전환한다. 잠정값과 확정값은 서로 다른 원천이 아니라 동일한 SSOT에서 계산 시점과 확정 상태만 다르게 한다.

Warehouse가 향후 1~5분 데이터 신선도 SLA를 충족하지 못하는 것이 측정으로 확인될 때만 Lakehouse 직접 처리 경로를 대안으로 도입한다. 수초 단위 장애 감지나 즉시 자동 대응이 필요해질 경우에는 원본 이벤트 직접 처리 방식을 별도의 ADR에서 재검토한다.

# 영향

- 실시간 Mart와 확정 Mart가 동일한 Warehouse 이벤트를 사용하므로 지표 정의와 최종 정합성 관리가 단순해진다.
- Warehouse 도착 이전의 데이터는 실시간 화면에 표시할 수 없으며, 전체 지연시간은 원천에서 Warehouse까지의 적재 지연을 포함한다.
- BigQuery Continuous Query용 컴퓨팅 리소스와, 선택적으로 Pub/Sub을 추가할 경우 메시징 비용이 발생한다.
- 
### 보완해야할 것
- Continuous Query 장애에 대비해 체크포인트, 모니터링, 재시작 및 기간 재처리 절차를 마련해야 한다.
- 중복 전달이나 재실행에도 집계값이 중복되지 않도록 `event_id` 기반 멱등성을 보장해야 한다.
- 늦게 도착한 이벤트는 적재 시각이 아니라 발생 시각과 영업일 기준으로 원래 집계 구간에 반영해야 한다.
- 현재 시간대 값에는 `잠정`, 기준 시각, 데이터 최신 시각을 표시하고 마감 후 `확정` 상태로 전환한다.


# 관련 문서

- [BigQuery Continuous Query](https://cloud.google.com/bigquery/docs/continuous-queries-introduction)
- [BigQuery APPENDS 함수](https://cloud.google.com/bigquery/docs/reference/standard-sql/time-series-functions#appends)
- [BigQuery에서 Pub/Sub으로 데이터 내보내기](https://cloud.google.com/bigquery/docs/export-to-pubsub)
- [BigQuery 변경 이력](https://cloud.google.com/bigquery/docs/change-history)
