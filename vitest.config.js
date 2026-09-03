import { defineConfig } from 'vitest/config'
import { fileURLToPath } from 'node:url'

export default defineConfig({
  resolve: {
    alias: {
      // App code uses importmap-style bare specifiers ("llamapress/foo"). Vitest has
      // no importmap, so map the pin prefix onto the source directory.
      'llamapress': fileURLToPath(new URL('./app/javascript/llamapress', import.meta.url))
    }
  },
  test: {
    environment: 'happy-dom',
    globals: true,
    setupFiles: ['./spec/javascript/setup.js'],
    testTimeout: 10000,
    hookTimeout: 30000,
    include: ['spec/javascript/**/*.test.js'],
    coverage: {
      provider: 'v8',
      reporter: ['text', 'json', 'html'],
      include: ['app/javascript/**/*.js']
    }
  }
})
