// End-to-end smoke test of the running stack (web through Nginx -> API -> PostgreSQL).
// Needs: npm i -D playwright && npx playwright install chromium
// Run:   BASE_URL=http://localhost:8000 node e2e/smoke.cjs
const { chromium } = require('playwright');
const BASE = process.env.BASE_URL ?? 'http://localhost:8000';
const run = Date.now().toString(36);
const log = (...a) => console.log(...a);
(async () => {
  const browser = await chromium.launch();
  const problems = [];
  const mk = async (viewport) => {
    const ctx = await browser.newContext({ viewport });
    await ctx.grantPermissions(['clipboard-read', 'clipboard-write'], { origin: BASE });
    const page = await ctx.newPage();
    page.on('pageerror', (e) => problems.push('pageerror: ' + e.message));
    page.on('console', (m) => { if (m.type() === 'error' && !/img\.youtube|Failed to load resource/.test(m.text())) problems.push('console: ' + m.text()); });
    return { ctx, page };
  };
  // Wait for a toast containing `text` (IndexedDB writes are async), then return its text.
  const toast = async (p, text) => { const t = p.locator('.toast', { hasText: text }); await t.waitFor({ timeout: 4000 }); return (await t.locator('span').textContent()); };
  const hero = async (p, text) => { await p.locator('.hero .sub', { hasText: text }).waitFor({ timeout: 4000 }); return p.locator('.hero .sub').textContent(); };

  // ---------- 1. phone-sized, first visit: seeded, works with no account
  const { ctx: a, page } = await mk({ width: 390, height: 844 });
  await page.goto(BASE);
  await page.getByRole('heading', { name: 'Your collections' }).waitFor();
  log('1. home loads; collections:', await page.locator('.folder-card h3').allTextContents());
  log('   waiting badge:', await page.locator('.bottom-nav .badge').textContent());
  await page.screenshot({ path: 'e2e/web-1-home-mobile.png' });

  // ---------- 2. paste a link -> sort it for me
  await page.evaluate(() => navigator.clipboard.writeText('Resep sambal matah khas Bali https://www.instagram.com/reel/test-sambal/'));
  await page.getByRole('button', { name: 'Paste link' }).click();
  const url = await page.getByLabel('Link').inputValue();
  log('2. paste filled link:', url, '| title:', await page.getByLabel('Title').inputValue());
  await page.getByRole('button', { name: 'Save link' }).click();
  log('   toast:', await toast(page, 'Saved'), '| badge now:', await page.locator('.bottom-nav .badge').textContent());

  // ---------- 3. folder: tick done, undo, back
  await page.locator('.folder-card', { hasText: 'Jakarta Trip' }).click();
  await page.getByRole('heading', { name: 'Jakarta Trip' }).waitFor();
  log('3. hero:', await page.locator('.hero .sub').textContent());
  await page.getByRole('button', { name: 'Mark as done' }).first().click();
  log('   toast:', await toast(page, 'Marked as done'), '| hero:', await hero(page, '2 done'));
  await page.screenshot({ path: 'e2e/web-2-folder-mobile.png' });
  await page.locator('.toast').getByRole('button', { name: 'Undo' }).click();
  log('   after undo:', await hero(page, '1 done'));
  await page.getByRole('button', { name: 'Back to list' }).click();
  log('   back ->', new URL(page.url()).pathname);

  // ---------- 4. offline: reload with no network
  await page.evaluate(() => navigator.serviceWorker.ready.then(() => true));
  await page.reload(); await page.waitForTimeout(500); // let the SW take control
  await a.setOffline(true);
  await page.reload();
  await page.getByRole('heading', { name: 'Your collections' }).waitFor({ timeout: 5000 });
  log('4. reloaded OFFLINE, app still loads:', await page.locator('.folder-card h3').count(), 'collections');
  await page.locator('.folder-card', { hasText: 'Bali Trip' }).click();
  await page.getByRole('button', { name: 'Add link' }).click();
  await page.getByLabel('Link').fill('https://www.youtube.com/watch?v=abcdefghijk');
  await page.getByLabel('Title').fill('Saved while offline');
  await page.getByRole('button', { name: 'Save link' }).click();
  log('   saved offline:', await toast(page, 'Saved to'));
  log('   New links after 3 reloads (should still be 4, none auto-filed):', await page.locator('.bottom-nav .badge').textContent());
  await a.setOffline(false);

  // ---------- 5. sign in -> local saves upload to PostgreSQL
  await page.goto(BASE + '/friends');
  await page.getByRole('button', { name: 'Continue with Google' }).click();
  await page.getByLabel('Email').fill(`alice.${run}@example.com`);
  await page.getByLabel('Your name').fill('Alice');
  await page.getByRole('button', { name: 'Continue', exact: true }).click();
  await page.getByRole('main').getByText('Synced to your Shareby account').waitFor({ timeout: 8000 });
  log('5. signed in + synced');

  // ---------- 6. shared board + invite
  await page.getByRole('button', { name: 'New board' }).click();
  await page.getByLabel('Name').fill('Housewarming Ideas');
  await page.getByRole('button', { name: 'Create board' }).click();
  await page.getByLabel('Email').fill(`bob.${run}@example.com`);
  await page.getByRole('button', { name: 'Send invite' }).click();
  log('6. invite:', await toast(page, 'Invite saved'));
  await page.locator('a.card', { hasText: 'Housewarming Ideas' }).click();
  await page.getByRole('button', { name: 'Add pin' }).click();
  await page.getByLabel('Link').fill('https://www.tiktok.com/@x/video/777');
  await page.getByLabel('Title').fill('Ide hampers murah buat tamu');
  await page.getByRole('button', { name: 'Save link' }).click();
  await page.waitForTimeout(2600); // debounced sync

  // ---------- 7. Bob (desktop) signs in, sees the board, ticks the pin
  const { ctx: b, page: bob } = await mk({ width: 1366, height: 860 });
  await bob.goto(BASE + '/friends');
  await bob.getByRole('button', { name: 'Continue with Google' }).click();
  await bob.getByLabel('Email').fill(`bob.${run}@example.com`);
  await bob.getByLabel('Your name').fill('Bob');
  await bob.getByRole('button', { name: 'Continue', exact: true }).click();
  await bob.locator('a.card', { hasText: 'Housewarming Ideas' }).waitFor({ timeout: 8000 });
  await bob.locator('a.card', { hasText: 'Housewarming Ideas' }).click();
  log('7. bob sees pin:', await bob.locator('.link-row .title').allTextContents(), '|', await bob.locator('.link-row .meta span').last().textContent());
  await bob.getByRole('button', { name: 'Mark as done' }).click();
  await bob.waitForTimeout(2600);
  await bob.screenshot({ path: 'e2e/web-3-board-desktop.png' });

  // ---------- 8. Alice sees "Done by Bob"; back from a shared board -> Friends
  await page.goto(BASE + '/profile');
  await page.getByRole('button', { name: 'Sync now' }).click();
  await page.getByRole('main').getByText('Synced to your Shareby account').waitFor();
  await page.goto(BASE + '/friends');
  await page.locator('a.card', { hasText: 'Housewarming Ideas' }).click();
  log('8. alice sees:', await page.locator('.link-row .meta span').last().textContent());
  await page.getByRole('button', { name: 'Back to list' }).click();
  log('   back from shared board ->', new URL(page.url()).pathname);

  // ---------- 9. Web Share Target
  await page.goto(BASE + '/share?title=Kopi%20enak&text=Kopi%20aren%20Jaksel&url=https%3A%2F%2Fwww.instagram.com%2Freel%2Fkopi1');
  await page.getByRole('heading', { name: 'Save to Shareby' }).waitFor();
  log('9. share target sheet, link:', await page.getByLabel('Link').inputValue(), '| title:', await page.getByLabel('Title').inputValue());
  await page.keyboard.press('Escape');

  // ---------- 10. desktop: Ctrl+V anywhere opens the save sheet
  await bob.goto(BASE + '/');
  await bob.getByRole('heading', { name: 'Your collections' }).waitFor();
  await bob.evaluate(() => {
    const e = new ClipboardEvent('paste', { clipboardData: new DataTransfer(), bubbles: true });
    e.clipboardData.setData('text/plain', 'https://youtu.be/dQw4w9WgXcQ');
    document.body.dispatchEvent(e);
  });
  log('10. global paste opened:', await bob.getByRole('heading', { name: 'Save a link' }).isVisible());
  await bob.keyboard.press('Escape');
  await bob.screenshot({ path: 'e2e/web-4-home-desktop.png' });

  log('\nproblems:', problems.length ? problems : 'none');
  await browser.close();
})().catch((e) => { console.error('FAILED:', e.message); process.exit(1); });
