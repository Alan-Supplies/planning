사용자 요청  https://prod-pp-api.supp.fitness/pub/v1/auth
     │
     ▼
DNS  Route53 supp.fitness 존 · CNAME prod-pp-api
     → k8s-apisix-apisixal-020f73fc5e-...elb.amazonaws.com
     ⚠️ 코드에 없음 (수동 관리)
     │
     ▼
ALB  k8s-apisix-apisixal-020f73fc5e (internet-facing, DB-vpc)
     ★★★ apisix.tf:707  ← 바로 여기 ★★★
     │     리스너 80 → redirect 443 / 443 HTTPS(ACM) → 그 외 fixed-response
     ▼
파드 IP:9080  타깃그룹 target-type=ip · 172.31.72.79, 172.31.67.49 (healthy)
     │
     ▼
APISIX Gateway  ApisixRoute CRD 로 라우팅
     │
     ▼
백엔드  argocd-server:443 (/api/webhook) · order/auth 등

---

                     사용자 / GitHub webhook
                          │  https://prod-pp-api.supp.fitness/pub/v1/order/...
                          ▼
            ┌─────────────────────────────────────┐
            │ Route53  supp.fitness (퍼블릭 존)    │  ⚠️ IaC 코드 밖 (수동 관리)
            │ prod-pp-api  CNAME→  ALB DNS        │
            └─────────────────────────────────────┘
                          │
══════════════════════════│═══════════════════════════════════════════════
 AWS 699016088228 · ap-northeast-2
┌─────────────────────────│─────────────────────────────────────────────┐
│ VPC  vpc-a220b0c9  "DB-vpc(Dev, Prod)"  172.31.0.0/16                 │
│                    igw-39115751                                       │
│  ┌─── 퍼블릭 서브넷 (0.0.0.0/0 → IGW) ──────────────────────────────┐ │
│  │                       ▼                                          │ │
│  │  ╔═══════════════════════════════════════════════════════════╗  │ │
│  │  ║ ALB  k8s-apisix-apisixal-020f73fc5e   internet-facing     ║  │ │
│  │  ║  :80  → 443 리다이렉트                                     ║  │ │
│  │  ║  :443 HTTPS(ACM) → Host=prod-pp-api 만 매칭                ║  │ │
│  │  ║                     그 외 → fixed-response                 ║  │ │
│  │  ╚═══════════════════════════════════════════════════════════╝  │ │
│  │   걸쳐 있는 서브넷 ▼                                              │ │
│  │   2a 172.31.128.0/20          2c 172.31.144.0/20                │ │
│  │   subnet-0ac9a4bf…            subnet-07cd691c…                  │ │
│  │   ⚠️ 두 서브넷 이름이 똑같이 prod-public-subnet-2a-preppers-eks   │ │
│  │   ⚠️ kubernetes.io 태그 없음                                     │ │
│  │                                                                  │ │
│  │   [ALB 미사용] 2b 172.31.96.0/20 · 2d 172.31.112.0/20           │ │
│  │                ↑ role/elb=1 태그는 반대로 여기에만 있음 ⚠️        │ │
│  └──────────────────────────────────────────────────────────────────┘ │
│              │ target-type=ip → 파드 IP:9080 로 직접                  │
│              │ (Service ClusterIP 10.100.45.141 을 거치지 않음)        │
│  ┌─── 프라이빗 서브넷 (0.0.0.0/0 → nat-07a44906d1) ─────────────────┐ │
│  │                    ▼                                             │ │
│  │  AZ 2a  172.31.64.0/20           AZ 2c  172.31.80.0/20          │ │
│  │  subnet-0c9846f1…                subnet-03190df0…               │ │
│  │  ┌───────────────────────────┐   ┌───────────────────────────┐  │ │
│  │  │ node .71.178   node .76.71│   │ node .92.173  node .94.169│  │ │
│  │  │  ┌─────────┐  ┌─────────┐ │   │                           │  │ │
│  │  │  │ apisix  │  │ apisix  │ │   │   apisix 파드 없음 ⚠️      │  │ │
│  │  │  │ .72.79  │  │ .67.49  │ │   │                           │  │ │
│  │  │  │ :9080 ✓ │  │ :9080 ✓ │ │   │   (backend 노드 2대만)     │  │ │
│  │  │  └─────────┘  └─────────┘ │   │                           │  │ │
│  │  │ node .79.168 (metrics)    │   │                           │  │ │
│  │  └───────────────────────────┘   └───────────────────────────┘  │ │
│  └──────────────────────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────────────┘

--
- 논리 경계

┌─ EKS 컨트롤플레인 (AWS 관리 VPC · 우리 VPC 밖) ──────────────────────┐
│  apiserver + etcd     엔드포인트: 퍼블릭만(0.0.0.0/0), 프라이빗 비활성 │
│                                                                       │
│  ▼ 여기 있는 건 전부 "선언"일 뿐 — 트래픽은 지나가지 않음             │
│    Ingress  apisix/apisix-alb   class=alb   ← apisix.tf:707           │
│    ApisixRoute × 16  (argocd-webhook, order, auth, kds, pos …)        │
│    Service  apisix-gateway  ClusterIP 10.100.45.141                  │
│             ↑ 서비스 CIDR 10.100.0.0/16 = VPC에 없는 가상 대역        │
└───────────────────────────────────────────────────────────────────────┘
         │ watch                              │ watch
         ▼                                    ▼
 aws-load-balancer-controller          apisix-ingress-controller
 (kube-system 파드)                    (apisix ns, 파드 2개)
         │ AWS API 호출                       │ APISIX etcd 에 라우팅 주입
         ▼                                    ▼
 ★ 실물 ALB 를 VPC 퍼블릭 서브넷에 생성    APISIX 게이트웨이의 경로 테이블
   태그: ingress.k8s.aws/stack=apisix/apisix-alb

---
apisix 가 아니라

ALB -> ingress -> 로 갈때 jwt, request_id 생성을 공용으로 하는 방법
 