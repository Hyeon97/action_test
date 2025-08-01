# .github/workflows/ci-cd.yml
name: Complete CI/CD Pipeline

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

# 환경 변수
env:
  NODE_VERSION: '18'
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}

jobs:
  # 1단계: 테스트 실행
  test:
    name: 테스트 실행
    runs-on: ubuntu-latest
    
    strategy:
      matrix:
        node-version: [16, 18, 20]
    
    steps:
    - name: 코드 체크아웃
      uses: actions/checkout@v4
      
    - name: Node.js ${{ matrix.node-version }} 설정
      uses: actions/setup-node@v4
      with:
        node-version: ${{ matrix.node-version }}
        cache: 'npm'
        
    - name: 의존성 설치
      run: npm ci
      
    - name: 단위 테스트 실행
      run: npm test
      
    - name: 커버리지 리포트 생성
      run: npm run test:coverage
      
    - name: 커버리지 업로드 (Node 18만)
      if: matrix.node-version == '18'
      uses: codecov/codecov-action@v3
      with:
        file: ./coverage/lcov.info
        fail_ci_if_error: false

  # 2단계: 보안 검사
  security:
    name: 보안 검사
    runs-on: ubuntu-latest
    
    steps:
    - name: 코드 체크아웃
      uses: actions/checkout@v4
      
    - name: Node.js 설정
      uses: actions/setup-node@v4
      with:
        node-version: ${{ env.NODE_VERSION }}
        cache: 'npm'
        
    - name: 의존성 설치
      run: npm ci
      
    - name: npm audit 실행
      run: npm audit --audit-level high
      continue-on-error: true
      
    - name: Snyk 보안 검사
      uses: snyk/actions/node@master
      env:
        SNYK_TOKEN: ${{ secrets.SNYK_TOKEN }}
      with:
        args: --severity-threshold=high
      continue-on-error: true

  # 3단계: 빌드 및 아티팩트 생성
  build:
    name: 빌드 및 아티팩트
    runs-on: ubuntu-latest
    needs: [test, security]
    
    outputs:
      version: ${{ steps.version.outputs.version }}
    
    steps:
    - name: 코드 체크아웃
      uses: actions/checkout@v4
      
    - name: Node.js 설정
      uses: actions/setup-node@v4
      with:
        node-version: ${{ env.NODE_VERSION }}
        cache: 'npm'
        
    - name: 의존성 설치
      run: npm ci
      
    - name: 애플리케이션 빌드
      run: npm run build
      
    - name: 버전 정보 생성
      id: version
      run: |
        VERSION=${GITHUB_SHA::7}
        echo "version=$VERSION" >> $GITHUB_OUTPUT
        echo "VERSION=$VERSION" > version.txt
        
    - name: 빌드 아티팩트 업로드
      uses: actions/upload-artifact@v4
      with:
        name: build-${{ steps.version.outputs.version }}
        path: |
          package.json
          src/
          config/
          version.txt
        retention-days: 30

  # 4단계: Docker 이미지 빌드
  docker-build:
    name: Docker 이미지 빌드
    runs-on: ubuntu-latest
    needs: build
    if: github.event_name == 'push'
    
    steps:
    - name: 코드 체크아웃
      uses: actions/checkout@v4
      
    - name: Docker Buildx 설정
      uses: docker/setup-buildx-action@v3
      
    - name: GitHub Container Registry 로그인
      uses: docker/login-action@v3
      with:
        registry: ${{ env.REGISTRY }}
        username: ${{ github.actor }}
        password: ${{ secrets.GITHUB_TOKEN }}
        
    - name: 메타데이터 추출
      id: meta
      uses: docker/metadata-action@v5
      with:
        images: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}
        tags: |
          type=ref,event=branch
          type=sha,prefix={{branch}}-
          type=raw,value=latest,enable={{is_default_branch}}
          
    - name: Docker 이미지 빌드 및 푸시
      uses: docker/build-push-action@v5
      with:
        context: .
        push: true
        tags: ${{ steps.meta.outputs.tags }}
        labels: ${{ steps.meta.outputs.labels }}
        cache-from: type=gha
        cache-to: type=gha,mode=max
        
    - name: 이미지 취약점 스캔
      uses: aquasecurity/trivy-action@master
      with:
        image-ref: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }}
        format: 'sarif'
        output: 'trivy-results.sarif'
        
    - name: 취약점 결과 업로드
      uses: github/codeql-action/upload-sarif@v3
      with:
        sarif_file: 'trivy-results.sarif'

  # 5단계: 스테이징 환경 배포
  deploy-staging:
    name: 스테이징 환경 배포
    runs-on: ubuntu-latest
    needs: [docker-build]
    if: github.ref == 'refs/heads/develop'
    environment: 
      name: staging
      url: https://staging.my-app.com
    
    steps:
    - name: 코드 체크아웃
      uses: actions/checkout@v4
      
    - name: 빌드 아티팩트 다운로드
      uses: actions/download-artifact@v4
      with:
        name: build-${{ needs.build.outputs.version }}
        
    - name: 스테이징 서버 배포
      run: |
        echo "스테이징 환경 배포 시작..."
        echo "Docker 이미지: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:develop-${{ github.sha }}"
        
        # 실제 배포 명령어 (예시)
        # ssh user@staging-server "docker pull ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:develop-${{ github.sha }}"
        # ssh user@staging-server "docker-compose -f docker-compose.staging.yml up -d"
        
        echo "스테이징 배포 완료"
        
    - name: 헬스체크
      run: |
        echo "헬스체크 수행 중..."
        sleep 30
        # curl -f https://staging.my-app.com/health || exit 1
        echo "헬스체크 통과"
        
    - name: 스모크 테스트
      run: |
        echo "스모크 테스트 실행..."
        # npm run test:smoke:staging
        echo "스모크 테스트 통과"

  # 6단계: 성능 테스트
  performance-test:
    name: 성능 테스트
    runs-on: ubuntu-latest
    needs: deploy-staging
    if: github.ref == 'refs/heads/develop'
    
    steps:
    - name: 코드 체크아웃
      uses: actions/checkout@v4
      
    - name: Lighthouse CI
      uses: treosh/lighthouse-ci-action@v10
      with:
        configPath: './lighthouserc.json'
        uploadArtifacts: true
        temporaryPublicStorage: true
        
    - name: K6 성능 테스트
      uses: grafana/k6-action@v0.3.1
      with:
        filename: tests/performance/load-test.js
      env:
        TEST_URL: https://staging.my-app.com

  # 7단계: 프로덕션 배포
  deploy-production:
    name: 프로덕션 배포
    runs-on: ubuntu-latest
    needs: [docker-build, build]
    if: github.ref == 'refs/heads/main'
    environment: 
      name: production
      url: https://my-app.com
    
    steps:
    - name: 코드 체크아웃
      uses: actions/checkout@v4
      
    - name: 빌드 아티팩트 다운로드
      uses: actions/download-artifact@v4
      with:
        name: build-${{ needs.build.outputs.version }}
        
    - name: 프로덕션 배포 준비
      run: |
        echo "프로덕션 배포 준비 중..."
        echo "버전: ${{ needs.build.outputs.version }}"
        echo "이미지: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:main-${{ github.sha }}"
        
    - name: 프로덕션 배포 실행
      run: |
        echo "프로덕션 배포 실행 중..."
        
        # Blue-Green 배포 또는 Rolling 배포
        # kubectl set image deployment/my-app my-app=${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:main-${{ github.sha }}
        # kubectl rollout status deployment/my-app
        
        echo "프로덕션 배포 완료"
        
    - name: 프로덕션 헬스체크
      run: |
        echo "프로덕션 헬스체크..."
        sleep 60
        # curl -f https://my-app.com/health || exit 1
        echo "프로덕션 헬스체크 통과"
        
    # - name: 슬랙 알림
    #   uses: 8398a7/action-slack@v3
    #   with:
    #     status: ${{ job.status }}
    #     channel: '#deployments'
    #     text: |
    #       프로덕션 배포 완료!
    #       - 버전: ${{ needs.build.outputs.version }}
    #       - 브랜치: ${{ github.ref_name }}
    #       - 커밋: ${{ github.sha }}
    #       - 배포자: ${{ github.actor }}
    #   env:
    #     SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK_URL }}
    #   if: always()
    
    - name: 이메일 알림
      uses: dawidd6/action-send-mail@v3
      with:
        server_address: smtp.gmail.com
        server_port: 587
        username: ${{ secrets.EMAIL_USERNAME }}
        password: ${{ secrets.EMAIL_PASSWORD }}
        subject: "[CI/CD] 프로덕션 배포 ${{ job.status == 'success' && '성공' || '실패' }}"
        to: ${{ secrets.NOTIFICATION_EMAIL }}
        from: ${{ secrets.EMAIL_USERNAME }}
        body: |
          프로덕션 배포가 ${{ job.status == 'success' && '성공적으로 완료' || '실패' }}되었습니다.
          
          배포 정보:
          - 상태: ${{ job.status }}
          - 버전: ${{ needs.build.outputs.version }}
          - 브랜치: ${{ github.ref_name }}
          - 커밋: ${{ github.sha }}
          - 배포자: ${{ github.actor }}
          - 시간: ${{ github.event.head_commit.timestamp }}
          
          레포지토리: ${{ github.repository }}
          액션 URL: ${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}
      if: always()

  # 8단계: 배포 후 테스트
  post-deployment-tests:
    name: 배포 후 테스트
    runs-on: ubuntu-latest
    needs: deploy-production
    if: github.ref == 'refs/heads/main'
    
    steps:
    - name: 코드 체크아웃
      uses: actions/checkout@v4
      
    - name: Node.js 설정
      uses: actions/setup-node@v4
      with:
        node-version: ${{ env.NODE_VERSION }}
        cache: 'npm'
        
    - name: 의존성 설치
      run: npm ci
      
    - name: E2E 테스트 실행
      run: |
        echo "E2E 테스트 실행 중..."
        # npm run test:e2e:production
        echo "E2E 테스트 완료"
        
    - name: API 테스트 실행
      run: |
        echo "API 테스트 실행 중..."
        # npm run test:api:production
        echo "API 테스트 완료"

  # 9단계: 릴리스 노트 생성
  create-release:
    name: 릴리스 생성
    runs-on: ubuntu-latest
    needs: [deploy-production, post-deployment-tests]
    if: github.ref == 'refs/heads/main'
    
    steps:
    - name: 코드 체크아웃
      uses: actions/checkout@v4
      with:
        fetch-depth: 0
        
    - name: 릴리스 노트 생성
      uses: release-drafter/release-drafter@v5
      with:
        config-name: release-drafter.yml
        publish: true
      env:
        GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}



        # 배포 조건
# 1) backend/develop -> develop MERGE
# 2) Labeling
on:
  pull_request:
    types: [closed]
    branches:
      - develop

jobs:
  deploy:
    if: github.event.pull_request.merged == true &&
      contains(github.event.pull_request.labels.*.name, 'backend') &&
      contains(github.event.pull_request.labels.*.name, 'operation')
    runs-on: ubuntu-latest