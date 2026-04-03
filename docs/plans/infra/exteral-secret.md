1. stacks/iam/eks/preppers-cluster/
   → External Secrets용 IAM Role 추가 (IRSA)

2. modules/eks/external-secrets/ 모듈 생성
   → helm_release (ESO 설치)
   → ClusterSecretStore

3. stacks/eks/preppers-cluster/ 에서 모듈 호출

4. stacks/eks/preppers-cluster/k8s/
   → ExternalSecret 리소스 추가

## 추가
### stacks/eks
- preppers-cluster/k8s
  external-secrets.tf
- supplies-eks-dev/k8s
  external-secrets.tf
### iam/eks
- preppers-cluster
  main.tf
  outputs.tf
- supplies-eks-dev
  main.tf
  outputs.tf
