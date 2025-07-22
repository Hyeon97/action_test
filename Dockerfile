# Puppeteer를 위한 Node.js 20 알파인 이미지 사용
FROM node:20-alpine

# Puppeteer에 필요한 Chrome/Chromium 의존성 설치
RUN apk add --no-cache \
    chromium \
    nss \
    freetype \
    harfbuzz \
    ca-certificates \
    ttf-freefont \
    && rm -rf /var/cache/apk/*

# Puppeteer에게 설치된 Chromium 실행 파일 경로 알려주기
ENV PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium-browser

# Chrome이 샌드박스 모드에서 실행되지 않도록 설정
ENV CHROME_BIN=/usr/bin/chromium-browser
ENV CHROME_PATH=/usr/bin/chromium-browser

# 작업 디렉토리 설정
WORKDIR /app

# package.json과 package-lock.json 복사
COPY package*.json ./

# npm 의존성 설치 (Puppeteer는 Chromium 다운로드 건너뛰기)
ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true
RUN npm ci --only=production

# 애플리케이션 코드 복사
COPY . .

# 포트 노출 (필요한 경우)
EXPOSE 3000

# 헬스체크 (선택사항)
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD node --version || exit 1

# 사용자 권한 설정 (보안을 위해)
RUN addgroup -g 1001 -S nodejs
RUN adduser -S nextjs -u 1001

# 애플리케이션 파일 소유권 변경
RUN chown -R nextjs:nodejs /app
USER nextjs

# 애플리케이션 실행
CMD ["npm", "start"]