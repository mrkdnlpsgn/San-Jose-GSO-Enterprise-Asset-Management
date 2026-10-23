import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  server: {
    port: 3000,
    proxy: {
      '/api': {
        target: 'http://localhost:8080',
        changeOrigin: true,
        cookieDomainRewrite: 'localhost',
      },
      '/uploads': {
        target: 'http://localhost:8080',
        changeOrigin: true,
      },
    },
    // Security headers served by the Vite dev server.
    // In production these should be set by your reverse proxy / CDN (nginx, Cloudflare, etc.).
    headers: {
      // Prevent MIME-type sniffing
      'X-Content-Type-Options': 'nosniff',
      // Block page from being framed - clickjacking protection
      'X-Frame-Options': 'DENY',
      // Limit referrer info sent to other origins
      'Referrer-Policy': 'strict-origin-when-cross-origin',
      // Deny access to sensitive browser APIs not used by this app
      'Permissions-Policy': 'camera=(self), microphone=(), geolocation=(), payment=(), usb=(), display-capture=()',
      // Suppress DNS prefetching to avoid leaking visited URLs
      'X-DNS-Prefetch-Control': 'off',
      // Isolate browsing context - limits cross-origin window access
      'Cross-Origin-Opener-Policy': 'same-origin',
      // Restrict cross-origin resource sharing at document level
      'Cross-Origin-Resource-Policy': 'same-origin',
    },
  },
})
