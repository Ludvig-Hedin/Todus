module.exports = function (api) {
  api.cache(true);
  return {
    presets: [
      ['babel-preset-expo', {
        'react-compiler': {
          target: '19'
        }
      }]
    ],
    plugins: [
      'react-native-reanimated/plugin'
    ],
  };
};
