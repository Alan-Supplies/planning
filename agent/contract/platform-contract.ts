/**
 * Platform Boundary Contract
 * -----------------------------------------------------------------------------
 * iac ↔ gitops 사이에서 교환되는 유일한 인터페이스.
 *
 *  - platform-iac  가 이 객체를 *생산* 한다 (Terraform outputs → JSON).
 *  - platform-gitops 가 이 객체를 *소비* 한다 (Application/values 렌더링 입력).
 *
 * 이 타입이 타입의 source of truth 이며, platform-contract.schema.json 은
 * 런타임 검증(CI, 에이전트 object 단계)에서 사용한다. 둘은 항상 동기화되어야 한다.
 *
 * 규칙:
 *  - 여기에 없는 필드를 gitops 가 iac 내부에서 끌어오지 않는다 (narrow waist).
 *  - 이 타입/스키마의 변경 권한은 arbiter 에게만 있다.
 */

/** 계약 스키마 버전. Breaking change 시 major 를 올린다. */
export type ContractVersion = `${number}.${number}`;

/** 회색지대 항목의 소유권 배정. DESIGN.md §2 표와 일치해야 한다. */
export type Owner = "iac" | "gitops";

export interface ClusterInfo {
  /** 논리적 클러스터 이름 (예: "prod-apne2-01") */
  name: string;
  /** Kubernetes API endpoint */
  endpoint: string;
  /** 클라우드 리전 (예: "ap-northeast-2") */
  region: string;
  /** OIDC provider URL — IRSA/Workload Identity 연동용 */
  oidcIssuerUrl: string;
  /** base64 인코딩된 클러스터 CA (선택; 외부 도구 연동용) */
  caData?: string;
}

/** IRSA / Workload Identity 로 gitops 워크로드가 사용할 IAM 역할. */
export interface WorkloadIdentity {
  /** 이 역할을 사용할 서비스 계정 (namespace/name) */
  serviceAccount: string;
  /** IAM Role ARN (AWS) 또는 GCP SA email 등 */
  roleArn: string;
}

/** iac 가 부트스트랩하는 ArgoCD 정보. */
export interface ArgoCdBootstrap {
  /** ArgoCD 가 설치된 namespace (일반적으로 "argocd") */
  namespace: string;
  /** iac 가 생성한 최초 AppProject 이름. gitops App 은 이 안에서만 생성. */
  appProject: string;
  /** iac 가 등록한 Git repo URL (repo credential 포함) */
  repoUrl: string;
  /** app-of-apps 진입점: root Application 이 가리키는 repo 경로 */
  rootAppPath: string;
  /** root Application 이름 (iac 가 생성, 이후 self-management 로 인계) */
  rootAppName: string;
  /** 부트스트랩 이후 ArgoCD self-management 로 인계되었는지 */
  selfManaged: boolean;
}

/**
 * 회색지대 소유권 배정. DESIGN.md §2 표의 machine-readable 버전.
 * object 단계에서 "이 항목은 네 소유"라고 근거를 댈 때 참조한다.
 */
export interface GrayZoneAssignments {
  namespaceCreation: Owner;
  externalSecretsOperatorInstall: Owner;
  externalSecretDefinitions: Owner;
  crds: Owner;
  clusterRbac: Owner;
  namespaceRbac: Owner;
}

/**
 * iac → gitops 로 넘어가는 전체 계약.
 * gitops 는 이 객체 밖의 어떤 iac 내부 상태에도 의존하지 않는다.
 */
export interface PlatformContract {
  contractVersion: ContractVersion;
  /** 이 계약을 생산한 시각 (ISO 8601) */
  producedAt: string;
  cluster: ClusterInfo;
  argocd: ArgoCdBootstrap;
  /** gitops 워크로드가 사용할 수 있는 사전 승인된 identity 목록 */
  workloadIdentities: WorkloadIdentity[];
  grayZone: GrayZoneAssignments;
}

/** 타입 가드 — 소비 측(gitops)에서 얇은 런타임 확인용. 상세 검증은 JSON Schema 로. */
export function isPlatformContract(v: unknown): v is PlatformContract {
  if (typeof v !== "object" || v === null) return false;
  const c = v as Record<string, unknown>;
  return (
    typeof c.contractVersion === "string" &&
    typeof c.cluster === "object" &&
    typeof c.argocd === "object" &&
    typeof c.grayZone === "object"
  );
}
