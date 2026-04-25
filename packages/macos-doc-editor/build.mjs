import * as esbuild from 'esbuild';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { mkdirSync, readFileSync, writeFileSync, cpSync, rmSync, existsSync } from 'node:fs';

const root = dirname(fileURLToPath(import.meta.url));
const outDir = join(root, 'dist');
const resourcesDir = join(root, '../../apps/macos/TodusMac/Resources/DocEditor');

if (existsSync(outDir)) rmSync(outDir, { recursive: true });
mkdirSync(outDir, { recursive: true });

await esbuild.build({
  entryPoints: [join(root, 'src/index.ts')],
  bundle: true,
  format: 'iife',
  outfile: join(outDir, 'index.js'),
  platform: 'browser',
  target: 'es2022',
  minify: true,
  legalComments: 'none',
  loader: { '.css': 'text' },
});

// Inline CSS: esbuild "text" loader inlines as string; we need separate file for link tag
// Re-run without bundling CSS into js — use external css file
const cssPath = join(root, 'src/editor.css');
const cssOut = join(outDir, 'editor.css');
writeFileSync(cssOut, readFileSync(cssPath));

const html = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Doc</title>
  <link rel="stylesheet" href="editor.css" />
  <style>html,body{margin:0;height:100%;background:transparent} body.dark{background:#141414}</style>
</head>
<body>
  <div id="editor"></div>
  <script src="index.js"></script>
</body>
</html>
`;

writeFileSync(join(outDir, 'index.html'), html);

if (existsSync(resourcesDir)) rmSync(resourcesDir, { recursive: true });
mkdirSync(join(resourcesDir, '..'), { recursive: true });
cpSync(outDir, resourcesDir, { recursive: true });

console.log('Built macos-doc-editor →', outDir, 'and copied to', resourcesDir);
