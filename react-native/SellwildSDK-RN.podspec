require 'json'

package = JSON.parse(File.read(File.join(__dir__, 'package.json')))

Pod::Spec.new do |s|
  s.name             = 'SellwildSDK-RN'
  s.version          = package['version']
  s.summary          = 'React Native bridge for the Sellwild iOS SDK'
  s.description      = <<-DESC
    Bridges the @sellwild/react-native-sdk components to native iOS:
      - <SellwildBanner> → SellwildAdView (Prebid Mobile + AdManagerBannerView)
      - <SellwildFeed>   → SellwildFeedView (all-in-one COL1-scheduled
                           feed of native listing cards + native ads)
    There is no WebView in either path.
  DESC

  s.homepage         = 'https://github.com/Antengo/sellwild-sdk'
  s.license          = { :type => 'MIT' }
  s.author           = { 'Sellwild' => 'sdk@sellwild.com' }
  s.source           = { :git => 'https://github.com/Antengo/sellwild-sdk.git', :tag => s.version.to_s }

  s.platforms        = { :ios => '13.0' }
  s.swift_version    = '5.5'

  s.source_files     = 'ios/*.{swift,m,h}'
  s.requires_arc     = true

  # The host app must already pull in SellwildSDK (the iOS SDK pod). We
  # depend on it explicitly so `pod install` resolves both with one
  # declaration in the host Podfile.
  s.dependency 'SellwildSDK', '>= 1.3.5'
  s.dependency 'React-Core'
end
