import { defineConfig } from 'vite';

export default defineConfig({
  root: 'src',
  publicDir: '../assets',
  server: { port: 5173 },
  build: { outDir: '../dist' }
});

