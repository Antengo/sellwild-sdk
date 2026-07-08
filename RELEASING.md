# Releasing SellwildSDK

**A release is NOT done when the tag is pushed. It is done when a partner can
install it from a clean machine.** Both 1.4.1 and 1.4.2 misfired with WeatherBug
because we skipped steps below. Do not skip them.

## Definition of Done

A release is complete only when ALL of these pass:

- [ ] iOS SPM: fresh `swift package resolve` pulls the new version
- [ ] iOS CocoaPods: `pod install --repo-update` in a **scratch project** (not this repo) installs the new version from the **public trunk**
- [ ] Android: new AAR resolves from `https://maven.sellwild.com` (not Maven Local)
- [ ] Coexistence smoke test: scratch Podfile with `pod 'PrebidMobile', '~> 3.0'` + `pod 'SellwildSDK'` builds with 0 errors
- [ ] ObjC dual-import test: an **Objective-C** file with `@import PrebidMobile; @import SellwildPrebidSDK;` that *uses* types from both compiles clean (Swift-only tests miss "different definitions in different modules" errors — this is what broke 1.4.2 for WeatherBug)
- [ ] Only after all of the above: notify partners

## Past Misfires (why each rule exists)

| Version | What went wrong | Rule it created |
|---------|----------------|-----------------|
| 1.4.1 | Updated Package.swift but not SellwildSDK.podspec — CocoaPods users (WeatherBug) couldn't install | Always update BOTH distribution files |
| 1.4.2 | Tagged on GitHub but never ran `pod trunk push` — version didn't exist on the public trunk. Then the jsDelivr CDN purge webhook failed, hiding the fix for 30+ more minutes | Trunk-publish is a mandatory step; verify via scratch-project install, not `pod spec lint` |
| 1.4.1 (tag) | Re-pointed an existing tag, poisoning partner caches | Never move a tag — cut a new version |
| 1.4.2 | Public @objc types (AdUnit, ResultCode, etc.) kept upstream ObjC names — WeatherBug's ObjC code importing both modules got "different definitions in different modules". Our coexistence test was Swift-only and never caught it | ObjC dual-import compile test is part of the Definition of Done; fixed in 1.4.3 via `@objc(SWPB*)` names |

## iOS Release Steps

### 1. Fork repo first (Antengo/sellwild-prebid-mobile-ios) — only if it changed

```bash
# Bump version in ALL podspecs: SellwildPrebid.podspec,
# SellwildPrebidGAMEventHandlers.podspec, SellwildPrebidAdMobAdapters.podspec,
# SellwildPrebidMAXAdapters.podspec
git commit -am "chore: bump to X.Y.Z" && git tag X.Y.Z && git push origin master --tags

# Publish to trunk IN DEPENDENCY ORDER (--synchronous waits for indexing):
pod trunk push SellwildPrebid.podspec --allow-warnings
pod trunk push SellwildPrebidGAMEventHandlers.podspec --allow-warnings --synchronous
```

### 2. This repo (sellwild-sdk)

```bash
# Bump version in BOTH files:
#   - SellwildSDK.podspec  (s.version AND the SellwildPrebid dependency pins)
#   - Package.swift        (fork dependency pin)
git commit -am "chore: release X.Y.Z" && git tag X.Y.Z && git push origin main --tags

pod trunk push SellwildSDK.podspec --allow-warnings --synchronous
```

### 3. Verify (mandatory, from a scratch project)

```bash
mkdir /tmp/release-check && cd /tmp/release-check
# Podfile: platform :ios, '13.0'; target with use_frameworks! :linkage => :static
# and: pod 'PrebidMobile', '~> 3.0'   +   pod 'SellwildSDK', '~> X.Y.Z'
pod install --repo-update        # must resolve X.Y.Z from trunk
xcodebuild build ...             # must succeed with 0 errors
```

If `pod install` can't find the version but `pod trunk info SellwildSDK` shows it:
the CDN is stale. Purge the shard manually:

```bash
# shard = first 3 hex chars of md5 of the pod name
M=$(printf '%s' "SellwildSDK" | md5)
curl "https://purge.jsdelivr.net/cocoa/all_pods_versions_${M:0:1}_${M:1:1}_${M:2:1}.txt"
# repeat for SellwildPrebid and SellwildPrebidGAMEventHandlers
```

## Android Release Steps

```bash
# 1. Bump version in build.gradle.kts (publishing block)
# 2. Publish with Android Studio's Java 17 (system Java 25 breaks Gradle):
JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" \
  ./gradlew publishReleasePublicationToMavenLocal

# 3. Sync to the public Maven repo:
aws s3 sync ~/.m2/repository/com/sellwild/ s3://maven.sellwild.com/releases/com/sellwild/ \
  --cache-control "max-age=86400,public"

# 4. Invalidate CloudFront (distribution E16P8KJDWTNW2W):
aws cloudfront create-invalidation --distribution-id E16P8KJDWTNW2W --paths "/releases/com/sellwild/*"

# 5. Verify the AAR is publicly reachable:
curl -sI https://maven.sellwild.com/releases/com/sellwild/sdk/X.Y.Z/sdk-X.Y.Z.aar  # expect 200
```

If the fork (Antengo/prebid-mobile-android) changed, publish its modules the same
way first (PrebidMobile-core, PrebidMobile-gamEventHandlers, omsdk-android).

## Hard Rules

1. **Never move an existing tag.** Cut a new patch version instead.
2. **Never announce a release based on `pod spec lint` or a local build.** Only a clean-environment install counts.
3. **Version numbers stay in lockstep** across podspec, Package.swift, and build.gradle.kts.
4. **Fork before SDK.** The fork's pods must be on trunk before SellwildSDK's podspec (which pins them) can validate.
