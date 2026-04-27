const { chromium } = require('playwright');

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage();
  await page.goto('http://localhost:3000/');
  await page.waitForTimeout(2000);
  
  const styles = await page.evaluate(() => {
    const body = document.body;
    const h1 = document.querySelector('h1, h2');
    return {
      bodyFontFamily: getComputedStyle(body).fontFamily,
      bodyBackground: getComputedStyle(body).backgroundColor,
      bodyColor: getComputedStyle(body).color,
      h1FontFamily: h1 ? getComputedStyle(h1).fontFamily : 'no h1 found',
    };
  });
  
  console.log('Styles:', styles);
  
  await browser.close();
})();
