# PATCHBOUND – Multiplayer Roguelite (Vertical Slice)

Prereqs: Node 20.11.x, npm.

Install:
```
npm ci
npm -w server ci
npm -w client ci
```

Run (dev):
```
npm run dev
# server: 3001, client: 5173
```

Build:
```
npm -w server run build
npm -w client run build
```

Test:
```
npm -w server run test
npm -w client run test
# e2e: start dev servers, then
npx playwright test
```

Controls: Arrows move, LMB fire, RMB alt, Q/E swap, F phase, R fusion,
Enter extract/next, C cleanse.

Notes: Placeholder art; see ASSETS_TODO.md. Dev helpers on window for tests.
