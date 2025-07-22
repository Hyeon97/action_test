module.exports = {
  testEnvironment: 'node',
  collectCoverage: true,
  coverageDirectory: 'coverage',
  coverageReporters: ['text', 'lcov', 'html'],
  collectCoverageFrom: [
    '*.js',
    '!jest.config.js',
    '!coverage/**'
  ],
  testMatch: [
    '**/*.test.js'
  ],
  verbose: true,
  testTimeout: 30000,
  // Puppeteer 테스트를 위한 설정
  setupFilesAfterEnv: [],
  // CI 환경에서의 설정
  ...(process.env.CI && {
    maxWorkers: 2,
    coverageThreshold: {
      global: {
        branches: 50,
        functions: 50,
        lines: 50,
        statements: 50
      }
    }
  })
}