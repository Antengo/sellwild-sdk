Pod::Spec.new do |s|
  s.name             = 'SellwildSDK'
  s.version          = '1.1.0'
  s.summary          = 'Sellwild mobile advertising SDK for iOS'
  s.description      = <<-DESC
    SellwildSDK provides native iOS components for embedding
    Sellwild marketplace listings and ad units in mobile apps.
    Supports banner ads (320x50, 300x250, 728x90), inline placements,
    and the full widget with Prebid header bidding.
  DESC

  s.homepage         = 'https://github.com/Antengo/sellwild-sdk'
  s.license          = { :type => 'MIT', :file => 'ios/LICENSE' }
  s.author           = { 'Sellwild' => 'sdk@sellwild.com' }
  s.source           = { :git => 'https://github.com/Antengo/sellwild-sdk.git', :tag => s.version.to_s }

  s.ios.deployment_target = '13.0'
  s.swift_version = '5.5'

  s.source_files = 'ios/Sources/SellwildSDK/**/*.swift'
  s.frameworks = 'UIKit', 'WebKit', 'Foundation'
end
