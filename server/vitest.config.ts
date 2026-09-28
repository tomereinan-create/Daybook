import { defineConfig } from 'vitest/config';

// The pure helpers run under plain node; anything touching D1 or the APNs
// fetch belongs in an integration test against `wrangler dev`, not here.
export default defineConfig({
  test: {
    include: ['test/**/*.test.ts'],
  },
});
