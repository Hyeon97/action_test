const puppeteer = require('puppeteer')

const page = ['http://127.0.0.1']


const FUNC = (async (path) => {
    console.info("start")
    const browser = await puppeteer.launch({
        headless: false,
        // 디폴트가 headless 라서 브라우저가 보이지 않으므로 false 해야 브라우저가 보임.

        executablePath: '',
        // 디폴트가 puppetter 내장된 크롬 브라우저를 이용하므로 실행PC의 브라우저로 재설정

        args: ["--window-size=1280,1080"]
        // args: ['--start-maximized']

        //  testddddddㅇㄴㅇㄹㄴㅇ

    })

    const page = await browser.newPage()
    await page.goto(path)        // 테스트할 사이즈 주소입력
    await page.setViewport({

        width: 1280,               // 페이지 너비

        height: 1080,                // 페이지 높이

        deviceScaleFactor: 1,     // 기기 배율 요소를 지정 DPR( Device Pixel Resolution )

        isMobile: false,            // 모바일

        hasTouch: false,           // 터치 이벤트 발생여부

        isLandscape: false,        //

    })
    // const dimensions = await page.evaluate(() => {
    //     return {
    //       width: document.documentElement.clientWidth,
    //       height: document.documentElement.clientHeight,
    //       deviceScaleFactor: window.devicePixelRatio,
    //     };
    //   });

    //   console.log('Dimensions:', dimensions);

    await page.waitForTimeout(3000)     // 눈으로 확인하기 위해 3초간 멈춤
    // await browser.close();              // 브라우저 종료
})


// for(let el of page){
//     FUNC(el)
// }
FUNC(page[0])

