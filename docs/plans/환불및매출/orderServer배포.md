1. deployment.yaml
- 환경변수: podsNum
  
1. service.yaml


resources:
  requests:
    cpu: '200m'
    memory: '2Gi' # 최소 메모리 요청 (Pod 최소한 이만큼 보장받음)
  limits:
    cpu: '200m'
    memory: '2Gi' # 최대 메모리 제한 (이걸 초과하면 OOMKilled 발생)


1. apiSix
  - pri
  - pub
  - api
2. buildspec.yml
3. codepipeline?