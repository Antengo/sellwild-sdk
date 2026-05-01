const path = require('path');
const {getDefaultConfig, mergeConfig} = require('@react-native/metro-config');

const sdkRoot = path.resolve(__dirname, '..', '..');
const sdkCore = path.join(sdkRoot, 'core');
const sdkRN = path.join(sdkRoot, 'react-native');
const appModules = path.resolve(__dirname, 'node_modules');

const config = {
  watchFolders: [sdkCore, sdkRN],
  resolver: {
    blockList: [
      /\/sellwild-sdk\/core\/node_modules\/.*/,
      /\/sellwild-sdk\/react-native\/node_modules\/.*/,
    ],
    extraNodeModules: new Proxy(
      {
        '@sellwild/react-native-sdk': sdkRN,
        '@sellwild/sdk-core': sdkCore,
      },
      {
        get: (target, name) =>
          name in target
            ? target[name]
            : path.join(appModules, String(name)),
      },
    ),
  },
};

module.exports = mergeConfig(getDefaultConfig(__dirname), config);
