const { FUNC } = require('./puppeteer')

// Jest 설정
jest.setTimeout(30000) // 30초 타임아웃

describe('Puppeteer Automation Tests', () => {
  test('should export FUNC function', () => {
    expect(typeof FUNC).toBe('function')
  })

  test('should handle valid HTTP URL', async () => {
    // console.log를 모킹하여 로그 출력 확인
    const consoleSpy = jest.spyOn(console, 'info').mockImplementation()

    await FUNC('https://example.com')

    expect(consoleSpy).toHaveBeenCalledWith('Puppeteer automation started')
    expect(consoleSpy).toHaveBeenCalledWith('Testing URL: https://example.com')

    consoleSpy.mockRestore()
  })

  test('should handle invalid URL gracefully', async () => {
    const consoleSpy = jest.spyOn(console, 'info').mockImplementation()

    await FUNC('invalid-url')

    expect(consoleSpy).toHaveBeenCalledWith('Skipping non-HTTP URL: invalid-url')

    consoleSpy.mockRestore()
  })

  test('should capture screenshot for valid URLs', async () => {
    const fs = require('fs')

    await FUNC('https://example.com')

    // 스크린샷 파일이 생성되었는지 확인 (일반적인 패턴으로)
    const files = fs.readdirSync('.')
    const screenshotFiles = files.filter(file => file.startsWith('screenshot-') && file.endsWith('.png'))

    expect(screenshotFiles.length).toBeGreaterThan(0)

    // 테스트 후 스크린샷 파일 정리
    screenshotFiles.forEach(file => {
      try {
        fs.unlinkSync(file)
      } catch (error) {
        // 파일 삭제 실패는 무시
      }
    })
  })
})

describe('Basic Application Tests', () => {
  test('should have correct package name', () => {
    const packageJson = require('./package.json')
    expect(packageJson.name).toBe('action_test')
  })

  test('should have puppeteer dependency', () => {
    const packageJson = require('./package.json')
    expect(packageJson.dependencies).toHaveProperty('puppeteer')
  })

  test('should have required scripts', () => {
    const packageJson = require('./package.json')
    expect(packageJson.scripts).toHaveProperty('test')
    expect(packageJson.scripts).toHaveProperty('build')
    expect(packageJson.scripts).toHaveProperty('start')
  })
})