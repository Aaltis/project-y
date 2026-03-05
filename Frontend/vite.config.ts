import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// When running inside Docker the proxy must target the gateway service by name.
// API_PROXY_TARGET is set in docker-compose; falls back to localhost for `npm run dev` outside Docker.
const apiTarget = process.env.API_PROXY_TARGET ?? 'http://localhost:8080'

export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    host: true,           // bind to 0.0.0.0 inside Docker
    hmr: { host: 'localhost' }, // browser connects to localhost for HMR WebSocket
    proxy: {
      '/api': apiTarget,
      '/auth': apiTarget,
      '/actuator': apiTarget,
    },
  },
})
