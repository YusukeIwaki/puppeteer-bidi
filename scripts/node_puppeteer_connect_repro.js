// Repro script for Puppeteer's `connect` behavior (BiDi).
//
// Run:
//   DEBUG=puppeteer:* node scripts/node_puppeteer_connect_repro.js
//
// Notes:
// - Requires `puppeteer` to be available (e.g. `npm i puppeteer` in a temp dir).
// - For Firefox BiDi, you likely need:
//     npx puppeteer browsers install firefox
//
// This script launches a browser, disconnects, then reconnects via `puppeteer.connect`.

/* eslint-disable no-console */

const puppeteer = require('puppeteer');

async function main() {
  // Try Firefox first since this Ruby project targets pure WebDriver BiDi.
  // If your Puppeteer version doesn't support Firefox in this environment,
  // set BROWSER=chrome to use BiDi-over-CDP instead.
  const browserName = process.env.BROWSER || 'firefox';

  const browser = await puppeteer.launch({
    browser: browserName,
    headless: true,
    protocol: 'webDriverBiDi',
  });

  const wsEndpoint = browser.wsEndpoint();
  console.log('[repro] wsEndpoint:', wsEndpoint);

  // Detach without closing the browser process.
  browser.disconnect();

  const browser2 = await puppeteer.connect({
    browserWSEndpoint: wsEndpoint,
    protocol: 'webDriverBiDi',
  });

  const page = await browser2.newPage();
  await page.goto('data:text/html,<title>ok</title>');
  const title = await page.title();
  console.log('[repro] title:', title);

  await browser2.close();
}

main().catch(err => {
  console.error(err);
  process.exitCode = 1;
});

