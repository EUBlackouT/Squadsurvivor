import { test, expect } from '@playwright/test';

test('loads and shows HUD', async ({ page }) => {
  await page.goto('/');
  await page.keyboard.press('Enter');
  await page.waitForSelector('#hud');
  await expect(page.locator('#hud-room')).toBeVisible();
  await expect(page.locator('#hud-enemies')).toBeVisible();
});


