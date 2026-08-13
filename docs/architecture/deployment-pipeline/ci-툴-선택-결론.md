# CI 툴 선택 — 결론

> 2026-08-12 · alan · 슬랙 `[CI 툴 선택의 시간]` 스레드 회신용
> 근거·실측 전문은 [ADR-0002](ADR002-ci-툴-선택.md)

---

## 결론

**GitHub Actions로 간다.** 팀 3인 만장일치이고, 실측이 이를 뒷받침한다.

단 "CodeBuild를 버린다"가 아니라 **"CI 제어 평면을 GHA가 소유한다"**가 정확하다. VPC가 필요한 잔여분은 self-hosted 러너가 받는다.

---

## 1. GHA의 장점

### 1-1. 팀이 꼽은 장점이 전부 실측으로 확인됐다

| 팀 의견 | 검증 |
|---|---|
| Austin — 동시 잡 60이면 충분 | ✅ 조직이 Team 플랜이고 Team 한도가 정확히 60. 최근 7일 일평균 56건이 하루 종일 분산되므로 여유 |
| Austin — 빌드 캐시 설정 간편 | ✅ 현재 CodeBuild는 **전 프로젝트 `NO_CACHE`**, buildspec에 `cache:` 블록 0건. GHA로 가면 오히려 빨라진다 |
| Austin — CodeBuild는 AWS 리소스 생성 수고 | ✅ 프로젝트 91개 중 **IaC 관리는 3개**. 88개가 콘솔 수기 관리 |
| Connor — Marketplace 생태계 | ✅ 조직 정책이 `allowed_actions: all` |
| Connor — migration 불필요 | ✅ buildspec 30개가 **템플릿 4종**뿐. `batch`·`reports`·`artifacts`·Parameter Store·커스텀 이미지 전부 미사용 |
| Alan — OIDC로 access_key→role | ✅ **OIDC provider가 이미 있다**(2026-07-28 생성). 모범적 신뢰 정책 롤 2개 가동 중 → 복제만 하면 된다 |

### 1-2. 지금 쓰는 장기 키를 없앤다

현재 `preppers-server` 등이 `secrets.AWS_ACCESS_KEY_ID`(장기 자격증명)로 AWS에 붙는다. OIDC 전환은 **선택이 아니라 부채 상환**이다.

---

## 2. 해결해야 할 문제

### 2-1. Docker Hub image pull rate limit — **해결법은 두 가지, 둘 다 이미 손에 있다**

현재 볼륨은 여유가 크다 — 6일치 156빌드를 버킷팅하면 **1시간 슬라이딩 피크 23건**(평균 0.9건), 한도는 100이다.

#### 해법 1 — 인증으로 한도를 늘린다

| | 미인증 | `docker login` 후 |
|---|---|---|
| 카운트 주체 | **IP 주소** (공유 IP면 남의 pull까지 합산) | **계정** |
| 한도 | 100 | 200 (Personal 무료) · **무제한** (Pro/Team/Business) |

**이미 대부분 적용돼 있다.** `docker build` 하는 buildspec 19개 중 **17개**가 `docker login -u gymboxx`를 `docker build` 바로 앞줄에서 실행한다. (ECR 로그인은 push용으로 별개다.)

- 남은 일: 미인증 **2개**(`slack-bot`, `web-socket-server`) 처리
- 확인할 것: `gymboxx` 계정 등급. 유료면 이미 무제한이다

#### 해법 2 — ECR Pass Through Cache

`FROM node:22-alpine`. 대신 레지스트리 참조를 적는다.
<acct>.dkr.ecr.<region>.amazonaws.com/docker-hub/library/node:22-alpine 형태로 바꾼다.
build 이미지는 거의 바뀔 일이 없으므로 limit 차감이 거의 발생하지 않는다.

> ⚠️ 수치는 문서를 믿지 말 것. `docs.docker.com`(100/6h)과 실서버 헤더(`100;w=3600` = 1시간)가 다르고, 윈도가 롤링인지 고정 리셋인지는 Docker가 문서화한 적이 없다. 아래로 직접 측정한다.

### 2-2. self-hosted runner
목적: VPC 내부 terraform plan & apply
관련PR: https://github.com/suppliesfitness/platform-iac/pull/103

bastion-vpc 안에 self-hosted EC2 러너 한 대를 둔다. 독립 실측으로 이 선택을 확인했다.

| 검증 항목 | 결과 |
|---|---|
| 피어링이 허브-스포크이고 **전이되지 않는다** | ✅ 확인. `supplies-eks-dev-vpc`에 두면 OpenSearch ALB 4개 중 **1개만** 도달 |
| bastion이 스포크 4개 경로를 갖는다 | ✅ `bastion-rtb-public`에 `172.16`·`172.31`·`10.8`·`10.20` 전부 존재 |
| 역방향 경로 | ✅ OpenSearch ALB 서브넷 전부에 `10.0.0.0/16` 존재 |
| ALB SG가 러너를 막는가 | ✅ 4개 전부 `443 from 0.0.0.0/0` — **SG 변경 불필요** |

runner는 별도의 EC2로 띄워서 보안 분리

다른 선택지
1. vpc attached CodeBuild CodeBuild는 NAT 신설(월 $43) 필요
2. vpc lambda - 제약이 많음
  실행시간, github long polling 안됨, /temp 스토리지 용량 문제(10GB)

