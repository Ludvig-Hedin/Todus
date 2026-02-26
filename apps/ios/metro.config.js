const path = require('path');
const { getDefaultConfig } = require('expo/metro-config');

const projectRoot = __dirname;
const workspaceRoot = path.resolve(projectRoot, '../..');

const config = getDefaultConfig(projectRoot);

// Monorepo: watch workspace root for shared packages
config.watchFolders = [workspaceRoot];

// Monorepo: resolve modules from both project and workspace node_modules
config.resolver.nodeModulesPaths = [
  path.resolve(projectRoot, 'node_modules'),
  path.resolve(workspaceRoot, 'node_modules'),
];

// Enable package exports resolution (needed for ESM modules like getDevServer)
config.resolver.unstable_enablePackageExports = true;

module.exports = config;
