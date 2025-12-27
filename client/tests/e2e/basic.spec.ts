import { test, expect } from '@playwright/test';

// Requires server running (npm run dev at root)

test('connects to server and receives snapshot', async ({ page }) => {
  await page.goto('http://localhost:5173/');
  await page.keyboard.press('Enter');
  await expect(page.locator('canvas')).toBeVisible();
  await page.waitForTimeout(1000);
  const errors:string[]=[]; page.on('console', m=>{ if(m.type()==='error') errors.push(m.text()); });
  await page.waitForTimeout(2000);
  expect(errors).toHaveLength(0);
});

