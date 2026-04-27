const { chromium } = require('playwright');

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage();
  
  const routes = ['/', '/download', '/pricing', '/legal'];
  
  for (const route of routes) {
    await page.goto(`http://localhost:3000${route}`);
    await page.waitForTimeout(2000);
    
    const text = await page.evaluate(() => document.body.innerText);
    console.log(`\n=== Route: ${route} ===`);
    console.log(text.substring(0, 500));
  }
  
  await browser.close();
})();
