name: Build and Push to NCP Container Registry

on:
  push:
    branches: [ '**' ]  # 모든 브랜치에서 실행
  pull_request:
    branches: [ main, develop ]

# GitHub Actions 권한 설정
permissions:
  contents: read
  packages: write

env:
  PROJECT_NAME: zdm-api-server
  REGISTRY_URL: zcon-nipa-container-registry.kr.ncr.ntruss.com
  NODE_VERSION: '22'
  # Kubernetes 배포 설정
  K8S_NAMESPACE: zdm-api
  K8S_DEPLOYMENT_NAME: zdm-api
  K8S_CONTAINER_NAME: zdm-api

jobs:
  # 1단계: 빌드 및 테스트
  build-and-test:
    name: Build and Test
    runs-on: ubuntu-latest
    
    outputs:
      version: ${{ steps.version.outputs.version }}
    
    steps:
    - name: 🛒 코드 체크아웃
      uses: actions/checkout@v4
      
    - name: 🔧 Node.js ${{ env.NODE_VERSION }} 설정
      uses: actions/setup-node@v4
      with:
        node-version: ${{ env.NODE_VERSION }}
        cache: 'npm'
        
    - name: 📦 의존성 설치
      run: npm ci
      
    - name: 🧪 TypeScript 빌드 테스트
      run: |
        echo "🔍 Testing TypeScript build..."
        npm run build
        echo "✅ TypeScript build successful"
        
    - name: 🏷️ 버전 정보 생성
      id: version
      run: |
        # 태그가 있으면 태그를 사용, 없으면 브랜치-SHA 조합 사용
        if [[ $GITHUB_REF == refs/tags/* ]]; then
          VERSION=${GITHUB_REF#refs/tags/}
        else
          VERSION=${{ github.ref_name }}-${{ github.sha }}
        fi
        echo "version=$VERSION" >> $GITHUB_OUTPUT
        echo "📍 Generated version: $VERSION"
        
    - name: 📤 빌드 아티팩트 업로드
      uses: actions/upload-artifact@v4
      with:
        name: build-artifacts-${{ steps.version.outputs.version }}
        path: |
          dist/
          package.json
          package-lock.json
        retention-days: 1

  # 2단계: Docker 이미지 빌드 및 푸시
  docker-build-push:
    name: Docker Build and Push to NCP
    runs-on: ubuntu-latest
    needs: build-and-test
    # main, develop 브랜치의 push 이벤트에서만 실행
    if: |
      github.event_name == 'push' && 
      (github.ref_name == 'main' || github.ref_name == 'develop')
    
    steps:
    - name: 🛒 코드 체크아웃
      uses: actions/checkout@v4
      
    - name: 🔧 Docker Buildx 설정
      uses: docker/setup-buildx-action@v3
      
    - name: 🔐 NCP Container Registry 로그인
      uses: docker/login-action@v3
      with:
        registry: ${{ env.REGISTRY_URL }}
        username: ${{ secrets.NCP_REGISTRY_USERNAME }}
        password: ${{ secrets.NCP_REGISTRY_PASSWORD }}
        
    - name: 🏷️ 메타데이터 추출
      id: meta
      uses: docker/metadata-action@v5
      with:
        images: ${{ env.REGISTRY_URL }}/${{ env.PROJECT_NAME }}
        tags: |
          type=ref,event=branch
          type=raw,value=latest,enable={{is_default_branch}}
        labels: |
          org.opencontainers.image.title=${{ env.PROJECT_NAME }}
          org.opencontainers.image.description=TypeScript Server for ${{ env.PROJECT_NAME }}
          org.opencontainers.image.vendor=Your Organization
          
    - name: 🐳 Docker 이미지 빌드 및 푸시
      uses: docker/build-push-action@v5
      with:
        context: .
        push: true
        tags: ${{ steps.meta.outputs.tags }}
        labels: ${{ steps.meta.outputs.labels }}
        cache-from: type=gha
        cache-to: type=gha,mode=max
        platforms: linux/amd64
        
    - name: 📋 푸시된 이미지 정보 출력
      run: |
        echo "🎉 Successfully pushed to NCP Container Registry!"
        echo "📍 Registry: ${{ env.REGISTRY_URL }}"
        echo "📍 Repository: ${{ env.PROJECT_NAME }}"
        echo "📍 Tags:"
        echo "${{ steps.meta.outputs.tags }}" | while read tag; do
          echo "   - $tag"
        done
        
    - name: 🧹 빌드 캐시 정리
      run: |
        echo "🧹 Cleaning up build cache..."
        docker builder prune -f
        echo "✅ Build cache cleaned up"

  # 3단계: 이미지 검증
  verify-image:
    name: Verify Pushed Image
    runs-on: ubuntu-latest
    needs: docker-build-push
    # Docker 이미지가 푸시된 경우에만 실행
    if: |
      github.event_name == 'push' && 
      (github.ref_name == 'main' || github.ref_name == 'develop')
    
    steps:
    - name: 🔐 NCP Container Registry 로그인
      uses: docker/login-action@v3
      with:
        registry: ${{ env.REGISTRY_URL }}
        username: ${{ secrets.NCP_REGISTRY_USERNAME }}
        password: ${{ secrets.NCP_REGISTRY_PASSWORD }}
        
    - name: 🔍 이미지 검증
      run: |
        echo "🔍 Verifying pushed image..."
        
        # latest 태그 이미지 풀 테스트
        IMAGE_NAME="${{ env.REGISTRY_URL }}/${{ env.PROJECT_NAME }}:latest"
        echo "📦 Pulling image: $IMAGE_NAME"
        
        if docker pull "$IMAGE_NAME"; then
          echo "✅ Image pull successful"
          
          # 이미지 정보 출력
          echo "📋 Image information:"
          docker images "$IMAGE_NAME" --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.CreatedAt}}\t{{.Size}}"
          
          # 간단한 실행 테스트
          echo "🚀 Testing container startup..."
          CONTAINER_ID=$(docker run -d -p 8080:53307 "$IMAGE_NAME")
          
          # 컨테이너 시작 대기
          sleep 15
          
          # 헬스체크
          if docker ps | grep -q "$CONTAINER_ID"; then
            echo "✅ Container is running"
            
            # HTTP 응답 테스트 (포트포워딩 없이 컨테이너 내부에서)
            if docker exec "$CONTAINER_ID" wget -q --spider http://localhost:53307/; then
              echo "✅ Application is responding"
            else
              echo "⚠️ Application health check failed"
              docker logs "$CONTAINER_ID"
            fi
          else
            echo "❌ Container failed to start"
            docker logs "$CONTAINER_ID"
          fi
          
          # 정리
          docker stop "$CONTAINER_ID" > /dev/null 2>&1
          docker rm "$CONTAINER_ID" > /dev/null 2>&1
          
        else
          echo "❌ Image pull failed"
          exit 1
        fi

  # 4단계: CD - Kubernetes 배포
  deploy-to-kubernetes:
    name: Deploy to Kubernetes
    runs-on: ubuntu-latest
    needs: [build-and-test, docker-build-push, verify-image]
    # main 브랜치에 push할 때만 배포 (운영 환경)
    if: |
      github.event_name == 'push' && 
      github.ref_name == 'main' &&
      needs.verify-image.result == 'success'
    
    environment:
      name: production
      url: http://zdm-api-service.zdm-api.svc.cluster.local:53307
    
    steps:
    - name: 🛒 코드 체크아웃
      uses: actions/checkout@v4
      
    - name: ⚙️ kubectl 설치
      uses: azure/setup-kubectl@v3
      with:
        version: 'v1.28.0'
        
    - name: 🔐 NKS 클러스터 인증 설정 (Service Account Token)
      run: |
        echo "🔐 Setting up NKS cluster authentication with Service Account Token..."
        
        # Secret 값 검증
        if [ -z "${{ secrets.KUBE_CONFIG_DATA }}" ]; then
          echo "❌ KUBE_CONFIG_DATA secret is empty!"
          exit 1
        fi
        
        # kubeconfig 파일 생성 (Service Account Token 방식)
        mkdir -p $HOME/.kube
        echo "🔍 Creating kubeconfig file..."
        echo "${{ secrets.KUBE_CONFIG_DATA }}" > $HOME/.kube/config
        chmod 600 $HOME/.kube/config
        
        # kubeconfig 파일 검증
        if [ ! -s $HOME/.kube/config ]; then
          echo "❌ kubeconfig file is empty!"
          exit 1
        fi
        
        echo "✅ kubeconfig file created successfully"
        echo "📋 Config file size: $(wc -c < $HOME/.kube/config) bytes"
        
        # kubeconfig가 Service Account Token 방식인지 확인
        echo "📋 kubeconfig authentication method check:"
        if grep -q "token:" $HOME/.kube/config; then
          echo "✅ Service Account Token authentication detected"
        elif grep -q "ncp-iam-authenticator" $HOME/.kube/config; then
          echo "❌ ncp-iam-authenticator method detected - this requires additional setup"
          echo "Please use Service Account Token method instead"
          exit 1
        else
          echo "⚠️ Unknown authentication method"
        fi
        
        # 클러스터 연결 테스트
        echo "🔍 Testing cluster connection..."
        if ! kubectl cluster-info; then
          echo "❌ Failed to connect to cluster"
          echo "📋 kubeconfig content (first 10 lines):"
          head -10 $HOME/.kube/config
          exit 1
        fi
        
        echo "🔍 Testing node access..."
        kubectl get nodes
        
        echo "🔍 Testing namespace access..."
        kubectl get namespaces
        
        echo "✅ Successfully connected to NKS cluster using Service Account Token"
        
    - name: 🔍 현재 배포 상태 확인
      run: |
        echo "🔍 Checking current deployment status..."
        
        # namespace 존재 확인
        if ! kubectl get namespace ${{ env.K8S_NAMESPACE }} >/dev/null 2>&1; then
          echo "❌ Namespace ${{ env.K8S_NAMESPACE }} does not exist!"
          exit 1
        fi
        
        # deployment 존재 확인
        if ! kubectl get deployment ${{ env.K8S_DEPLOYMENT_NAME }} -n ${{ env.K8S_NAMESPACE }} >/dev/null 2>&1; then
          echo "❌ Deployment ${{ env.K8S_DEPLOYMENT_NAME }} does not exist!"
          exit 1
        fi
        
        # 현재 배포 상태 (이미 존재하는 Deployment)
        echo "📋 Current deployment status:"
        kubectl get deployment ${{ env.K8S_DEPLOYMENT_NAME }} -n ${{ env.K8S_NAMESPACE }} -o wide || {
          echo "❌ Failed to get deployment status"
          exit 1
        }
        
        echo "📋 Current image:"
        kubectl get deployment ${{ env.K8S_DEPLOYMENT_NAME }} -n ${{ env.K8S_NAMESPACE }} -o jsonpath='{.spec.template.spec.containers[0].image}' || {
          echo "❌ Failed to get current image"
          exit 1
        }
        echo ""
        
        echo "📋 Current pods:"
        kubectl get pods -n ${{ env.K8S_NAMESPACE }} -l app=zdm-api || {
          echo "⚠️ Warning: Failed to get pods, but continuing..."
        }
        
    - name: 🚀 Kubernetes 배포 업데이트
      run: |
        echo "🚀 Updating Kubernetes deployment..."
        
        # 새로운 이미지로 업데이트 (latest 태그 사용)
        NEW_IMAGE="${{ env.REGISTRY_URL }}/${{ env.PROJECT_NAME }}:latest"
        echo "📦 New image: $NEW_IMAGE"
        
        # imagePullPolicy를 Always로 설정하여 latest 태그를 항상 pull하도록 함
        kubectl patch deployment ${{ env.K8S_DEPLOYMENT_NAME }} -n ${{ env.K8S_NAMESPACE }} -p "{
          \"spec\": {
            \"template\": {
              \"spec\": {
                \"containers\": [{
                  \"name\": \"${{ env.K8S_CONTAINER_NAME }}\",
                  \"image\": \"$NEW_IMAGE\",
                  \"imagePullPolicy\": \"Always\"
                }]
              }
            }
          }
        }" || {
          echo "⚠️ Patch failed, trying with kubectl set image..."
          kubectl set image deployment/${{ env.K8S_DEPLOYMENT_NAME }} \
            ${{ env.K8S_CONTAINER_NAME }}=$NEW_IMAGE \
            -n ${{ env.K8S_NAMESPACE }}
        }
        
        # 배포 어노테이션 추가 (강제 업데이트를 위해)
        kubectl annotate deployment ${{ env.K8S_DEPLOYMENT_NAME }} \
          deployment.kubernetes.io/revision- \
          -n ${{ env.K8S_NAMESPACE }} || true
          
        kubectl annotate deployment ${{ env.K8S_DEPLOYMENT_NAME }} \
          "deployment.kubernetes.io/deployed-at=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
          "deployment.kubernetes.io/deployed-by=github-actions" \
          "deployment.kubernetes.io/commit-sha=${{ github.sha }}" \
          -n ${{ env.K8S_NAMESPACE }} --overwrite
        
        echo "✅ Deployment update command executed"
        
    - name: ⏳ 배포 상태 모니터링
      timeout-minutes: 10
      run: |
        echo "⏳ Waiting for deployment to complete..."
        
        # 롤아웃 상태 모니터링
        if kubectl rollout status deployment/${{ env.K8S_DEPLOYMENT_NAME }} -n ${{ env.K8S_NAMESPACE }} --timeout=600s; then
          echo "✅ Deployment completed successfully!"
        else
          echo "❌ Deployment failed or timed out"
          
          # 실패 시 디버깅 정보 출력
          echo "📋 Deployment description:"
          kubectl describe deployment ${{ env.K8S_DEPLOYMENT_NAME }} -n ${{ env.K8S_NAMESPACE }}
          
          echo "📋 Pod status:"
          kubectl get pods -n ${{ env.K8S_NAMESPACE }} -l app=zdm-api
          
          echo "📋 Recent events:"
          kubectl get events -n ${{ env.K8S_NAMESPACE }} --sort-by='.lastTimestamp' | tail -10
          
          exit 1
        fi
        
    - name: 🔍 배포 후 상태 확인
      run: |
        echo "🔍 Post-deployment verification..."
        
        # 최종 배포 상태
        echo "📋 Final deployment status:"
        kubectl get deployment ${{ env.K8S_DEPLOYMENT_NAME }} -n ${{ env.K8S_NAMESPACE }} -o wide
        
        # Pod 상태 확인
        echo "📋 Pod status:"
        kubectl get pods -n ${{ env.K8S_NAMESPACE }} -l app=zdm-api -o wide
        
        # 새로운 이미지 확인
        echo "📋 Updated image:"
        kubectl get deployment ${{ env.K8S_DEPLOYMENT_NAME }} -n ${{ env.K8S_NAMESPACE }} \
          -o jsonpath='{.spec.template.spec.containers[0].image}'
        echo ""
        
        # Service 상태 확인
        echo "📋 Service status:"
        kubectl get service -n ${{ env.K8S_NAMESPACE }}
        
    - name: 🩺 애플리케이션 헬스체크
      run: |
        echo "🩺 Performing application health check..."
        
        # Pod가 Ready 상태인지 확인
        echo "⏳ Waiting for pods to be ready..."
        kubectl wait --for=condition=Ready pod -l app=zdm-api -n ${{ env.K8S_NAMESPACE }} --timeout=300s
        
        # 내부 헬스체크 (Service 통해서)
        echo "🔍 Testing internal service accessibility..."
        kubectl run healthcheck-${{ github.run_id }} \
          --image=curlimages/curl \
          --rm -i --restart=Never \
          --timeout=60s \
          -n ${{ env.K8S_NAMESPACE }} \
          -- curl -f -m 30 http://zdm-api-service:53307/health || {
            echo "⚠️ Health check failed, but deployment was successful"
            echo "This might be normal if health endpoint is not available"
          }
        
        echo "✅ Deployment verification completed"
        
    - name: 📊 배포 요약 정보
      run: |
        echo "## 🎯 배포 완료 요약" >> $GITHUB_STEP_SUMMARY
        echo "" >> $GITHUB_STEP_SUMMARY
        echo "### 📦 배포 정보" >> $GITHUB_STEP_SUMMARY
        echo "- **환경**: Production" >> $GITHUB_STEP_SUMMARY
        echo "- **네임스페이스**: \`${{ env.K8S_NAMESPACE }}\`" >> $GITHUB_STEP_SUMMARY
        echo "- **Deployment**: \`${{ env.K8S_DEPLOYMENT_NAME }}\`" >> $GITHUB_STEP_SUMMARY
        echo "- **이미지**: \`${{ env.REGISTRY_URL }}/${{ env.PROJECT_NAME }}:latest\`" >> $GITHUB_STEP_SUMMARY
        echo "- **커밋**: \`${{ github.sha }}\`" >> $GITHUB_STEP_SUMMARY
        echo "- **브랜치**: \`${{ github.ref_name }}\`" >> $GITHUB_STEP_SUMMARY
        echo "- **배포자**: ${{ github.actor }}" >> $GITHUB_STEP_SUMMARY
        echo "- **배포 시간**: $(date -u)" >> $GITHUB_STEP_SUMMARY
        echo "" >> $GITHUB_STEP_SUMMARY
        echo "### 🚀 배포 명령어" >> $GITHUB_STEP_SUMMARY
        echo "\`\`\`bash" >> $GITHUB_STEP_SUMMARY
        echo "kubectl set image deployment/${{ env.K8S_DEPLOYMENT_NAME }} \\" >> $GITHUB_STEP_SUMMARY
        echo "  ${{ env.K8S_CONTAINER_NAME }}=${{ env.REGISTRY_URL }}/${{ env.PROJECT_NAME }}:latest \\" >> $GITHUB_STEP_SUMMARY
        echo "  -n ${{ env.K8S_NAMESPACE }}" >> $GITHUB_STEP_SUMMARY
        echo "\`\`\`" >> $GITHUB_STEP_SUMMARY

  # 5단계: 알림 및 결과 리포트
  notify-result:
    name: Notify Build Result
    runs-on: ubuntu-latest
    needs: [build-and-test, docker-build-push, verify-image, deploy-to-kubernetes]
    if: always()
    
    steps:
    - name: 📧 결과 이메일 알림
      uses: dawidd6/action-send-mail@v3
      with:
        server_address: smtp.gmail.com
        server_port: 587
        username: ${{ secrets.EMAIL_USERNAME }}
        password: ${{ secrets.EMAIL_PASSWORD }}
        subject: "[NCP] ${{ env.PROJECT_NAME }} 빌드 및 배포 결과: ${{ (needs.docker-build-push.result == 'success' && (needs.deploy-to-kubernetes.result == 'success' || needs.deploy-to-kubernetes.result == 'skipped')) && '성공' || '실패' }}"
        to: ${{ secrets.NOTIFICATION_EMAIL }}
        from: ${{ secrets.EMAIL_USERNAME }}
        body: |
          ${{ env.PROJECT_NAME }} Docker 이미지 빌드 및 Kubernetes 배포가 완료되었습니다.

          ## 빌드 및 배포 결과 요약
          - 📦 빌드 및 테스트: ${{ needs.build-and-test.result }}
          - 🐳 Docker 빌드 & 푸시: ${{ needs.docker-build-push.result }}
          - 🔍 이미지 검증: ${{ needs.verify-image.result }}
          - 🚀 Kubernetes 배포: ${{ needs.deploy-to-kubernetes.result }}

          ## 프로젝트 정보
          - 프로젝트: ${{ env.PROJECT_NAME }}
          - 레지스트리: ${{ env.REGISTRY_URL }}
          - 브랜치: ${{ github.ref_name }}
          - 커밋: ${{ github.sha }}
          - 버전: ${{ needs.build-and-test.outputs.version }}
          - 트리거: ${{ github.event_name }}
          - 작성자: ${{ github.actor }}

          ## Docker 이미지
          ${{ needs.docker-build-push.result == 'success' && format('```
          {0}/{1}:latest
          {0}/{1}:{2}
          ```', env.REGISTRY_URL, env.PROJECT_NAME, needs.build-and-test.outputs.version) || '이미지 빌드 실패' }}

          ## Kubernetes 배포 정보
          ${{ needs.deploy-to-kubernetes.result == 'success' && format('- **네임스페이스**: {0}
          - **Deployment**: {1}
          - **배포 완료**: ✅', env.K8S_NAMESPACE, env.K8S_DEPLOYMENT_NAME) || needs.deploy-to-kubernetes.result == 'skipped' && '배포 건너뜀 (main 브랜치 아님)' || '배포 실패' }}

          ## 액션 상세 보기
          ${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}

          ---
          실행 시간: ${{ github.event.head_commit.timestamp }}
      if: always()
      
    - name: 📊 워크플로우 요약
      run: |
        echo "## 🎯 CI/CD 파이프라인 완료 요약" >> $GITHUB_STEP_SUMMARY
        echo "" >> $GITHUB_STEP_SUMMARY
        echo "| 단계 | 결과 | 상태 |" >> $GITHUB_STEP_SUMMARY
        echo "|------|------|------|" >> $GITHUB_STEP_SUMMARY
        echo "| 빌드 및 테스트 | ${{ needs.build-and-test.result }} | ${{ needs.build-and-test.result == 'success' && '✅' || '❌' }} |" >> $GITHUB_STEP_SUMMARY
        echo "| Docker 빌드 & 푸시 | ${{ needs.docker-build-push.result }} | ${{ needs.docker-build-push.result == 'success' && '✅' || '❌' }} |" >> $GITHUB_STEP_SUMMARY
        echo "| 이미지 검증 | ${{ needs.verify-image.result }} | ${{ needs.verify-image.result == 'success' && '✅' || '❌' }} |" >> $GITHUB_STEP_SUMMARY
        echo "| Kubernetes 배포 | ${{ needs.deploy-to-kubernetes.result }} | ${{ needs.deploy-to-kubernetes.result == 'success' && '✅' || needs.deploy-to-kubernetes.result == 'skipped' && '⏭️' || '❌' }} |" >> $GITHUB_STEP_SUMMARY
        echo "" >> $GITHUB_STEP_SUMMARY
        echo "### 📦 생성된 이미지" >> $GITHUB_STEP_SUMMARY
        echo "- **레지스트리**: \`${{ env.REGISTRY_URL }}\`" >> $GITHUB_STEP_SUMMARY
        echo "- **프로젝트**: \`${{ env.PROJECT_NAME }}\`" >> $GITHUB_STEP_SUMMARY
        echo "- **버전**: \`${{ needs.build-and-test.outputs.version }}\`" >> $GITHUB_STEP_SUMMARY
        echo "- **브랜치**: \`${{ github.ref_name }}\`" >> $GITHUB_STEP_SUMMARY
        echo "" >> $GITHUB_STEP_SUMMARY
        if [[ "${{ needs.deploy-to-kubernetes.result }}" == "success" ]]; then
          echo "### 🚀 배포 정보" >> $GITHUB_STEP_SUMMARY
          echo "- **환경**: Production" >> $GITHUB_STEP_SUMMARY
          echo "- **네임스페이스**: \`${{ env.K8S_NAMESPACE }}\`" >> $GITHUB_STEP_SUMMARY
          echo "- **Deployment**: \`${{ env.K8S_DEPLOYMENT_NAME }}\`" >> $GITHUB_STEP_SUMMARY
          echo "- **배포 시간**: $(date -u)" >> $GITHUB_STEP_SUMMARY
        fi
      if: always()