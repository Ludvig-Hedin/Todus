module.exports = {
  testEnvironment: 'node',
  setupFilesAfterEnv: ['<rootDir>/jest.setup.js'],
  transform: {
    '^.+\\.(ts|tsx|js)$': ['babel-jest', { presets: ['module:@react-native/babel-preset'] }],
  },
  transformIgnorePatterns: ['node_modules/(?!(\\@react-native-async-storage)/)'],
  moduleNameMapper: {
    '^@zero/shared$': '<rootDir>/../../packages/shared/src',
    '^@zero/design-tokens$': '<rootDir>/../../packages/design-tokens/src',
    '^@zero/ui-native$': '<rootDir>/../../packages/ui-native/src',
    '^@zero/api-client$': '<rootDir>/../../packages/api-client/src',
  },
};
