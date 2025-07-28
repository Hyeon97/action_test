"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const dotenv_1 = __importDefault(require("dotenv"));
const express_1 = __importDefault(require("express"));
// 환경변수 로드
dotenv_1.default.config();
const app = (0, express_1.default)();
const PORT = parseInt(process.env.PORT || '53307', 10);
// JSON 파싱 미들웨어
app.use(express_1.default.json());
// GET "/" 엔드포인트
app.get('/', (req, res) => {
    res.send('Server is Running in NKS (3).');
});
// 서버 시작
app.listen(PORT, () => {
    console.log(`Server is running on port ${PORT}`);
    console.log(`Visit: http://localhost:${PORT}`);
});
exports.default = app;
//# sourceMappingURL=server.js.map