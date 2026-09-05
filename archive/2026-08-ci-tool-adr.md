# 배경

ARGOCD를 적용하면서 CI, CD가 분리되었다.

좀 더 효율적인 CI 아키텍처 선택을 검토하게 되었다.

# 검토한 선택지

|  | A. CodePipeline 유지 | **B. CodeBuild Only** | C. GH Actions → CodeBuild | D. GH Actions로만 |
| --- | --- | --- | --- | --- |
| 서비스당 관리 리소스 | 2개 | 1개 | 2개 + 워크플로 파일 | 1개 |
| 환경변수 소유 | 2곳으로 분산 | 한 곳 | 2곳 | 1곳 |
| 필요 파일 | buildspec.yml | buildspec.yml | .workflows/*.yml
buildspec.yml | .workflows/*.yml |
| AWS 자격증명 | 불필요 | 불필요(기존 CodeConnection 재사용) | OIDC/IAM | OIDC/IAM |

# 결정

**D github action 결정
-** 현재 CodePipeline 만이 할 수 있는 기능을 사용하지 않는다.
**-** codebuild는 buildspec.yml과 codebuild 설정을 따로 관리해야 한다.
**-** 한곳에서 관리해서 리소스 분산을 줄일 수 있다.
- OIDC/IAM 기존 access-key 사용을 바꾸는 방식으로 쉽게 대체할 수 있다.

- 추가적인 팀원 의견

| 팀 의견 | 검증 |
| --- | --- |
| Austin — 동시 잡 60이면 충분 | ✅ 조직이 Team 플랜이고 Team 한도가 정확히 60. 최근 7일 일평균 56건이 하루 종일 분산되므로 여유 |
| Austin — 빌드 캐시 설정 간편 | ✅ 현재 CodeBuild는 **전 프로젝트 `NO_CACHE`**, buildspec에 `cache:` 블록 0건. GHA로 가면 오히려 빨라진다 |
| Austin — CodeBuild는 AWS 리소스 생성 수고 | ✅ 프로젝트 91개 중 **IaC 관리는 3개**. 88개가 콘솔 수기 관리 |
| Connor — Marketplace 생태계 | ✅ 조직 정책이 `allowed_actions: all` |
| Connor — migration 불필요 | ✅ buildspec 30개가 **템플릿 4종**뿐. `batch`·`reports`·`artifacts`·Parameter Store·커스텀 이미지 전부 미사용 |
| Alan — OIDC로 access_key→role | ✅ **OIDC provider가 이미 있다**(2026-07-28 생성). 모범적 신뢰 정책 롤 2개 가동 중 → 복제만 하면 된다 |

## 이후 해결해야할 과제

### **docker rate limit**

현재 볼륨은 여유가 크다 — 6일치 156빌드를 버킷팅하면 **1시간 슬라이딩 피크 23건**(평균 0.9건), 한도는 100이다.
하지만 이건 테스트가 돌지 않고 있어서다. 테스트가 돈다면 limit는 빠르게 차감 된다.

**해결 ECR Pass Through Cache**

`FROM node:22-alpine`. 대신 레지스트리 참조를 적는다.
<acct>.dkr.ecr.<region>.amazonaws.com/docker-hub/library/node:22-alpine 형태로 바꾼다.
build 이미지는 거의 바뀔 일이 없으므로 limit 차감이 거의 발생하지 않는다.

### self hosted runner

목적: VPC 내부 terraform plan & apply
관련PR: https://github.com/suppliesfitness/platform-iac/pull/103

**bastion vpc에 runner를 별도 EC2로 둔다.**

- bastion vpc는 이미 허브-스포크
SG를 추가로 수정할 필요 없다.

다른 선택지

1. vpc attached CodeBuild CodeBuild는 NAT 신설(월 $43) 필요
2. vpc lambda - 제약이 많음
실행시간, github long polling 안됨, /temp 스토리지 용량 문제(10GB)

# 영향

### 사전 준비

1. 러너 IAM롤 권한 축소
`AdministratorAccess` → 스택이 실제로 만지는 서비스로 한정
2. ECR Pull Through Cache rule 생성
3. Codebuild 환경변수 Github 으로 이관

### 이관

1. OIDC provider는 현재 있고 repo별 IAM 롤 추가
2. 중앙 워크플로 저장소에 공통 build.yml 들(serverless 별도) 작성
3. github action에서 사용중인 access_key_id를 OIDC로 대체
4. ECR PTC 적용 - Dockerfile `FROM` 치환
5. workflow 파일 교체 → codebuild, codepipeline 제거

### 실행후

access_key 사용처 확인후 폐기