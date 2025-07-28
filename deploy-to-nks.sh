#!/bin/bash

# NKS 배포 스크립트
set -e

# 환경 변수 설정
PROJECT_NAME="zdm-api-server"
VERSION=${1:-latest}
REGISTRY_URL="zcon-nipa-container-registry.kr.ncr.ntruss.com"
K8S_NAMESPACE="default"

# 색상 코드
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🚀 NKS 배포 시작...${NC}"

# # 1. kubectl 연결 확인
# echo -e "${YELLOW}🔍 kubectl 연결 확인...${NC}"
# if ! kubectl cluster-info > /dev/null 2>&1; then
#     echo -e "${RED}❌ kubectl이 클러스터에 연결되지 않았습니다.${NC}"
#     echo -e "${YELLOW}💡 NKS 클러스터 설정을 확인해주세요.${NC}"
#     exit 1
# fi
# echo -e "${GREEN}✅ kubectl 연결 성공${NC}"

# 2. 이미지 존재 확인
echo -e "${YELLOW}🐳 Docker 이미지 확인...${NC}"
IMAGE_NAME="${REGISTRY_URL}/${PROJECT_NAME}:${VERSION}"
if ! docker pull $IMAGE_NAME > /dev/null 2>&1; then
    echo -e "${RED}❌ 이미지를 찾을 수 없습니다: $IMAGE_NAME${NC}"
    echo -e "${YELLOW}💡 먼저 이미지를 빌드하고 푸시해주세요.${NC}"
    exit 1
fi
echo -e "${GREEN}✅ 이미지 확인 완료: $IMAGE_NAME${NC}"

# 3. 배포 매니페스트 업데이트
echo -e "${YELLOW}📝 배포 매니페스트 업데이트...${NC}"
cp k8s/deployment.yaml k8s/deployment-temp.yaml
sed -i "s|your-nks-registry.ncloud.com/your-namespace/zdm-api-server:latest|$IMAGE_NAME|g" k8s/deployment-temp.yaml
echo -e "${GREEN}✅ 매니페스트 업데이트 완료${NC}"

# 4. 배포 실행
echo -e "${YELLOW}🚀 Kubernetes에 배포 중...${NC}"
kubectl apply -f k8s/deployment-temp.yaml

# 5. 배포 상태 확인
echo -e "${YELLOW}⏳ 배포 상태 확인 중...${NC}"
kubectl rollout status deployment/${PROJECT_NAME} -n ${K8S_NAMESPACE} --timeout=300s

# 6. Pod 상태 확인
echo -e "${YELLOW}📦 Pod 상태 확인...${NC}"
kubectl get pods -l app=${PROJECT_NAME} -n ${K8S_NAMESPACE}

# 7. 서비스 확인
echo -e "${YELLOW}🌐 서비스 상태 확인...${NC}"
kubectl get service ${PROJECT_NAME}-service -n ${K8S_NAMESPACE}

# 8. Ingress 확인 (있는 경우)
if kubectl get ingress ${PROJECT_NAME}-ingress -n ${K8S_NAMESPACE} > /dev/null 2>&1; then
    echo -e "${YELLOW}🌍 Ingress 상태 확인...${NC}"
    kubectl get ingress ${PROJECT_NAME}-ingress -n ${K8S_NAMESPACE}
fi

# 9. 헬스체크
echo -e "${YELLOW}🏥 헬스체크 수행...${NC}"
sleep 30

# 포트포워딩으로 헬스체크
kubectl port-forward service/${PROJECT_NAME}-service 8080:80 -n ${K8S_NAMESPACE} > /dev/null 2>&1 &
PORT_FORWARD_PID=$!
sleep 5

if curl -f -s http://localhost:8080/ > /dev/null; then
    echo -e "${GREEN}✅ 헬스체크 성공!${NC}"
else
    echo -e "${RED}❌ 헬스체크 실패${NC}"
fi

# 포트포워딩 프로세스 종료
kill $PORT_FORWARD_PID > /dev/null 2>&1

# 10. 임시 파일 정리
rm -f k8s/deployment-temp.yaml

echo -e "${GREEN}🎉 NKS 배포 완료!${NC}"
echo -e "${BLUE}📍 배포된 이미지: $IMAGE_NAME${NC}"
echo -e "${BLUE}📍 네임스페이스: $K8S_NAMESPACE${NC}"

# 11. 유용한 명령어 출력
echo -e "${YELLOW}"
echo "🔧 유용한 명령어:"
echo "  로그 확인: kubectl logs -l app=${PROJECT_NAME} -n ${K8S_NAMESPACE}"
echo "  Pod 상태: kubectl get pods -l app=${PROJECT_NAME} -n ${K8S_NAMESPACE}"
echo "  서비스 포트포워딩: kubectl port-forward service/${PROJECT_NAME}-service 8080:80 -n ${K8S_NAMESPACE}"
echo "  배포 롤백: kubectl rollout undo deployment/${PROJECT_NAME} -n ${K8S_NAMESPACE}"
echo -e "${NC}"