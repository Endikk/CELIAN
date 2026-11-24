/// <reference types="vitest/config" />
// Build and test settings of the front (research RS-05 of spec 001 in CELIAN).
// Vite 8 compiles TSX with Oxc, which reads "jsx": "react-jsx" from
// tsconfig.json: no React plugin, whose Fast Refresh only serves a dev server.
import { defineConfig } from "vite";

export default defineConfig({
  test: {
    environment: "jsdom",
    include: ["tests/**/*.test.{ts,tsx}"],
  },
});
