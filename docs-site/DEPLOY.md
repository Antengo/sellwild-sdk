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

This outputs the AAR and POM to `~/.m2/repository/com/sellwild/sdk/1.0.0/`.

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
| Maven Coordinates | `com.sellwild:sdk:1.0.0` |

---

## npm Packages

Published to npmjs.com under the `@sellwild` org.

```bash
cd core && npm publish --access public
cd react-native && npm publish --access public
```

Requires npm login and 2FA OTP.

| Package | Registry |
|---|---|
| `@sellwild/sdk-core` | [npmjs.com](https://www.npmjs.com/package/@sellwild/sdk-core) |
| `@sellwild/react-native-sdk` | [npmjs.com](https://www.npmjs.com/package/@sellwild/react-native-sdk) |

---

## iOS SDK (CocoaPods)

Published to CocoaPods trunk.

```bash
cd ios && pod trunk push SellwildSDK.podspec
```

Requires trunk session registered to `ryan@antengo.com`.

| Resource | Value |
|---|---|
| Pod | [SellwildSDK](https://cocoapods.org/pods/SellwildSDK) |
| Trunk Account | `ryan@antengo.com` |

---

## Flutter SDK (pub.dev)

Published to pub.dev.

```bash
cd flutter && dart pub publish
```

Authenticates via Google OAuth — use `ryan@antengo.com`.

| Resource | Value |
|---|---|
| Package | [sellwild_sdk](https://pub.dev/packages/sellwild_sdk) |
| Publisher Account | `ryan@antengo.com` |
