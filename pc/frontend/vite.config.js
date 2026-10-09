import {defineConfig} from 'vite'
import {fileURLToPath} from 'node:url'

// Include the main viewer, RX diagnostics and standalone settings window in production builds.
export default defineConfig({
  build: {
    rollupOptions: {
      input: {
        main: fileURLToPath(new URL('./index.html', import.meta.url)),
        integration: fileURLToPath(new URL('./integration.html', import.meta.url)),
        settings: fileURLToPath(new URL('./settings.html', import.meta.url))
      }
    }
  }
})
