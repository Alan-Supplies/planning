# CKA 취득 계획

## 목표

Kubernetes 운영 역량을 체계적으로 만들고 CKA(Certified Kubernetes Administrator)에 합격한다.

시험 일정부터 잡기보다 매일 실습하는 습관을 먼저 만든다. 4주간 학습 기록을 유지한 뒤 진도와 실습 결과를 근거로 응시 목표일을 정한다.

## 현재 시험 기준

2026-07-23 확인 기준이다. 시험을 신청하거나 응시일을 정할 때 공식 문서를 다시 확인한다.

- Kubernetes 버전: v1.35
- 형식: 온라인 감독, 명령줄에서 문제를 해결하는 실기 시험
- 시간: 2시간
- 공식 안내: [Certified Kubernetes Administrator](https://training.linuxfoundation.org/certification/certified-kubernetes-administrator-cka/)
- 공식 커리큘럼: [CNCF Curriculum](https://github.com/cncf/curriculum)

| 영역 | 비중 |
| --- | ---: |
| Troubleshooting | 30% |
| Cluster Architecture, Installation & Configuration | 25% |
| Services & Networking | 20% |
| Workloads & Scheduling | 15% |
| Storage | 10% |

## 운영 원칙

- 평일에는 **25분**을 기본 학습 단위로 사용한다.
- 바쁜 날에도 **최소 10분** 동안 명령 하나를 직접 실행해 학습 연속성을 지킨다.
- 읽기보다 실습을 우선한다. 한 학습 단위에서 최소 한 번은 직접 명령을 실행한다.
- 학습 종료 시 `배운 것`, `막힌 것`, `다음 시작점`을 한 줄씩 기록한다.
- 업무에서 만난 Kubernetes 문제는 해당 시험 영역에 연결해 복습한다.
- 밀린 분량을 다음 날에 더하지 않는다. 다음 날은 원래의 25분으로 다시 시작한다.

## 매일 25분 루틴

1. **3분 — 시작:** 전날의 `다음 시작점`을 확인한다.
2. **17분 — 실습:** 하나의 작은 시나리오를 직접 해결한다.
3. **5분 — 기록:** 결과와 다음 시작점을 아래 학습 기록에 남긴다.

시간이 부족한 날의 최소 루틴:

1. 공식 문서에서 개념 하나를 확인한다.
2. 관련 `kubectl` 명령을 한 번 실행한다.
3. 다음에 이어갈 명령이나 질문을 한 줄 남긴다.

## 12주 로드맵

시작일은 첫 학습 기록을 작성한 날로 본다. 진도가 늦어지면 주차를 늘리되 매일 학습량을 무리하게 늘리지 않는다.

| 주차 | 집중 영역 | 주간 완료 조건 |
| --- | --- | --- |
| 1 | 현재 수준 진단, kubectl 기본 조작 | 각 시험 영역을 자가 평가하고 취약 영역 3개를 정한다 |
| 2 | Cluster Architecture | control plane 구성요소와 클러스터 구조를 설명하고 관련 리소스를 조회한다 |
| 3 | Installation & Configuration | kubeadm, RBAC, Helm, Kustomize 기본 시나리오를 실습한다 |
| 4 | Workloads & Scheduling | Deployment, rollout, scheduling, autoscaling 문제를 해결한다 |
| 5 | Services & Networking I | Service, endpoint, CoreDNS 연결 문제를 진단한다 |
| 6 | Services & Networking II | NetworkPolicy, Ingress, Gateway API 시나리오를 실습한다 |
| 7 | Storage | PV, PVC, StorageClass, access mode, reclaim policy를 실습한다 |
| 8 | Troubleshooting I | Pod, 애플리케이션 로그, 리소스 사용 문제를 진단한다 |
| 9 | Troubleshooting II | 노드, 클러스터 구성요소, 네트워크 문제를 진단한다 |
| 10 | 통합 시간 제한 실습 | 시간을 측정하며 영역 혼합 문제를 해결한다 |
| 11 | 모의시험 1회 및 보완 | 오답을 영역별로 분류하고 취약 영역을 다시 실습한다 |
| 12 | 모의시험 2회 및 응시 판단 | 시간 내 완료율을 확인하고 시험일을 정하거나 보완 주차를 계획한다 |

## 첫 4주 점검

4주 후 다음 항목을 확인하고 응시 목표일을 정한다.

- [ ] 평일 학습 실행률이 70% 이상이다.
- [ ] 읽기보다 직접 실습한 날이 더 많다.
- [ ] 다섯 시험 영역의 현재 수준을 설명할 수 있다.
- [ ] 취약 영역과 보완 방법이 정해져 있다.
- [ ] 2시간 실기 시험을 준비할 현실적인 주간 시간을 확보했다.

## 학습 백로그

각 항목은 25분 안에 시작할 수 있는 실습으로 더 작게 나눈다.

### Troubleshooting

- [ ] Pending Pod의 원인을 events와 리소스 상태로 진단한다.
- [ ] CrashLoopBackOff의 로그와 이전 컨테이너 로그를 확인한다.
- [ ] Service가 Pod에 연결되지 않는 원인을 endpoint와 selector로 확인한다.

### Cluster Architecture, Installation & Configuration

- [ ] control plane 구성요소와 역할을 설명한다.
- [ ] RBAC Role, ClusterRole, Binding 차이를 실습한다.
- [ ] Helm과 Kustomize로 리소스를 설치·변경한다.

### Services & Networking

- [ ] ClusterIP, NodePort, LoadBalancer의 차이를 실습한다.
- [ ] CoreDNS 문제를 진단한다.
- [ ] NetworkPolicy로 트래픽을 허용·차단한다.

### Workloads & Scheduling

- [ ] Deployment rollout과 rollback을 실습한다.
- [ ] requests, limits, affinity, taint, toleration을 적용한다.
- [ ] ConfigMap과 Secret으로 워크로드를 설정한다.

### Storage

- [ ] PV, PVC, StorageClass의 연결 관계를 실습한다.
- [ ] access mode와 reclaim policy 차이를 확인한다.
- [ ] 동적 볼륨 프로비저닝 흐름을 설명한다.

## 학습 기록

| 날짜 | 시간 | 영역 | 실습·결과 | 막힌 것 | 다음 시작점 |
| --- | ---: | --- | --- | --- | --- |
| 2026-07-23 |  | 시작 준비 | CKA 장기 계획 생성 |  | 시험 영역별 현재 수준을 `상/중/하`로 평가한다 |

## 주간 회고

매주 마지막 학습일에 작성한다.

- 실행한 날 / 계획한 날:
- 가장 많이 직접 실행한 명령:
- 새롭게 이해한 내용:
- 반복해서 막힌 내용:
- 다음 주 첫 실습:

