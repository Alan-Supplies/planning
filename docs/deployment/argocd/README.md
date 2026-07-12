# 목적
아르고 CD 맛보기

## 로컬 쿠버네티스 설치
1. docker 데몬필요(맥은 docker desktop)
1. brew install kind
2. kubectl create namespace argocd
3. argocd 설치
  kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
4. 포트포워딩
  kubectl port-forward svc/argocd-server -n argocd 8080:443
5. admin 비밀번호 확인
6. 비밀번호 확인
  kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
  -> Y2VD0LJFILg3KmYh
7. http://127.0.0.1:8080  
  <img src="image/argocd-gateway.png" width="200" />
8. 로그인
  admin / 비밀번호  
  <img src="image/argo-main.png" width="200" />

## cli 설치
1. brew install argocd
2. argocd login localhost:8080 --username admin --password Y2VD0LJFILg3KmYh --insecure

## 샘플 앱 사용
1. argocd app create guestbook \
  --repo https://github.com/argoproj/argocd-example-apps.git \
  --path guestbook \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace default
2. argocd app sync guestbook  
  <img src="image/application상세.png" width="200" />

3. replica 늘려보기
  kubectl scale deployment guestbook-ui --replicas=2
  -> OutOfSync
  sync로 레포 설정으로 되돌릴 수 있음
4. auto sync 켜보기
  argocd app set guestbook --sync-policy automated --self-heal
  레포와 설정이 안맞으면 곧 자동 복구

## AWS 적용
1. argocd.tf
2. terraform apply -target=kubernetes_namespace.argocd_alan -target=helm_release.argocd_alan
3. password 확인
   kubectl --context supplies-eks-dev -n argocd-alan get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
   9F2iWgTpkK8c7s7V
4. login
   argocd login localhost:8081 --username admin --password 9F2iWgTpkK8c7s7V --insecure
5. repo 등록
   argocd repo add git@github.com:Alan-Supplies/argocd-example-apps.git \
  --ssh-private-key-path ~/.ssh/argocd_alan
  주의: argocd용 키는 passphrase 없어야 한다. 새로 등록
6. 확인
  argocd repo list
7. app 생성
    ```bash
    argocd app create guestbook-alan \
    --repo https://github.com/Alan-Supplies/argocd-example-apps.git \
    --path guestbook \
    --dest-server https://kubernetes.default.svc \
    --dest-namespace argocd-alan \
    --sync-policy automated
    ```
8. 예제앱으로 스케일업하기
  guestbook-ui-deployment.yaml에서 replicas 수정
  안됨
  -> 폴링 주기 3분
9. 강제 리프레시
  argocd app get guestbook-alan --refresh



## 웹훅 연결 (GitHub → ArgoCD 자동 동기화) — 런북

> **관련 이슈**: [TECH-127 ARGOCD 웹훅 연결](https://linear.app/suppliesfitness/issue/TECH-127/argocd-웹훅-연결) (상위: TECH-126)
> **목적**: 현재는 폴링 주기(기본 3분)마다만 repo 변경이 반영됨(위 "AWS 적용" 8~9번 참고).
> GitHub push webhook을 붙여 **커밋 즉시 refresh/sync**가 트리거되게 한다. (폴링은 백업으로 계속 동작)
> **대상 repo**: `Alan-Supplies/argocd-example-apps` · **환경**: `supplies-eks-dev` context / `argocd-alan` namespace

### 사전 준비 (체크)
- [ ] `kubectl --context supplies-eks-dev -n argocd-alan get pods` — argocd-server Running 확인
- [ ] `argocd-example-apps` repo의 GitHub Settings → Webhooks **관리 권한** 보유
- [ ] argocd-server로의 port-forward 터미널 하나 유지 (아래 3-1에서 사용)
- [ ] 공개 노출 도구 준비 (`brew install ngrok`, 계정/authtoken 등록)

### 핵심 개념 (1분)
- ArgoCD의 webhook 수신 엔드포인트는 고정: **`<argocd-host>/api/webhook`**
- GitHub은 인터넷에서 이 URL로 POST를 보냄 → **port-forward(localhost)로는 도달 불가**, 공개 URL이 반드시 필요
- 서명 검증용 secret은 `argocd-secret`의 `webhook.github.secret` 키에 저장하고, **GitHub webhook의 Secret과 동일**해야 함

### 절차

**1. 웹훅 시크릿 생성**
```bash
WEBHOOK_SECRET=$(openssl rand -hex 20)
echo "$WEBHOOK_SECRET"   # ← 이 값을 아래 4번 GitHub Secret 칸에 그대로 붙여넣기
```

**2. argocd-secret에 시크릿 등록**
```bash
kubectl --context supplies-eks-dev -n argocd-alan patch secret argocd-secret \
  --type merge -p "{\"stringData\":{\"webhook.github.secret\":\"$WEBHOOK_SECRET\"}}"
# argocd-server가 즉시 못 읽으면 한 번 재기동
kubectl --context supplies-eks-dev -n argocd-alan rollout restart deploy/argocd-server
```

**3. ArgoCD server를 공개 URL로 노출 (임시 = ngrok)**
> port-forward만 있는 현 상태에서 내일 바로 테스트하기 위한 임시 경로입니다.
> 정식 노출(Ingress/LB)은 아래 "후속 과제" 참고 — TECH-147과 연계.

3-1. 터미널 A — port-forward 유지 (argocd-server는 443/https)
```bash
kubectl --context supplies-eks-dev -n argocd-alan port-forward svc/argocd-server 8081:443
```
3-2. 터미널 B — ngrok으로 https 터널 오픈
```bash
ngrok http https://localhost:8081
# 출력된 Forwarding URL 확인:  https://xxxx.ngrok-free.app
```
> ⚠️ argocd-server는 self-signed 인증서라 ngrok이 업스트림 TLS 검증에 실패할 수 있음.
> 그럴 땐 `ngrok http https://localhost:8081 --host-header=rewrite` 시도, 또는 트러블슈팅 참고.
> ⚠️ 무료 ngrok은 재실행 시 URL이 바뀌므로, GitHub webhook URL도 그때마다 갱신해야 함.

**4. GitHub webhook 등록**
`argocd-example-apps` repo → **Settings → Webhooks → Add webhook**
- **Payload URL**: `https://xxxx.ngrok-free.app/api/webhook`  ← 3-2 URL + `/api/webhook`
- **Content type**: `application/json`
- **Secret**: 1번에서 만든 `$WEBHOOK_SECRET` 값
- **SSL verification**: Enable (ngrok https면 유효)
- **Which events**: *Just the push event*
- **Active** 체크 → Add webhook

### 검증
1. GitHub webhook 화면 → **Recent Deliveries** 에서 방금 ping이 **200 OK** 인지 확인
2. argocd-server 로그에서 수신 확인
   ```bash
   kubectl --context supplies-eks-dev -n argocd-alan logs deploy/argocd-server | grep -i webhook | tail
   ```
3. **실제 push 테스트**: `argocd-example-apps`의 `guestbook` 매니페스트를 살짝 수정(예: replicas)하고 push
   → 폴링 3분을 **기다리지 않고** guestbook-alan 앱이 곧바로 OutOfSync 감지/동기화되는지 확인
   ```bash
   argocd app get guestbook-alan   # SYNC STATUS 및 최근 reconcile 시각 확인
   ```

### 트러블슈팅
| 증상 | 원인/조치 |
|---|---|
| GitHub Recent Deliveries가 4xx/타임아웃 | Payload URL 오타(`/api/webhook` 누락), ngrok 터널 끊김 → URL 재확인 |
| 401/403 서명 오류 | GitHub Secret ≠ `webhook.github.secret`. 1~2번 값 재확인 후 argocd-server 재기동 |
| 200인데 sync 안 됨 | webhook의 repo URL과 ArgoCD 등록 repo URL 불일치. `argocd repo list`로 등록 URL 확인(https/ssh 형태 무관하게 호스트/경로 일치해야 함) |
| ngrok TLS 오류 | `--host-header=rewrite` 추가 시도, 또는 argocd-server를 insecure(http)로 노출 후 http 터널 |

### 후속 과제
- ngrok은 임시. **정식은 Ingress/LB로 argocd-server 고정 도메인 노출** 후 그 URL로 webhook 재설정 → TECH-147(환경별 구조), TECH-145(App Project 설계)와 연계
- 완료 후 TECH-127 상태 갱신 + `docs/일정관리/cycle1-todo.md` 체크박스 반영

### 기타
예제 깃헙
Alan-Supplies/argocd-example-apps
  