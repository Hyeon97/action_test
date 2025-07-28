#!/bin/bash

# 환경 변수 설정
PROJECT_NAME="zdm-api-server"
VERSION=${1:-latest}
REGISTRY_URL="zcon-nipa-container-registry.kr.ncr.ntruss.com"  # NKS Container Registry URL               # 네임스페이스

# 색상 코드
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}🚀 Starting build and push process...${NC}"

# 1. 프로젝트 빌드 테스트
echo -e "${YELLOW}📦 Testing TypeScript build...${NC}"
npm run build
if [ $? -ne 0 ]; then
    echo -e "${RED}❌ TypeScript build failed${NC}"
    exit 1
fi
echo -e "${GREEN}✅ TypeScript build successful${NC}"

# 2. Docker 이미지 빌드
echo -e "${YELLOW}🐳 Building Docker image...${NC}"
docker build -t ${PROJECT_NAME}:${VERSION} .
if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Docker build failed${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Docker image built successfully${NC}"

# 3. 이미지 태그 지정
echo -e "${YELLOW}🏷️  Tagging image for registry...${NC}"
docker tag ${PROJECT_NAME}:${VERSION} ${REGISTRY_URL}/${PROJECT_NAME}:${VERSION}
docker tag ${PROJECT_NAME}:${VERSION} ${REGISTRY_URL}/${PROJECT_NAME}:latest

# 4. NKS Container Registry 로그인 (필요한 경우)
echo -e "${YELLOW}🔐 Login to NKS Container Registry...${NC}"
# docker login ${REGISTRY_URL}

# 5. 이미지 푸시
echo -e "${YELLOW}📤 Pushing image to registry...${NC}"
docker push ${REGISTRY_URL}/${PROJECT_NAME}:${VERSION}
docker push ${REGISTRY_URL}/${PROJECT_NAME}:latest

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Successfully pushed to registry!${NC}"
    echo -e "${GREEN}📍 Image: ${REGISTRY_URL}/${PROJECT_NAME}:${VERSION}${NC}"
else
    echo -e "${RED}❌ Failed to push to registry${NC}"
    exit 1
fi

# 6. 불필요한 이미지 정리
echo -e "${YELLOW}🧹 Cleaning up dangling images...${NC}"
DANGLING_IMAGES=$(docker images --filter "dangling=true" -q)
if [ ! -z "$DANGLING_IMAGES" ]; then
    docker rmi $DANGLING_IMAGES || true
    echo -e "${GREEN}✅ Dangling images cleaned up${NC}"
else
    echo -e "${GREEN}✅ No dangling images to clean${NC}"
fi

# 7. 빌드 캐시 정리 (선택사항)
echo -e "${YELLOW}🧹 Cleaning up build cache...${NC}"
docker builder prune -f

echo -e "${GREEN}🎉 Build and push completed successfully!${NC}"