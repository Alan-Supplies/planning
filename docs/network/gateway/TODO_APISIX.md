실행 항목 (아키텍처 변경 없음, 관측성 개선)

1. success-codes 범위 축소

현재 "200-499". APISIX 루트 404 허용 목적은 이해되나, 이 범위면 APISIX가 etcd 연결 상실로 모든 요청에 4xx를 반환하는 상태에서도 헬스체크가 통과한다. 장애 감지 불가.

APISIX에 /healthz 라우트 추가 (200 반환)

healthcheck-path → /healthz

success-codes → "200"

2. ALB 액세스 로그 활성화

load-balancer-attributes에 access_logs.s3.enabled=true 추가

요청이 APISIX Pod에 도달하지 못하고 ALB 단에서 잘린 경우를 구분하기 위함. ALB JWT 검증 관련 500 사례도 액세스 로그의 실패 코드로만 진단됐던 전례가 있다.

3. 정리 (optional)

kubernetes.io/ingress.class annotation 제거 (deprecated, spec.ingress_class_name과 중복)

Validate Token 액션의 AWS Load Balancer Controller annotation 지원 여부 — 컨트롤러 릴리스 노트 확인 필요. 미지원이면 리스너 룰을 Terraform으로 외부 관리해야 하고, 컨트롤러 재조정 시 덮어쓰기 drift 우려.