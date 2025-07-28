# 멀티스테이지 빌드 - 빌드 스테이지
FROM node:22-alpine AS builder

WORKDIR /app

# package.json과 package-lock.json 복사
COPY package*.json ./

# 의존성 설치 (dev dependencies 포함)
RUN npm ci

# 소스 코드 복사
COPY . .

# TypeScript 빌드
RUN npm run build

# 프로덕션 스테이지
FROM node:22-alpine AS production

# 보안을 위한 패키지 업데이트
RUN apk update && apk upgrade && apk add --no-cache dumb-init

# 비특권 사용자 생성
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nextjs -u 1001

WORKDIR /app

# package.json 복사
COPY package*.json ./

# 프로덕션 의존성만 설치
RUN npm ci --only=production && npm cache clean --force

# 빌드된 애플리케이션 복사
COPY --from=builder --chown=nextjs:nodejs /app/dist ./dist

# 환경변수 설정
ENV NODE_ENV=production
ENV PORT=53307

# 비특권 사용자로 전환
USER nextjs

# 헬스체크 추가
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD node -e "require('http').get('http://localhost:$PORT/', (res) => { process.exit(res.statusCode === 200 ? 0 : 1) })"

# 포트 노출
EXPOSE $PORT

# dumb-init을 사용하여 시그널 처리 개선
ENTRYPOINT ["dumb-init", "--"]

# 서버 실행
CMD ["node", "dist/server.js"]