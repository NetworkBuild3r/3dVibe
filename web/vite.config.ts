import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

const apiTarget =
  (globalThis as { process?: { env?: Record<string, string | undefined> } }).process?.env?.API_PROXY_TARGET ||
  "http://127.0.0.1:3000";

export default defineConfig({
  plugins: [react()],
  server: {
    host: "0.0.0.0",
    port: 5173,
    proxy: {
      "/api": {
        target: apiTarget,
        changeOrigin: true
      },
      "/up": {
        target: apiTarget,
        changeOrigin: true
      }
    }
  }
});
