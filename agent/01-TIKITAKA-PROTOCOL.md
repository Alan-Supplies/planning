# 티키타카 프로토콜 (런북)

> 두 에이전트가 "대화"하는 게 아니라 **검증 가능한 핑퐁**을 한다.
> 매 라운드는 잡담이 아니라 계약/코드의 **diff** 를 산출한다.

## 상태 기계

```
        ┌────────────┐
        │  PROPOSE   │  (iac 또는 gitops)
        └─────┬──────┘
              ▼
     ┌──────────────────┐   fail
     │ VALIDATE (schema)│──────────┐
     └────────┬─────────┘          ▼
        pass  │              ┌────────────┐
              ▼              │  OBJECT    │  (근거: 필드/회색지대 행)
        ┌──────────┐         └─────┬──────┘
        │  ACCEPT  │               │
        └────┬─────┘   근거가 표에 │ 있음 → 상대가 수정 후 재 PROPOSE
             │         근거가 표에 │ 없음 ↓
             ▼                     ▼
      계약/코드 merge      ┌──────────────────┐
                          │ ESCALATE→arbiter │→ DECISION + 계약 diff → 재 PROPOSE
                          └──────────────────┘
```

## 라운드 규칙

각 라운드는 아래 4개 필드로만 표현한다 (자유서술 금지):

| 필드 | 내용 |
|---|---|
| `actor` | `iac` \| `gitops` \| `arbiter` |
| `action` | `PROPOSE` \| `ACCEPT` \| `OBJECT` \| `ESCALATE` \| `DECISION` |
| `diff` | 계약 파일 / Application / TF 의 실제 diff (없으면 라운드 무효) |
| `basis` | OBJECT·DECISION 시 필수: 위반한 **계약 필드명** 또는 **회색지대 행** 또는 arbiter **원칙 번호** |

## 단계별 상세

### 1. PROPOSE
- 변경을 제안하는 쪽이 diff 를 낸다.
- iac 의 PROPOSE 는 보통 `PlatformContract` 갱신, gitops 의 PROPOSE 는 Application/values 갱신 또는 "workloadIdentity 요청".

### 2. VALIDATE
- 상대는 먼저 diff 를 **스키마로 검증**한다:
  ```bash
  npx ajv-cli validate -s contract/platform-contract.schema.json -d contract/your.contract.json
  ```
- 스키마 실패면 곧장 OBJECT (basis = 실패한 필드).

### 3. ACCEPT / OBJECT
- **ACCEPT**: 스키마 통과 + MUST-NOT-TOUCH 침범 없음 + 회색지대 배정과 일치 → merge.
- **OBJECT**: 위 중 하나라도 위반. `basis` 에 반드시 근거를 명시.
  - 예: `basis: grayZone.crds=gitops 인데 iac 가 CRD 를 설치하려 함`

### 4. ESCALATE → arbiter
- OBJECT 의 근거가 **계약/표에 없을 때만** 발동 (즉 "규칙 자체가 없음").
- arbiter 는 `arbiter-agent.md` 원칙에 따라 **DECISION + 계약/표 diff** 를 낸다.
- 두 에이전트는 갱신된 계약을 입력으로 라운드를 재개한다.

## 종료 조건 (Definition of Done)
- 계약이 스키마를 통과하고,
- 회색지대 표에 떠다니는 항목이 0이고,
- 마지막 라운드가 `ACCEPT` 이며 merge 된 diff 가 존재.

## 오케스트레이션 (실전)
- 사람 또는 상위 오케스트레이터가 `PROPOSE` 를 어느 에이전트에 줄지 라우팅한다.
- `ESCALATE` 가 나오면 자동으로 `arbiter-agent` 를 호출하고, 그 `DECISION` 을 두 에이전트 컨텍스트에 주입 후 재개.
- 각 라운드 diff 는 PR/커밋으로 남겨 audit trail 을 만든다 — 이게 "책임 혼란" 재발을 막는 핵심.

## 안티패턴 (하지 말 것)
- ❌ diff 없는 라운드 (합의만 구두로).
- ❌ 두 에이전트가 회색지대 표를 직접 수정 (arbiter 전용).
- ❌ 계약 밖 서로의 내부 구현 참조.
- ❌ 근거(`basis`) 없는 OBJECT.
