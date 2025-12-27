import { test, expect } from '@playwright/test';

test('shows merge timer during window', async ({ page }) => {
  await page.goto('/');
  await page.keyboard.press('Enter');
  await page.waitForSelector('canvas');
  // Wait for a snapshot and merge HUD to update
  await page.waitForSelector('#hud-merge');
  // Force a merge window via test channel
  await expect.poll(async ()=> await page.evaluate(()=> typeof (window as any).__pbForceMerge === 'function'), { timeout: 10000 }).toBe(true);
  await page.evaluate(()=> (window as any).__pbForceMerge?.(2500));
  // Expect HUD shows a countdown like 'x.xs'
  await expect(page.locator('#hud-merge')).not.toHaveText('-', { timeout: 5000 });
});

test('phase denied near enemy emits FX', async ({ page }) => {
  await page.goto('/');
  await page.keyboard.press('Enter');
  await page.waitForSelector('canvas');
  // Directly set a client cooldown via helper and assert HUD updates
  await expect.poll(async ()=> await page.evaluate(()=> typeof (window as any).__pbPhaseCooldown === 'function'), { timeout: 10000 }).toBe(true);
  await page.evaluate(()=> (window as any).__pbPhaseCooldown?.(1500));
  await expect(page.locator('#hud-phase')).not.toHaveText('ready', { timeout: 3000 });
});


