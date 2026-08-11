import { defineConfig } from "vitest/config";
import react from "@vitejs/plugin-react";

const apiOrigin = readApiOrigin();

export default defineConfig({
  base: "/uok-ui/",
  plugins: [react()],
  build: {
    outDir: "../priv/static/uok-ui",
    emptyOutDir: true,
    sourcemap: false,
  },
  server: {
    port: 5173,
    strictPort: true,
    proxy: {
      "/api": apiOrigin,
    },
  },
  test: {
    environment: "jsdom",
    setupFiles: ["./src/test/setup.ts"],
    clearMocks: true,
    restoreMocks: true,
  },
});

function readApiOrigin(): string {
  const configuredOrigin = process.env.UOK_API_ORIGIN ?? "http://127.0.0.1:4000";
  const parsedOrigin = new URL(configuredOrigin);

  if (
    parsedOrigin.protocol !== "http:" ||
    !["127.0.0.1", "localhost"].includes(parsedOrigin.hostname)
  ) {
    throw new Error("UOK_API_ORIGIN must be a loopback HTTP origin");
  }

  return parsedOrigin.origin;
}
