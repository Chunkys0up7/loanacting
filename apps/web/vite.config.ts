import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    proxy: {
      "/loans": "http://localhost:4000",
    },
  },
  test: {
    environment: "jsdom",
    globals: true,
    setupFiles: ["./test/setup.ts"],
    // test/e2e/** are Playwright specs (npm run e2e), not Vitest's — without
    // this exclude, Vitest's default glob also picks up *.spec.ts there and
    // tries to run them as Vitest tests, which fails (Playwright's test()
    // global isn't valid outside a Playwright run).
    exclude: ["node_modules/**", "test/e2e/**"],
  },
});
