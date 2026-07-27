# ArgoCD/GitOps 퀴즈 복습 노트

대상 문서:
- `suppliesfitness/preppers-order-server` `feature/TECH-147/argocd-chart` 브랜치 `docs/deployment/*` (파일럿 설계+runbook, 2026-07-14~16)
- `suppliesfitness/platform-gitops`(현재 최신/단일 소스) `docs/deployment/*` (파일럿 이후 실제 진행, 2026-07-17~21):
  `gitops-아키텍처-primer.md`, `order-server-gitops-후속-runbook.md`, `AppProject설계-TECH-145.md`,
  `gitops-prod-선행결정-C-E-F.md`, `gitops-prod-스탠드업-runbook.md`, `platform-iac-gitops-전환-분석.md`

---

## 1. 정확히 몰랐거나 헷갈렸던 것 (본인이 답한 것 vs 정확한 내용)

### 1-1. Helm vs Kustomize 선택 근거
- 답: "여러 프로젝트로 확장 가능해서"
- 정확: 8개 워크로드(백엔드5+클라이언트3)가 `Deployment+Service+Ingress+HPA` 구조로 **거의 동형**이라,
  템플릿 1개+values N개로 **중복 최소화**가 핵심 근거. 확장성은 그 결과로 따라오는 부수 효과.

### 1-2. Kustomize에서 image.tag 변경 빈도
- 질문: "kustomize에선 태그를 계속 바꿀 일이 많은가?"
- 정확: 태그 변경 빈도(매 빌드)는 Helm/Kustomize와 무관 — GitOps 자체 특성. 달라지는 건 "어디를 고치는가"
  (Helm=`values.yaml` 한 줄 / Kustomize=`kustomization.yaml`의 `images:` 필드).

### 1-3. Push(kubectl) vs Pull(GitOps) 배포 모델
- "이전 kubectl에선 이런 작업(태그 커밋)이 없었는데?" → 처음엔 차이를 몰랐음.
- 정확: 예전=CI가 빌드 후 곧장 `kubectl apply`(push, CI가 클러스터 직접 조작).
  GitOps=ArgoCD가 git만 보고 동기화(pull), CI는 git에 값만 커밋. 파일럿 기간엔 `default`(구)와
  `preppers-dev`(신)가 **병행** 운영됨.

### 1-4. Pull 방식을 쓰는 이유
- 답: "이미지 생성과 파드 관리를 분리하기 위해서" → **정확** (관심사 분리).
- 추가로 확인한 부수 이점: CI 클러스터 권한 축소, git=배포 이력/PR 승인 게이트, 롤백=git revert,
  드리프트 자동 복구(selfHeal).

### 1-5. app/prereqs Application을 둘로 나눈 이유
- 답: "나중에 TF로 이관할 것들을 분리해서 이전에 유리하게" → 소유권 경계 이유는 **정확**.
- 놓친 부분: 이유가 하나 더 있음 — "소스 타입이 다름"(app=Helm 차트, prereqs=raw 매니페스트).
  Application 하나는 소스 하나만 가능해서 애초에 못 합침.

### 1-6. 네임스페이스 스코프 ↔ prereqs의 platform-iac 이관 (가장 헷갈렸던 지점, v1)
- "namespace 다르면 공유 못한다면서 → 그럼 TF로 못 넘기는 거 아니냐"는 혼동 발생.
  본인이 직접 인정: "어떻게 넣는지를 정확히 이해 못하고 있었어"
- 정확: "어디 있어야 하나(네임스페이스 스코프)"와 "누가 만드나(ArgoCD냐 Terraform이냐)"는 별개 문제.
  Terraform은 클러스터 밖 도구라 스코프 제약을 안 받고, 한 `apply`로 여러 ns에 각각 리소스를 동시에
  만들 수 있음(`default`용은 이미 platform-iac가 하고 있었음).

### 1-7. Helm 템플릿 `{{- ... -}}` 문법
- 안 읽혀서 어려워함. `-`는 로직이 아니라 **공백/줄바꿈 제거**(whitespace control)용이라는 걸 몰랐음.
- 팁: 로직 파악할 땐 `-` 무시하고 키워드(if/with/range/end)만 읽기. 결과가 궁금하면
  `helm template ...`로 렌더링해서 순수 YAML로 확인하는 게 가장 빠름.

### 1-8. ArgoCD 대시보드 보안
- "admin 비밀번호가 있어도 위험한 거구나" → **정확한 직관**.
- 이유: 비밀번호는 최소 방어선일 뿐, MFA 없음/브루트포스 취약/공유계정이라 감사 불가 등의 한계.
  네트워크 격리(사내 ALB/VPN)+SSO(OIDC)+RBAC를 추가로 쌓아야 함.

### 1-9. GitOps의 "진짜 동작 방식" — ArgoCD가 무엇을 보는가
- 답: "image-updater가 ecr을 보고 있다" → **다른 감시자와 혼동**.
- 정확: 이 프로젝트엔 감시자가 두 개 있음 — ① **ArgoCD가 git을 본다**(일반 GitOps 정의, push가
  트리거가 아니라 ArgoCD가 git을 관찰하다 당겨와서 반영) ② **Image Updater가 ECR을 본다**(그 앞단에
  붙은 별개 다리: ECR→git write-back). 질문의 핵심은 ①이었는데 ②로 답함.
- 추가 확인: "git이 ArgoCD 웹훅을 호출할 텐데" → 맞음. 다만 **webhook은 "확인해봐"라는 트리거 알림일 뿐**,
  실제로 뭐가 바뀌었는지는 ArgoCD가 스스로 git을 다시 읽어서(pull) 판단 — 그래서 webhook을 쓰든 안 쓰든
  "pull 기반"이라는 원리 자체는 안 바뀜.

### 1-10. 부트스트랩 역설 (ArgoCD 자신은 누가 만드나)
- 답: "argocd는 terraform으로 설치하고, root는 어느 경로를 읽어야 할지 지정한다" → **둘 다 정확**.
- 보완: root.yaml 자체도 "딱 한 번" 수동 kubectl apply가 필요(씨앗 심기) — 그 이후부터는 완전히
  자동(GitOps)으로 넘어감. "처음(0→1)엔 IaC+수동 개입, 그 다음(1→N)은 GitOps"라는 경계가 핵심.

### 1-11. 인식 체인 — 안 만든 파일이 왜 클러스터에 뜨는가
- 답: "root.yml이 찾는다" → **정확**하지만 뒤이어 좋은 질문: "그 전에 root가 git을 읽어오는 건가?"
- 정확: root도 결국 **그냥 하나의 Application**일 뿐이라 ArgoCD Application 컨트롤러가 다른 앱과
  똑같이 git을 pull함. 다만 `recurse:true`라서 그 폴더 안의 하위 파일(appset 등)도 "그냥 배포할
  리소스"로 취급해 적용 → 그렇게 만들어진 ApplicationSet을 ApplicationSet 컨트롤러가 이어받아 처리.
  즉 root가 특별한 게 아니라 "이 폴더 전체가 내 관할"이라고 선언된 앱일 뿐, 같은 pull 매커니즘이
  재귀적으로 이어지는 구조.

### 1-12. sync 모드 3가지 (automated / 수동 / freeze) — ⚠️ 내 질문 설계 실수
- 답: "automated: 주기적으로 동기화 / 수동: 동기화 안하지만 꺼지면 복구 / freeze: 아무 조치 없음.
  근데 freeze는 문서에 없지 않나?" → **freeze는 실제로 문서에 있었음**(primer 5번 섹션에 표로 명시).
- 정확한 동작: automated=git변화 자동반영+**수동변경도 자동으로 되돌림**(단순 주기 동기화 그 이상).
  수동=차이만 감지, 사람이 Sync 눌러야 반영(수동변경이 그대로 유지, "꺼지면 복구"는 아님).
  freeze=원래 automated였던 걸 "잠깐 끄는" patch.
- **본인이 제기한 좋은 지적**: "수동과 freeze는 결과(동작)가 똑같은데 왜 구분해서 물었나, 질문이
  적절했는지 모르겠다" → **타당한 비판**. 실제로 런타임 동작 기준으론 2가지뿐(자동/비자동)이고
  수동·freeze는 동작이 동일함. 진짜 차이는 동작이 아니라 **"git이 뭐라고 말하는가"** — 수동은 git
  매니페스트 자체에 automated가 없는 **설계 상태**(git과 일치), freeze는 git엔 여전히 automated:true라고
  적혀있는데 **클러스터의 라이브 객체만 임시로 patch**한 것(git과 불일치, 사고대응용 임시 부채,
  되돌려야 함이 명시적으로 추적됨). → 다음엔 "실제로 차이가 존재하는 것"만 비교 질문으로 낼 것.

### 1-13. ArgoCD와 별개로 불량 이미지를 검출하는 방법
- 답: "잘못된 이미지를 불러오거나 실패할 수 있다" → 결과는 맞지만 **원인(사람이 태그를 손으로
  입력하다가 실수)까지는 못 짚음**.
- 정확: 실제 사고는 `image_tag`에 prefix 누락/오타 등 **수동 입력 실수**가 반복(문서: "다발"). 워크플로우가
  ECR에 그 태그가 실제 존재하는지 검증을 안 해서 배포 단계에서야 실패(ImagePullBackOff). 해법은 사람의
  입력 단계 자체를 없애는 것(Image Updater). 그 외 ArgoCD와 별개인 검출 방법: ①CI에서 빌드 직후
  컨테이너 실행+healthz 스모크 테스트(이번 dotenv 사고의 근본 해법) ②이미지 취약점 스캔(성격 다름,
  로직 버그는 못 잡음) ③Argo Rollouts 같은 progressive delivery(카나리 배포+자동 메트릭 분석+자동 롤백).

### 1-14. GitOps 웹훅 시크릿은 bootstrap(IaC)부터 준비돼야 함 — 본인이 스스로 짚은 갭
- 본인 발언: "이 부분을 놓쳤다."
- 정확: webhook secret(`random_password.argocd_webhook`)은 GitOps가 아니라 **ArgoCD를 설치하는
  Terraform(`argocd.tf`)에서 helm_release.argocd의 `configs.secret.githubSecret`로 처음부터 같이 주입**됨.
  즉 root.yaml(GitOps 시작점)보다 먼저, ArgoCD 설치와 같은 시점(IaC)에 준비되는 항목.

### 1-15. webhook secret을 왜 GitOps가 아니라 IaC에서 만들어야 하나 (두 가지 이유)
- 답1: "GitOps는 쿠버네티스 설정만 관리, 환경변수는 관리 안 함" → **부정확**. GitOps(ArgoCD)는 Secret도
  잘 관리함(ESO로 이미 하고 있음). 진짜 이유는 "**git에 평문 비밀값을 커밋하면 안 된다**"는 원칙 —
  ESO는 git엔 "AWS SM의 이 항목 참조"만 적고 실제 값은 AWS에만 두는 방식이라 가능했던 것. 이 webhook
  secret은 그런 참조 체계 없이 Terraform이 랜덤값을 직접 helm 값으로 주입하는 방식이라, GitOps로
  넣으려면 SOPS 같은 별도 암호화 도구가 필요(지금 없음).
- 답2: "gitops는 푸시하면 동기화, 최초 1회 설정을 반복적으로 참조한다" → 방향은 있으나 불명확.
  정확: webhook의 역할 자체가 "git이 바뀌면 ArgoCD한테 빨리 알려주는 것"인데, 이 webhook 설정 자체를
  GitOps로 관리하면 "그 설정이 바뀌었다"는 신호를 빨리 알려줄 webhook이 아직 없는(혹은 막 만드는 중인)
  **닭-달걀 순환(자기참조)** 문제가 생김. 그래서 도구 자체(ArgoCD 인스턴스 계층)를 설치하는 IaC에서
  같이 만드는 게 자연스러움.

---

## 2. 다음에 이어서 물어볼 후보 (아직 정식으로 안 다룸)

- shared ArgoCD 승격(argocd-alan→argocd) 시 겪은 함정 2가지(Application finalizer, CRD 소유권) — 대화 중
  설명은 했지만 직접 질문/답변은 안 함
- APISIX 컷오버에서 왜 consumer는 안 옮기고 라우트만 옮겼는지
- AppProject 미적용 상태의 리스크(`project: default` = 무제한, 8개 앱 전부 해당)
- 클러스터 스코핑(모델 A) — 왜 각 클러스터 ArgoCD가 자기 도메인만 봐야 하는지
- prod 착수 전 선행 결정 C(AppProject)/E(consumer 소유)/F(prereqs 소유)가 서로 얽혀있는 이유
- platform-iac 전체를 GitOps로 안 옮기는 이유 (ArgoCD가 `terraform apply`를 못 한다는 것 등)
- 환경 차이를 디렉토리 대신 `values-<env>.yaml` 파일 접미사로 표현하는 이유
- 파일럿 CI 무한루프 방지 장치(`paths-ignore`, `[skip ci]`)

## 3. 메타 — 퀴즈 방식에 대한 본인 피드백 (기억해둘 것)

- "결과가 똑같은 두 개념을 비교하라"는 질문은 혼란을 줌. 실제로 차이가 있는 지점만 질문할 것
  (동작 차이가 없으면 "의도/설계 차이"라고 명확히 묻는 질문으로 바꿀 것).
- 한 번에 여러 문제 대신 **한 문제씩** 진행하는 걸 선호함.
- 점수 매기기보다 **정확히 뭘 몰랐는지 짚어주는 것**이 목적.

---
작성: 2026-07-27
