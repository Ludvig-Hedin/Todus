import history from 'connect-history-api-fallback';
import tailwindcss from '@tailwindcss/vite';
import react from '@vitejs/plugin-react';
import { defineConfig } from 'vite';

export default defineConfig({
  plugins: [
    react(),
    tailwindcss(),
    {
      name: 'spa-fallback',
      configureServer(server) {
        server.middlewares.use(
          history({
            htmlAcceptHeaders: ['text/html', 'application/xhtml+xml'],
          }),
        );
      },
    },
  ],
  server: {
    port: 3000,
  },
});
