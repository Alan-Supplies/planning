# gymboxx prod 서비스 인수 런북 (서비스 1개당)

> 라이브 `default` 워크로드를 ArgoCD로 in-place 인수할 때 **서비스마다 반복하는 절차**.
> 설계·근거는 [온보딩 체크리스트](./gymboxx-prod-온보딩-체크리스트.md) / [시크릿 관리](./gymboxx-prod-시크릿-관리.md).
> 여기는 **확인할 것과 커맨드만.** 2026-07-30 `hq-server-prod`로 전 과정 1회 검증됨.

```bash
export CTX=arn:aws:eks:ap-northeast-2:699016088228:cluster/eks_prod
export REGION=ap-northeast-2
export SVC=hq-server          # apps/gymboxx/<SVC> 디렉터리 이름
export DEP=${SVC}-prod        # 라이브 Deployment 이름
export APP=gymboxx-${SVC}-prod
```

---

## 0. 선행 조건

```bash
# Secret 에 이 서비스가 쓸 키가 있는가 (없으면 새 파드가 CreateContainerConfigError)
kubectl get secret service-credentials -n default --context=$CTX -o jsonpath='{.data}' | jq -r 'keys[]'
# Application 이 존재하고 OutOfSync 인가
kubectl -n argocd get app $APP --context=$CTX
```
- [ ] 참조할 키가 목록에 있다
- [ ] `SYNC STATUS = OutOfSync`, `HEALTH = Healthy`

---

## 1. 🚨 이미지 태그 재대조 (sync 직전, 매번)

**가장 잘 터지는 지점.** 실측 이후에도 prod 배포는 계속되므로 repo 태그가 금방 낡는다.
실제로 hq-server에서 하루 만에 2주 롤백 직전까지 갔다.

```bash
# ① Deployment 스펙 (values 와 대조할 기준)
kubectl get deploy $DEP -n default --context=$CTX \
  -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'

# ② 실제 떠 있는 파드 (롤아웃 중이면 ①과 다를 수 있음)
kubectl get pods -n default --context=$CTX -l app=$DEP \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[0].image}{"\n"}{end}'

# ③ ECR 최신 (①이 낡은 건 아닌지 역검증)
aws ecr describe-images --repository-name prod --region $REGION \
  --query "reverse(sort_by(imageDetails[?starts_with(imageTags[0],\`${DEP}-\`)],&imagePushedAt))[:3].{tag:imageTags[0],pushedAt:imagePushedAt}" \
  --output table

# ④ repo 값
grep -E '^  tag:' apps/gymboxx/$SVC/values-prod.yaml
```
- [ ] ①②③④가 **전부 같은 태그**
- [ ] 다르면 → `values-prod.yaml` 수정 → PR 머지 → 처음부터 다시

---

## 2. diff 확인

```bash
argocd app diff $APP
```
- [ ] 실질 변경이 **평문 → `secretKeyRef` 전환뿐**
- [ ] **`image:` 라인이 없다** (있으면 1번으로 복귀)

무시해도 되는 것: `argocd.argoproj.io/tracking-id`, Helm 표준 라벨(`app.kubernetes.io/*`, `helm.sh/chart`),
Service `name: http`.

> ⚠️ `argocd app diff` 출력에는 **평문 시크릿이 그대로 찍힌다.** 티켓·슬랙에 붙이지 말 것.
> ⚠️ `kubectl diff`로 볼 때만 나오는 OTel/CloudWatch 애노테이션 8개는 서버사이드 webhook 주입분 —
> ArgoCD diff에는 안 나온다. 노이즈다.

---

## 3. 롤아웃 전 스냅샷 (사후 비교용)

```bash
date -u +%Y-%m-%dT%H:%M:%SZ                      # 시작 시각 기록 (5번에서 사용)
kubectl get pods -n default --context=$CTX -l app=$DEP
```

---

## 4. sync

```bash
argocd app sync $APP --timeout 600
kubectl rollout status deploy/$DEP -n default --context=$CTX --timeout=10m
```
- [ ] `Phase: Succeeded`
- [ ] rollout 완료

**롤아웃은 느리다 — 서비스당 3~5분이 정상.** 앱 부팅이 약 59초(`preStop sleep 30`의 2배)라
`Progressing`이 길게 유지된다. 조급하게 끊지 말 것.

**문제 시 즉시 롤백:**
```bash
kubectl rollout undo deploy/$DEP -n default --context=$CTX
```

---

## 5. 결과 확인

```bash
kubectl -n argocd get app $APP --context=$CTX
kubectl get deploy $DEP -n default --context=$CTX
kubectl get pods -n default --context=$CTX -l app=$DEP \
  -o custom-columns='NAME:.metadata.name,READY:.status.containerStatuses[0].ready,STATUS:.status.phase,RESTARTS:.status.containerStatuses[0].restartCount'

# 평문이 실제로 사라졌는가
kubectl get deploy $DEP -n default --context=$CTX -o json \
 | jq -r '.spec.template.spec.containers[0].env[] | "\(.name)\t\(if .valueFrom then "→ secretKeyRef/"+.valueFrom.secretKeyRef.key else "평문" end)"'
```
- [ ] `Synced` / `Healthy`
- [ ] 레플리카 전부 `READY=true`, **`RESTARTS=0`**
- [ ] 대상 시크릿이 전부 `→ secretKeyRef/...`

---

## 6. ALB 타깃 헬스

```bash
TG=$(aws elbv2 describe-target-groups --region $REGION \
  --query "TargetGroups[?contains(TargetGroupName,'$(echo ${SVC} | tr -d '-')')].TargetGroupArn" --output text | tr '\t' '\n' | tail -1)
aws elbv2 describe-target-health --target-group-arn "$TG" --region $REGION \
  --query 'TargetHealthDescriptions[].{Target:Target.Id,Port:Target.Port,State:TargetHealth.State}' --output table
```
- [ ] 타깃이 **전부 `healthy`**

> ⚠️ 타깃 그룹이 여러 개 잡히면 파드의 readiness gate 이름으로 현행을 특정한다:
> ```bash
> kubectl get pod -n default --context=$CTX -l app=$DEP -o jsonpath='{.items[0].spec.readinessGates[0].conditionType}{"\n"}'
> # → target-health.elbv2.k8s.aws/k8s-default-<이름>  ← 이 <이름>이 붙은 TG 가 현행
> ```

---

## 7. 무중단 검증 (CloudWatch, 3번의 시각 사용)

```bash
LBDIM=$(aws elbv2 describe-target-groups --target-group-arns "$TG" --region $REGION \
  --query 'TargetGroups[0].LoadBalancerArns[0]' --output text | sed -E 's#.*:loadbalancer/##')
TGDIM=$(echo "$TG" | sed -E 's#.*:##')
FROM=2026-07-30T15:20:00Z   # 롤아웃 시작 -3분
TO=2026-07-30T15:35:00Z     # 롤아웃 종료 +5분

# 5xx 0건이어야 한다 (출력이 비면 0건)
aws cloudwatch get-metric-statistics --namespace AWS/ApplicationELB \
  --metric-name HTTPCode_Target_5XX_Count --start-time $FROM --end-time $TO \
  --period 60 --statistics Sum \
  --dimensions "Name=TargetGroup,Value=$TGDIM" "Name=LoadBalancer,Value=$LBDIM" \
  --region $REGION --query 'sort_by(Datapoints,&Timestamp)[].[Timestamp,Sum]' --output text

# healthy 타깃이 0으로 떨어진 적 없어야 한다
aws cloudwatch get-metric-statistics --namespace AWS/ApplicationELB \
  --metric-name HealthyHostCount --start-time $FROM --end-time $TO \
  --period 60 --statistics Minimum \
  --dimensions "Name=TargetGroup,Value=$TGDIM" "Name=LoadBalancer,Value=$LBDIM" \
  --region $REGION --query 'sort_by(Datapoints,&Timestamp)[].[Timestamp,Minimum]' --output text

# 트래픽이 실제로 흐르던 시간대였는지 (0이면 검증 의미 없음)
aws cloudwatch get-metric-statistics --namespace AWS/ApplicationELB \
  --metric-name RequestCount --start-time $FROM --end-time $TO \
  --period 60 --statistics Sum --dimensions "Name=LoadBalancer,Value=$LBDIM" \
  --region $REGION --query 'sort_by(Datapoints,&Timestamp)[].[Timestamp,Sum]' --output text
```
- [ ] `HTTPCode_Target_5XX_Count` = **0건**
- [ ] `HealthyHostCount` 최솟값 **≥ 1** (1로 떨어졌다 회복되는 건 정상 — gate가 일한 것)
- [ ] `RequestCount` > 0

**hq-server 실측(2026-07-30)**: 5xx 0건, HealthyHostCount 2→1→2, 분당 900~1,700 요청 중 무중단.

---

## 8. 외부 경로 스모크

```bash
# 이 서비스로 가는 외부 경로 찾기
kubectl get ingress eks-ingress -n default --context=$CTX -o json \
 | jq -r ".spec.rules[] | .host as \$h | (.http.paths[] | select(.backend.service.name==\"$DEP\") | \"\(\$h)\(.path)\")"

curl -s -i --max-time 10 https://prod.supp.fitness/<경로> | head -12
```
- [ ] **앱이 응답**했는가 — `x-powered-by: Express` 헤더 + JSON 본문
- [ ] 502/503이 아니다

> `404`는 정상일 수 있다. 앱이 낸 404(`{"message":"Cannot GET /hq",...}` + `x-powered-by`)면 경로가
> 살아 있다는 뜻이고, ALB가 낸 404면 헤더도 JSON 본문도 없다. **둘을 구분할 것.**

---

## 자주 막히는 지점

| 증상 | 원인 | 조치 |
|---|---|---|
| Application이 UI에 안 보임 | ArgoCD 인스턴스가 클러스터마다 별개 | **`https://prod-gbx-argocd.supp.fitness`** 로 접속 (dev는 `dev-gbx-...`) |
| 머지했는데 Application이 안 생김 | root 폴링 기본 3분 | `kubectl -n argocd annotate app platform-root argocd.argoproj.io/refresh=hard --overwrite` |
| `argocd` CLI 소켓 bind 실패 | 샌드박스 | 샌드박스 해제 후 재실행 |
| sync 출력 URL이 `argocd.example.com` | `argocd-cm`의 `url` 미설정 | 접속엔 무관(알림 링크만 깨짐). platform-iac 별건 |
