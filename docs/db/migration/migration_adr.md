---
title: 0020. DB 스키마 마이그레이션은 VPC 부착 CodeBuild 에서 실행한다
description: VPN 안 RDS 에 DDL 을 적용할 실행 위치로 self-hosted 러너 대신 환경별 VPC CodeBuild 를 택한다 — CodeBuild 미사용 방침의 예외와 그 경계
status: draft
classification: internal
---
# 0020. DB 스키마 마이그레이션은 VPC 부착 CodeBuild 에서 실행한다

## 배경

gymboxx-lib 은 스키마 변경을 손으로 쓴 SQL 에서 TypeORM 마이그레이션으로 옮기고, 머지 때 자동 적용하려 합니다.(TECH-2337 · TECH-2638). 자동 적용은 허용 목록(`CREATE TABLE` · `ADD COLUMN ALGORITHM=INSTANT` · `INSERT`)만 하고 나머지는 실행 전에 막습니다.

현재 migration을 실행할 곳이 없습니다. RDS 는 VPN 안이라 GitHub 호스티드 러너가 닿지 않습니다. 유일한 self-hosted 러너(`iac-runner`)는 AdministratorAccess 박스라 다른 레포의 CI 를 얹지 않는다는 판단이 이미 있다(0016).

빌드·배포 파이프라인은 CodeBuild 에서 GitHub Actions 로 옮겼습니다. 이 ADR 은 그 방침의 예외가 됩니다.

## 검토한 선택지

| 안 | 장점 | 단점 |
|---|---|---|
| **A. 환경별 VPC 부착 CodeBuild (채택)** | 상주 서버 없음, 실행마다 새 컨테이너. 워크플로가 AWS API(OIDC)로 시작하고 로그를 받아 옴. 기존 NAT·RDS SG 그대로 | CodeBuild 미사용 방침의 예외. 시작에 1~2분. 소스를 S3 로 넘기는 배선 |
| B. 환경별 self-hosted 러너(EC2) | 팀 표준(GitHub Actions) 그대로, 로그가 Actions 에 바로 | 환경마다 상주 EC2·패치·러너 등록. DB 자격증명을 다루는 호스트가 잡 간 격리 없이 상시 존재 |
| C. `iac-runner` 공유 | 추가 자원 0 | admin 자격증명 박스에 다른 레포 코드를 돌리게 된다(0016 이 피한 결합) |
| D. 클러스터 안 CronJob(pull) | 네트워크 변경 0 | 머지와 적용이 즉시 이어지지 않고, 실패가 PR·Actions 에 보이지 않음 |
| E. VPC Lambda | 상주 없음 | TypeORM·마이그레이션을 매번 패키징, 15분 제한 |

0016 이 CodeBuild 를 버린 이유(bastion-vpc 에서 ENI 가 공인 IP 를 못 받아 NAT 신설 필요, 여러 스포크 도달)는 여기 해당하지 않음. dev-vpc app 서브넷에는 NAT 가 있고, 닿아야 할 곳은 환경마다 RDS 하나.

## 결정

**DB 스키마 마이그레이션의 실행 위치는 환경별 VPC 부착 CodeBuild 로 합니다.** 범위는 DB 마이그레이션 실행 하나고 빌드·배포는 계속 GitHub Actions 입니다.

- 소스는 워크플로가 `npm ci` 까지 끝내 S3 로 넘깁니다. CodeBuild 는 GitHub·사설 npm 자격증명이 없습니다.
- DB 비밀번호는 CodeBuild 안에서만 Secrets Manager 로 푼다. 워크플로 OIDC role 은 소스 업로드·빌드 실행·로그 조회만 합니다.
- 프로젝트당 `concurrent_build_limit = 1` — 같은 마이그레이션을 두 번 적용하지 않도록 제한 합니다.
- 리소스는 쓰는 쪽이 소유한다(`stacks/<product>/lib-migration/<env>`).

현재 갤발서버는 임시로 적용돼어 있습니다.(platform-iac #522 · #523, gymboxx-lib `migrate-dev.yml`, 2026-10-15 첫 적용). 운영은 이 ADR 채택 뒤 같은 형태로 만들고 채택다지 않으면 대체안으로 진행합니다.

## 영향

얻는 것: 상주 서버 없이 머지합니다.

감수하는 것: CodeBuild 를 쓰는 예외가 발생합니다. 로그를 CloudWatch 를 거쳐 Actions 로 옮겨야 합니다.

다시 볼 조건: VPC 안에서 돌아야 하는 CI 작업이 다른 레포에도 생기면, 레포별 CodeBuild 를 늘리지 않고 공용 self-hosted 러너(안 B)를 다시 검토합니다.

## 관련문서
https://app.notion.com/p/supplies/CI-GHA-3bacac6c910d8026a0c9ceb4a74170ac?v=396cac6c910d80b08b6b000c2a1d2f31&source=copy_link