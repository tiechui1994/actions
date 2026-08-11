const puppeteer = require('puppeteer');

async function run(proxy = '') {
    try{
        const opt = {
            headless: true,
            args: [
                '--disable-gpu', // GPU
                '--disable-dev-shm-usage', // TEMP FILE SHARE
                '--disable-setuid-sandbox', // UID SANDBOX
                '--no-first-run', // FIRST PAGE
                '--no-sandbox',
                '--user-agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36"',
            ]
        };
        if (proxy !== '') {
            opt.args.push('--proxy-server='+proxy)
        }

        const browser = await puppeteer.launch(opt);

        const page = await browser.newPage();

        await page.goto('https://streams.streamlit.app/', {
            waitUntil: 'domcontentloaded',
            timeout: 60000,
        });

        const waitForStatus = (pathname, method) => {
            return new Promise((resolve, reject) => {
                const timeout = setTimeout(() => {
                    page.off('response');
                    reject(new Error(`等待目标请求 [${pathname}] 超时`));
                }, 60000);

                const responseHandler = async (response) => {
                    const request = response.request();
                    const url = new URL(response.url());  
                    const headers = response.headers();
                    if (url.pathname == pathname && request.method() == method) {
                        console.log(`捕获到目标 Response: ${url}`);                        
                        page.off('response');
                        clearTimeout(timeout);
                        const status = await response.json()
                        resolve(status);
                    }
                };

                // 注册监听器
                page.on('response', responseHandler);
            });
        };

        // https://xxx/api/v2/app/status
        const status = await waitForStatus('/api/v2/app/status', 'GET')
        console.log('current status:', JSON.stringify(status))
        if (status.status === 5) {
            await new Promise(resolve => setTimeout(resolve, 30000));
            console.log('保活/唤醒操作完成');

            await browser.close()
            console.info("loginout .....");
            return
        }

        const wakeButtonSelector = 'button:has-text("Yes, wake it up!"), button:has-text("Wake app up"), button:has-text("Yes, get this app back up!")';
        // 寻找页面中的唤醒按钮
        const wakeButton = await page.$(wakeButtonSelector).catch(() => null);
        if (wakeButton) {
            console.log('检测到应用处于休眠状态, 正在自动点击唤醒按钮...');
            await wakeButton.click();
            // 唤醒通常需要一段时间，等待页面加载完成
            await page.waitForNavigation({ waitUntil: 'networkidle2', timeout: 60000 }).catch(() => {});
        } else {
            console.log('应用处于活跃状态或未触发休眠弹窗.');
        }

        // 关键点：保持页面打开 30 秒，确保 WebSocket 完成握手与心跳维持
        console.log('等待 ws 握手与心跳同步...');
        await new Promise(resolve => setTimeout(resolve, 30000));
        console.log('保活/唤醒操作完成');

        await browser.close()
        console.info("loginout .....");
    } catch(e) {
        console.warn('warn', e)
    }
}

(async() => {
    const args = process.argv.slice(2);

    const proxyArg = args.find(arg => arg.startsWith('--proxy='));
    const proxy = proxyArg ? proxyArg.split('=')[1] : '';

    await run(proxy)
})()
