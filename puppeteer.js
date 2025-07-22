const puppeteer = require('puppeteer')

const pages = ['http://127.0.0.1:8080', 'https://example.com']

const FUNC = async (path) => {
    console.info("Puppeteer automation started")
    console.info(`Testing URL: ${path}`)

    try {
        const browser = await puppeteer.launch({
            headless: process.env.NODE_ENV === 'production' ? 'new' : false,
            // CI 환경에서는 headless 모드로 실행

            args: [
                "--no-sandbox",
                "--disable-setuid-sandbox",
                "--disable-dev-shm-usage",
                "--disable-accelerated-2d-canvas",
                "--no-first-run",
                "--no-zygote",
                "--disable-gpu",
                "--window-size=1280,1080"
            ]
            // CI 환경을 위한 Chrome 플래그 추가
        })

        const page = await browser.newPage()

        await page.setViewport({
            width: 1280,               // 페이지 너비
            height: 1080,              // 페이지 높이
            deviceScaleFactor: 1,      // 기기 배율 요소를 지정 DPR(Device Pixel Resolution)
            isMobile: false,           // 모바일
            hasTouch: false,           // 터치 이벤트 발생여부
            isLandscape: false,        // 가로 모드
        })

        // 페이지 로드 및 기본 테스트
        if (path.startsWith('http')) {
            try {
                await page.goto(path, { waitUntil: 'networkidle0', timeout: 30000 })
                console.info(`Successfully loaded: ${path}`)

                // 페이지 타이틀 가져오기
                const title = await page.title()
                console.info(`Page title: ${title}`)

                // 스크린샷 찍기 (CI 환경에서도 작동)
                await page.screenshot({
                    path: `screenshot-${Date.now()}.png`,
                    fullPage: true
                })
                console.info("Screenshot captured")

            } catch (error) {
                console.error(`Failed to load ${path}:`, error.message)
            }
        } else {
            // 로컬 파일이나 다른 형태의 URL 처리
            console.info(`Skipping non-HTTP URL: ${path}`)
        }

        await page.waitForTimeout(3000)     // 3초간 대기
        await browser.close()               // 브라우저 종료
        console.info("Browser closed successfully")

    } catch (error) {
        console.error("Puppeteer execution failed:", error)
        process.exit(1)
    }
}

// 메인 실행 함수
const runTests = async () => {
    console.info("Starting Puppeteer automation tests...")

    for (const pageUrl of pages) {
        await FUNC(pageUrl)
    }

    console.info("All tests completed successfully")
}

// 모듈로 호출되지 않은 경우에만 실행
if (require.main === module) {
    runTests()
}

module.exports = { FUNC, runTests }