// React Native autolinking config for @sellwild/react-native-sdk.
//
// On iOS we have two podspecs in the worktree (SellwildSDK.podspec for the
// pure-iOS SDK, and ios/SellwildSDK-RN.podspec for the RN bridge). Point
// autolink explicitly at the bridge so `pod install` doesn't try to link
// the standalone iOS SDK pod from inside this package.
//
// On Android the bridge module lives at android/ and is picked up by the
// standard sourceDir convention.
module.exports = {
  dependency: {
    platforms: {
      ios: {
        podspecPath: __dirname + '/ios/SellwildSDK-RN.podspec',
      },
      android: {
        sourceDir: __dirname + '/android',
        packageImportPath: 'import com.sellwild.rnsdk.SellwildSdkPackage;',
        packageInstance: 'new SellwildSdkPackage()',
      },
    },
  },
}
