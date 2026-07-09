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



### 기타
예제 깃헙
Alan-Supplies/argocd-example-apps
  