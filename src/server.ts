import dotenv from 'dotenv'
import express, { Request, Response } from 'express'

// 환경변수 로드
dotenv.config()

const app = express()
const PORT = parseInt(process.env.PORT || '53307', 10)

// JSON 파싱 미들웨어
app.use(express.json())

// GET "/" 엔드포인트
app.get('/', (req: Request, res: Response) => {
  res.send('Server is Running in NKS.')
})

// 서버 시작
app.listen(PORT, () => {
  console.log(`Server is running on port ${PORT}`)
  console.log(`Visit: http://localhost:${PORT}`)
})

export default app