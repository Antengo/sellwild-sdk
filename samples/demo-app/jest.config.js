const path = require('path');

const appModules = path.join(__dirname, 'node_modules');

module.exports = {
  preset: 'react-native',
  // The SDK folders have no Babel runtime of their own.
  modulePaths: [appModules],
  // As in metro.config.js: the SDK packages are the repo's folders, and every
  // file gets the app's one copy of React and React Native.
  moduleNameMapper: {
    '^@sellwild/react-native-sdk$': path.resolve(
      __dirname,
      '../../react-native/src',
    ),
    '^@sellwild/sdk-core$': path.resolve(__dirname, '../../core/src'),
    '^react$': path.join(appModules, 'react'),
    '^react/(.*)$': path.join(appModules, 'react/$1'),
    '^react-native$': path.join(appModules, 'react-native'),
    '^react-native-webview$': path.join(appModules, 'react-native-webview'),
  },
};
