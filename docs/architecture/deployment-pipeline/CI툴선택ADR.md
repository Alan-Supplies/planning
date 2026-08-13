# 배경

CI, CD가 분리되면서 좀 더 효율적인 CI 아키텍처 선택을 검토하게 되었다.

# 검토한 선택지

1. **codebuild**
codebuild 환경별 설정 + buildspec.yml
2. **github action**
    
    하나의 파일에서 관리 workflow/build.yml
    

# 결정

**B github action 결정**

| 팀 의견 | 검증 |
| --- | --- |
| Austin — 동시 잡 60이면 충분 | ✅ 조직이 Team 플랜이고 Team 한도가 정확히 60. 최근 7일 일평균 56건이 하루 종일 분산되므로 여유 |
| Austin — 빌드 캐시 설정 간편 | ✅ 현재 CodeBuild는 **전 프로젝트 `NO_CACHE`**, buildspec에 `cache:` 블록 0건. GHA로 가면 오히려 빨라진다 |
| Austin — CodeBuild는 AWS 리소스 생성 수고 | ✅ 프로젝트 91개 중 **IaC 관리는 3개**. 88개가 콘솔 수기 관리 |
| Connor — Marketplace 생태계 | ✅ 조직 정책이 `allowed_actions: all` |
| Connor — migration 불필요 | ✅ buildspec 30개가 **템플릿 4종**뿐. `batch`·`reports`·`artifacts`·Parameter Store·커스텀 이미지 전부 미사용 |
| Alan — OIDC로 access_key→role | ✅ **OIDC provider가 이미 있다**(2026-07-28 생성). 모범적 신뢰 정책 롤 2개 가동 중 → 복제만 하면 된다 |

# 영향

해결해야할 두가지 문제가 있다.

## docker rate limit

현재 볼륨은 여유가 크다 — 6일치 156빌드를 버킷팅하면 **1시간 슬라이딩 피크 23건**(평균 0.9건), 한도는 100이다.
하지만 이건 테스트가 돌지 않고 있어서다. 테스트가 돈다면 limit는 빠르게 차감 된다.

### 해법 1 — 인증으로 한도를 늘린다

- docker login(personal) 으로 한도를 200으로 늘릴 수 있다.
- 팀플랜을 구독하면 무제한이다.

#### 해법 2 — ECR Pass Through Cache

`FROM node:22-alpine`. 대신 레지스트리 참조를 적는다.
<acct>.dkr.ecr.<region>.amazonaws.com/docker-hub/library/node:22-alpine 형태로 바꾼다.
build 이미지는 거의 바뀔 일이 없으므로 limit 차감이 거의 발생하지 않는다.

## self hosted runner

목적: VPC 내부 terraform plan & apply
관련PR: https://github.com/suppliesfitness/platform-iac/pull/103

**bastion vpc에 runner를 별도 EC2로 둔다.**

- bastion vpc는 이미 허브-스포크
다른 vpc의 SG를 수정할 필요 없다.

다른 선택지

1. vpc attached CodeBuild CodeBuild는 NAT 신설(월 $43) 필요
2. vpc lambda - 제약이 많음
실행시간, github long polling 안됨, /temp 스토리지 용량 문제(10GB)

# 관련 문서