# Node.js 22 사용
FROM node:22-alpine

# 작업 디렉토리 설정
WORKDIR /app

# 환경변수 설정 (기본값)
ENV PORT=53307

# package.json과 package-lock.json 복사
COPY package*.json ./

# 의존성 설치
RUN npm install

# 소스 코드 복사
COPY . .

# TypeScript 빌드
RUN npm run build

# 포트 노출 (환경변수 사용)
EXPOSE $PORT

# 서버 실행
CMD ["npm", "start"]