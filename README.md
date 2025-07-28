# action_test
git action test


## 진행 절차
1. 로컬 VM에서 docker image 생성
2. NKS Container registry에 이미지 추가
3. 해당 container로 새 pod 만들기
4. 외부에서 통신 시도



## 로컬 빌드 테스트
# 1. 의존성 설치
npm install

# 2. TypeScript 빌드
npm run build

# 3. 빌드 결과 확인
ls -la dist/

# 4. 로컬에서 실행 테스트
npm start

## Docker Image 빌드
# Docker 이미지 빌드
docker build -t zdm-api-server:latest .

# 빌드 완료 확인
docker images | grep zdm-api-server

## Docker Container 실행
# 1. 기본 포트(53307)로 실행
docker run -d --name my-zdm-api-server -p 53307:53307 zdm-api-server:latest

# 2. 다른 포트(예: 8080)로 실행하고 싶다면
docker run -d --name my-zdm-api-server-8080 -p 8080:8080 -e PORT=8080 zdm-api-server:latest

# 3. 컨테이너 상태 확인
docker ps

# 4. 컨테이너 로그 확인
docker logs my-zdm-api-server

## Container 관리
# 컨테이너 목록
docker container list

# 컨테이너 중지
docker stop my-zdm-api-server

# 컨테이너 재시작
docker start my-zdm-api-server

# 컨테이너 삭제
docker rm my-zdm-api-server

# 이미지 삭제
docker rmi zdm-api-server:latest

# 이름, tage가 모두 <none>인 이미지 삭제
docker rmi $(docker images -f "dangling=true" -q)

# 모든 이미지 삭제
docker image prune -a


## CD
```
# Object Storage에서 image pull 하기
docker pull zcon-nipa-container-registry.kr.ncr.ntruss.com/zdm-api-server:latest

# docker registry 인증정보 생성

# 1. 간단한 Pod 생성
kubectl run zdm-api-server \
  --image=zcon-nipa-container-registry.kr.ncr.ntruss.com/zdm-api-server:latest \
  --namespace=zdm-api \
  --port=53307 \
  --env="PORT=53307" \
  --env="NODE_ENV=production"

# 2. 상태 확인
kubectl get pods -n zdm-api
kubectl logs -f zdm-api-server -n zdm-api

# 3. 포트포워딩으로 테스트
kubectl port-forward zdm-api-server 8080:53307 -n zdm-api
curl http://localhost:8080/

# 98. 시크릿
kubectl get secrets -n zdm-api
# 시크릿 삭제
kubectl delete secret ncp-registry-secret -n zdm-api
# 99. Pod 삭제
kubectl delete pod zdm-api-server -n zdm-api
```

# bastion 서버에 SSH 접속 후 실행
kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: github-actions
  namespace: kube-system
---
apiVersion: v1
kind: Secret
metadata:
  name: github-actions-token
  namespace: kube-system
  annotations:
    kubernetes.io/service-account.name: github-actions
type: kubernetes.io/service-account-token
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: github-actions-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: github-actions
  namespace: kube-system
EOF

# Token과 인증서 정보 추출
TOKEN=$(kubectl get secret github-actions-token -n kube-system -o jsonpath='{.data.token}' | base64 -d)
CA_CERT=$(kubectl get secret github-actions-token -n kube-system -o jsonpath='{.data.ca\.crt}')
CLUSTER_URL=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')

# 새로운 kubeconfig 생성
cat > github-actions-kubeconfig.yaml << EOF
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority-data: ${CA_CERT}
    server: ${CLUSTER_URL}
  name: nks-cluster
contexts:
- context:
    cluster: nks-cluster
    user: github-actions
  name: github-actions@nks-cluster
current-context: github-actions@nks-cluster
users:
- name: github-actions
  user:
    token: ${TOKEN}
EOF

echo "✅ Service Account kubeconfig 생성 완료!"