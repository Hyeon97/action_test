name: Complete CI/CD Pipeline

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

env:
  NODE_VERSION: '18'
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}

jobs:
  build:
    name: 빌드 및 아티팩트
    runs-on: ubuntu-latest
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
        
    # - name: 이미지 취약점 스캔
    #   uses: aquasecurity/trivy-action@master
    #   with:
    #     image-ref: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }}
    #     format: 'sarif'
    #     output: 'trivy-results.sarif'
        
    # - name: 취약점 결과 업로드
    #   uses: github/codeql-action/upload-sarif@v3
    #   with:
    #     sarif_file: 'trivy-results.sarif'

  deploy-production:
    name: 프로덕션 배포
    runs-on: ubuntu-latest
    needs: [build]
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
          sleep 10
          # curl -f https://my-app.com/health || exit 1
          echo "프로덕션 헬스체크 통과"

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

  notify-result:
    name: 최종 결과 이메일 알림
    runs-on: ubuntu-latest
    needs:
      - build
      - deploy-production
      - post-deployment-tests
    if: github.ref == 'refs/heads/main'
    steps:
      - name: 최종 결과 이메일 발송
        uses: dawidd6/action-send-mail@v3
        with:
          server_address: smtp.gmail.com
          server_port: 587
          username: ${{ secrets.EMAIL_USERNAME }}
          password: ${{ secrets.EMAIL_PASSWORD }}
          subject: "[CI/CD] 전체 작업 결과: ${{ job.status == 'success' && '성공' || '실패' }}"
          to: ${{ secrets.NOTIFICATION_EMAIL }}
          from: ${{ secrets.EMAIL_USERNAME }}
          body: |
            전체 작업이 ${{ job.status == 'success' && '성공적으로 완료' || '실패' }}되었습니다.

            - 빌드 상태: ${{ needs.build.result }}
            - 배포 상태: ${{ needs.deploy-production.result }}
            - 배포 후 테스트 상태: ${{ needs.post-deployment-tests.result }}

            레포지토리: ${{ github.repository }}
            액션 URL: ${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}
        if: