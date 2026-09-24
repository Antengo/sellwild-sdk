// Globals that core/src uses and React Native's own types do not declare.
// tsconfig.json lists this file so src (and core/src, through the paths
// entry) type-check without the DOM lib, which would also allow document,
// window and localStorage, none of which exist in React Native.
//
// React Native has no Web Crypto unless the app installs a polyfill.
// core/src/api.ts calls crypto.randomUUID() inside a try/catch and falls
// back when it is missing, so only that call is declared.
declare var crypto: { randomUUID(): string }
