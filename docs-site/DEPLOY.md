# Deployment Guide

## Docs Site

The docs site is a VitePress static site deployed to S3 + CloudFront at https://sdk.sellwild.com.

## Prerequisites

- AWS CLI configured with account `457870823482`
- Node.js 18+

## Build

```bash
cd docs-site
npm install
npm run build
```

Output lands in `docs-site/.vitepress/dist/`.

## Deploy to S3

```bash
aws s3 sync .vitepress/dist/ s3://sdk.sellwild.com/ \
  --cache-control "max-age=3600,public" \
  --delete
```

## Invalidate CloudFront Cache

```bash
aws cloudfront create-invalidation \
  --distribution-id E2I8MYVEM6ZX5R \
  --paths "/*"
```

Invalidation takes 1-2 minutes to propagate globally.

## One-liner

```bash
npm run build && \
aws s3 sync .vitepress/dist/ s3://sdk.sellwild.com/ --cache-control "max-age=3600,public" --delete && \
aws cloudfront create-invalidation --distribution-id E2I8MYVEM6ZX5R --paths "/*"
```

## Infrastructure

| Resource | Value |
|---|---|
| S3 Bucket | `sdk.sellwild.com` |
| CloudFront Distribution | `E2I8MYVEM6ZX5R` |
| CloudFront Domain | `d3dsg4mdklzb65.cloudfront.net` |
| ACM Certificate | `arn:aws:acm:us-east-1:457870823482:certificate/98b905b8-c410-4280-b3b9-c32aa5b0dc8a` |
| Route53 Zone | `Z3G3982AWLHGHP` (sellwild.com) |
| DNS | `sdk.sellwild.com` CNAME → CloudFront |

## Local Development

```bash
cd docs-site
npm install
npm run dev
```

Runs at `http://localhost:5173` with hot reload.

---

## Android SDK (Maven)

The Android SDK is published as an AAR to a self-hosted Maven repository at https://maven.sellwild.com/releases.

### Prerequisites

- Android Studio with SDK platform 35 and build tools
- AWS CLI configured

### Build and Publish

```bash
cd android
./gradlew publishReleasePublicationToMavenLocal
```

This outputs the AAR, POM and Gradle module to `~/.m2/repository/com/sellwild/sdk/<version>/`. The full release procedure (version bump, upload, metadata, verification) is in [RELEASING.md](../RELEASING.md).

### Deploy to S3

```bash
aws s3 sync ~/.m2/repository/com/sellwild/ s3://maven.sellwild.com/releases/com/sellwild/ \
  --cache-control "max-age=86400,public"
```

### Invalidate CloudFront Cache

```bash
aws cloudfront create-invalidation \
  --distribution-id E16P8KJDWTNW2W \
  --paths "/*"
```

### One-liner

```bash
cd android && \
./gradlew publishReleasePublicationToMavenLocal && \
aws s3 sync ~/.m2/repository/com/sellwild/ s3://maven.sellwild.com/releases/com/sellwild/ --cache-control "max-age=86400,public" && \
aws cloudfront create-invalidation --distribution-id E16P8KJDWTNW2W --paths "/*"
```

### Infrastructure

| Resource | Value |
|---|---|
| S3 Bucket | `maven.sellwild.com` |
| CloudFront Distribution | `E16P8KJDWTNW2W` |
| CloudFront Domain | `d1ey29h6mr9765.cloudfront.net` |
| ACM Certificate | `arn:aws:acm:us-east-1:457870823482:certificate/689f47f8-081d-423b-a427-f6c454e4d4c6` |
| Route53 Zone | `Z3G3982AWLHGHP` (sellwild.com) |
| DNS | `maven.sellwild.com` CNAME → CloudFront |
| Maven Coordinates | `com.sellwild:sdk:<version>` (latest: 1.8.1) |
| Also hosted | `com.sellwild:PrebidMobile-*` / `omsdk-android` (Prebid fork), `com.boltive:boltive-sdk` (Boltive mirror) |

---

## npm Packages

Published to npmjs.com under the `@sellwild` org.

```bash
cd core && npm publish --access public
cd react-native && npm publish --access public
```

Publish `@sellwild/sdk-core` **before** `@sellwild/react-native-sdk`, because RN loads core APIs at startup. Publishing requires `npm login` and 2FA. npm only accepts a **security key** (Touch ID or a passkey) for new 2FA: `npm publish` prints an auth link, and you approve it in the browser. Publishers: `rphansen91`, `nsp37`.

| Package | Registry |
|---|---|
| `@sellwild/sdk-core` | [npmjs.com](https://www.npmjs.com/package/@sellwild/sdk-core) |
| `@sellwild/react-native-sdk` | [npmjs.com](https://www.npmjs.com/package/@sellwild/react-native-sdk) |

---

## iOS SDK (CocoaPods)

Published to CocoaPods trunk.

```bash
pod trunk push SellwildSDK.podspec --allow-warnings --synchronous
```

Run it from the repo root (where `SellwildSDK.podspec` lives), at the release tag. If the Prebid fork changed, push `SellwildPrebid` and then `SellwildPrebidGAMEventHandlers` from the fork repo first. See [RELEASING.md](../RELEASING.md). A trunk session for one of the pod owners is required.

| Resource | Value |
|---|---|
| Pod | [SellwildSDK](https://cocoapods.org/pods/SellwildSDK) |
| Trunk Owners | `ryan@antengo.com`, `nicholas.pirollo@gmail.com` |
