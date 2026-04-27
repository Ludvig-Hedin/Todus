const history = require('connect-history-api-fallback');
const react = require('@vitejs/plugin-react');
const { defineConfig } = require('vite');

module.exports = defineConfig({
  plugins: [
    react(),
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
