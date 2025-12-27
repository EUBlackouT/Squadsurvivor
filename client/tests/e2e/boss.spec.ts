import { test, expect } from '@playwright/test';

test('boss room loads and runs without errors', async ({ page }) => {
  await page.goto('/?boss=1');
  await page.keyboard.press('Enter');
  await expect(page.locator('canvas')).toBeVisible();
  const errors:string[]=[];
  page.on('console', m=>{ if(m.type()==='error') errors.push(m.text()); });
  await page.waitForTimeout(1500);
  expect(errors).toHaveLength(0);
});


