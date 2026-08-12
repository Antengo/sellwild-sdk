Pod::Spec.new do |s|
  s.name             = 'SellwildSDK'
  s.version          = '1.7.2'
  s.summary          = 'Sellwild mobile advertising SDK for iOS'
  s.description      = <<-DESC
    SellwildSDK provides native iOS components for embedding
    Sellwild marketplace listings and ad units in mobile apps.
    Banner ads run a native Prebid Mobile auction and render
    in a GAMBannerView — no WebView in the ad path.
  DESC

  s.homepage         = 'https://github.com/Antengo/sellwild-sdk'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Sellwild' => 'sdk@sellwild.com' }
  s.source           = { :git => 'https://github.com/Antengo/sellwild-sdk.git', :tag => s.version.to_s }

  s.ios.deployment_target = '13.0'
  s.swift_version = '5.5'

  # Required because GMA + UMP ship as static binaries; consumers should add
  # `use_frameworks! :linkage => :static` to their Podfile (or rely on this
  # static_framework flag to satisfy the transitive constraint).
  s.static_framework = true

  s.source_files = 'ios/Sources/SellwildSDK/**/*.swift'
  s.frameworks = 'UIKit', 'WebKit', 'Foundation'

  # Native ad stack — required, not optional.
  # SellwildAdView runs a Prebid Mobile auction and renders in a GAMBannerView.
  # The widget surface (SellwildWidgetView / SellwildWidget) still uses WKWebView
  # for marketplace listings; that is intentional.
  #
  # SellwildPrebid is our namespace-shaded fork of Prebid Mobile SDK. This
  # allows Sellwild ads to coexist with a partner's own Prebid implementation
  # without singleton conflicts (SellwildPrebid.shared vs Prebid.shared).
  s.dependency 'SellwildPrebid', '1.4.3'
  s.dependency 'SellwildPrebidGAMEventHandlers', '1.4.3'
  s.dependency 'Google-Mobile-Ads-SDK', '>= 12.0', '< 14.0'
end
