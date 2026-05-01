# SDK Deployment Guide

How to build, version, and publish each platform SDK.

---

## Versioning

All five platform packages should stay in sync on the same version number. Before any release:

1. Update version in:
   - `core/package.json`
   - `react-native/package.json` (also bump the `@sellwild/sdk-core` dep version)
   - `ios/Package.swift` (tag-based, update git tag)
   - `ios/SellwildSDK.podspec` → `s.version`
   - `android/build.gradle.kts` → `version = "x.y.z"`
   - `flutter/pubspec.yaml` → `version:`
   - `flutter/CHANGELOG.md` (pub.dev requires an entry for every version)

2. Tag the git commit. **Push two tags — both `vX.Y.Z` and `X.Y.Z`** —
   because SPM/CocoaPods resolve by the bare version while our own conventions
   prefer `v`-prefixed tags:
   ```bash
   git tag v1.1.0
   git tag 1.1.0
   git push origin v1.1.0 1.1.0
   ```

---

## Core (TypeScript)

The core package is published to npm as `@sellwild/sdk-core` and is also a
build/runtime dependency for the React Native SDK. **Publish core first**, then
React Native (so the RN package can resolve the new core version from the
registry).

```bash
cd sdk/core
npm install
npm run build   # outputs compiled JS + types to dist/
```

> ⚠️ Verify `package.json` `main` and `types` point into `dist/` (e.g.
> `dist/index.js`, `dist/index.d.ts`) — **never** ship `src/index.ts` as the
> entry point. Consumers should not have to compile our sources.

Publish to npm:
```bash
npm publish --access public
```

---

## React Native

### Build

The RN package ships source (`.tsx`/`.ts`) — no separate build step. npm packaging handles it.

### Publish to npm

```bash
cd sdk/react-native
npm publish --access public
```

For a scoped private registry (GitHub Packages, Artifactory):
```bash
npm publish --registry https://npm.pkg.github.com
```

### Local development (linking into a host app)

```bash
cd sdk/react-native
npm link

cd /path/to/host-app
npm link @sellwild/react-native-sdk
```

Or with Yarn workspaces — add to the host app's `package.json`:
```json
{
  "workspaces": ["../sdk/react-native"]
}
```

---

## iOS

### Requirements
- Xcode 14+
- Swift 5.5+
- CocoaPods 1.12+ (for pod publishing)

### Test locally before publishing

```bash
cd sdk/ios
# Build and run tests
xcodebuild test \
  -scheme SellwildSDK \
  -destination 'platform=iOS Simulator,name=iPhone 15'
```

Or open in Xcode:
```bash
open Package.swift
```

### Swift Package Manager (SPM)

SPM uses git tags and resolves by **bare SemVer** (`1.1.0`, not `v1.1.0`).
After pushing both `v1.1.0` and `1.1.0` tags (see [Versioning](#versioning)),
consumers add the package via its git URL:
```
https://github.com/sellwild/sdk-ios.git
```

No separate publish step — the tag IS the release.

### CocoaPods

CocoaPods also resolves by bare SemVer. The `1.1.0` tag (no `v` prefix) **must
exist on the remote** before `pod trunk push`, otherwise lint fails with
`Unable to find a specification for SellwildSDK (= 1.1.0)`.

1. Validate the podspec:
   ```bash
   cd sdk/ios
   pod spec lint SellwildSDK.podspec --allow-warnings
   ```

2. Publish to the CocoaPods trunk:
   ```bash
   pod trunk push SellwildSDK.podspec --allow-warnings
   ```
   (Requires a CocoaPods trunk account: `pod trunk register sdk@sellwild.com`)

3. For a private spec repo (recommended for internal distribution):
   ```bash
   pod repo push sellwild-specs SellwildSDK.podspec --allow-warnings
   ```

---

## Android

### Requirements
- JDK 17
- Android SDK with API 35 build tools
- Gradle 8+

### Build the library AAR

```bash
cd sdk/android
./gradlew assembleRelease
# Output: build/outputs/aar/sdk-release.aar
```

### Run unit tests

```bash
./gradlew test
```

### Publish to the Sellwild Maven repo (S3-backed)

The public Sellwild Maven repo is `https://maven.sellwild.com/releases`, backed
by `s3://maven.sellwild.com/releases/` and fronted by CloudFront.

> ⚠️ **Do not use `publishToMavenLocal` followed by `aws s3 sync`.** That produces
> `maven-metadata-local.xml` (wrong filename) and skips checksum generation
> (`.md5` / `.sha1`). Gradle dynamic version resolution (`1.+`, `1.1.+`,
> `latest.release`) will silently fail. Always publish directly to the S3 repo
> as shown below — Gradle will write the correct `maven-metadata.xml` and
> checksums for every artifact.

**One-time setup**

1. Install the Gradle `maven-publish-s3` wagon (already wired into
   `android/build.gradle.kts`) — no extra plugin needed; Gradle's built-in
   `maven { url = "s3://..." }` support is used.
2. Configure AWS credentials. Either:
   - Have a working `aws configure` profile (the default profile is used), **or**
   - Export `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` for a user with
     `s3:PutObject` on `arn:aws:s3:::maven.sellwild.com/releases/*`.

**Publishing block in `android/build.gradle.kts`**

```kotlin
publishing {
    publications {
        register<MavenPublication>("release") {
            groupId = "com.sellwild"
            artifactId = "sdk"
            version = "1.1.0"
            afterEvaluate { from(components["release"]) }
            pom {
                name.set("Sellwild SDK")
                description.set("Sellwild mobile advertising SDK for Android")
                url.set("https://github.com/sellwild/sdk-android")
            }
        }
    }
    repositories {
        maven {
            name = "SellwildS3"
            url = uri("s3://maven.sellwild.com/releases")
            credentials(AwsCredentials::class) {
                accessKey = System.getenv("AWS_ACCESS_KEY_ID")
                    ?: (project.findProperty("aws.accessKey") as String?)
                secretKey = System.getenv("AWS_SECRET_ACCESS_KEY")
                    ?: (project.findProperty("aws.secretKey") as String?)
            }
        }
    }
}
```

**Publish**

```bash
cd sdk/android
./gradlew clean assembleRelease
./gradlew publishReleasePublicationToSellwildS3Repository
```

This uploads, in one shot:

- `sdk-1.1.0.aar` + `.md5` + `.sha1`
- `sdk-1.1.0.pom` + `.md5` + `.sha1`
- `sdk-1.1.0.module` + `.md5` + `.sha1`     ← Gradle Module Metadata
- `sdk-1.1.0-sources.jar` + `.md5` + `.sha1`
- `maven-metadata.xml` + `.md5` + `.sha1`   ← **correct filename, with checksums**

**Invalidate CloudFront after publish**

```bash
aws cloudfront create-invalidation \
  --distribution-id E2I8MYVEM6ZX5R \
  --paths "/releases/com/sellwild/sdk/*"
```

**Verify**

```bash
# Pinned version + dynamic version both resolve:
curl -sI https://maven.sellwild.com/releases/com/sellwild/sdk/maven-metadata.xml
curl -s  https://maven.sellwild.com/releases/com/sellwild/sdk/maven-metadata.xml \
  | grep -E "<latest>|<release>|<version>"
```

A consumer app then resolves it with:

```kotlin
repositories {
    maven { url = uri("https://maven.sellwild.com/releases") }
    google()
    mavenCentral()
}

dependencies {
    implementation("com.sellwild:sdk:1.1.0")  // or "com.sellwild:sdk:1.+"
}
```

### Publish to local Maven repository (for testing only)

```bash
./gradlew publishToMavenLocal
# Output lands in ~/.m2/repository/com/sellwild/sdk/
```

> Note: this writes `maven-metadata-local.xml` (Gradle's local-only convention).
> **Never** sync that directory directly to S3 — use the S3 publish task above.

Host app consumes the local copy via:
```kotlin
repositories {
    mavenLocal()
    google()
    mavenCentral()
}
```

### Repairing a broken Maven repo (if `maven-metadata-local.xml` slipped through)

If you suspect a previous release was uploaded via `s3 sync` and is missing the
proper metadata file or checksums:

```bash
cd /tmp && mkdir -p maven-fix && cd maven-fix
aws s3 sync s3://maven.sellwild.com/releases/com/sellwild/sdk/ ./sdk/

# Rename if needed
[ -f sdk/maven-metadata-local.xml ] && \
  mv sdk/maven-metadata-local.xml sdk/maven-metadata.xml

# Generate checksums for everything missing them
cd sdk
for f in $(find . -type f ! -name "*.md5" ! -name "*.sha1"); do
  [ -f "$f.md5"  ] || md5    -q "$f" > "$f.md5"
  [ -f "$f.sha1" ] || shasum -a 1 "$f" | awk '{print $1}' > "$f.sha1"
done

aws s3 sync . s3://maven.sellwild.com/releases/com/sellwild/sdk/
aws cloudfront create-invalidation \
  --distribution-id E2I8MYVEM6ZX5R \
  --paths "/releases/com/sellwild/sdk/*"
```

### Publish to Maven Central (future)

Requires signing config and Sonatype credentials. Add to `build.gradle.kts`:
```kotlin
signing {
    useGpgCmd()
    sign(publishing.publications)
}
```

Then:
```bash
./gradlew publishToSonatype closeAndReleaseSonatypeStagingRepository
```

---

## Flutter

### Requirements
- Flutter 3.10+
- Dart 3.0+

### Validate the package

```bash
cd sdk/flutter
flutter pub get
flutter analyze
flutter test
dart pub publish --dry-run   # checks everything before actual publish
```

### Publish to pub.dev

```bash
dart pub publish
```

You'll be prompted to authenticate with your Google account. The package will be at:
```
https://pub.dev/packages/sellwild_sdk
```

### For private distribution (not pub.dev)

Host the package in a private git repo and reference it in the host app's `pubspec.yaml`:
```yaml
dependencies:
  sellwild_sdk:
    git:
      url: https://github.com/sellwild/sdk-flutter.git
      ref: v1.0.0
```

Or use a private pub server (e.g., `pub_server` or Cloudsmith):
```yaml
dependency_overrides:
  sellwild_sdk:
    hosted:
      name: sellwild_sdk
      url: https://your-private-pub-server.com
    version: ^1.0.0
```

---

## CI/CD (GitHub Actions example)

### React Native — publish on tag

```yaml
# .github/workflows/publish-rn.yml
name: Publish React Native SDK
on:
  push:
    tags: ['v*']
jobs:
  publish:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
          registry-url: 'https://registry.npmjs.org'
      - run: cd sdk/core && npm ci && npm run build
      - run: cd sdk/react-native && npm ci && npm publish
        env:
          NODE_AUTH_TOKEN: ${{ secrets.NPM_TOKEN }}
```

### Flutter — publish on tag

```yaml
# .github/workflows/publish-flutter.yml
name: Publish Flutter SDK
on:
  push:
    tags: ['v*']
jobs:
  publish:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.19.0'
      - run: cd sdk/flutter && flutter pub get && flutter test
      - uses: k-paxian/dart-package-publisher@v1.6
        with:
          flutter: true
          relativePath: sdk/flutter
          credentialJson: ${{ secrets.PUB_CREDENTIALS }}
```

---

## What `widget.sellwild.com` needs to serve

The SDK WebViews load two scripts from the CDN:

| File | Purpose |
|------|---------|
| `https://widget.sellwild.com/widget.js` | The compiled sellwild-widget bundle |
| `https://widget.sellwild.com/prebid.js` | Prebid.js with configured bidder adapters |

These are already built and deployed by the existing `sellwild-widget` deploy pipeline (`npm run deploy`). The SDK's WebViews simply load whatever is live at that URL.

**To use a staging version**, set `prebidSrc` and override the widget URL via the `__SELLWILD_SDK_CONFIG__` window object injected into the WebView HTML (see `htmlBuilder.ts`, `SellwildWidgetView.swift`, `SellwildWidgetView.kt`).

### Zone-based ad delivery

The zone script URL `https://bidstream.sellwild.com/ads?zone=<ID>&w=<W>&h=<H>` must be set up on the Sellwild infrastructure side. Confirm the correct base URL with the ad ops team before enabling zone-based delivery for a publisher.

---

## Admin Dashboard (Netlify)

The admin dashboard is a Vite + React app deployed to Netlify with serverless functions for the backend (Athena/CloudWatch queries) and Netlify Identity for authentication.

**Live URL:** https://sellwild-admin.netlify.app
**Netlify Admin:** https://app.netlify.com/projects/sellwild-admin
**Site ID:** `7fbfd204-d02b-4323-8713-d61f0769873d`

### Architecture

```
dashboard/
├── index.html              # Loads Netlify Identity widget
├── netlify.toml             # Build, functions, and redirect config
├── vite.config.ts           # Vite config with @/ alias
├── src/
│   ├── main.tsx             # Entry point (React + Router)
│   ├── App.tsx              # Auth gate + routes
│   ├── hooks/useAuth.ts     # Netlify Identity hook (same as CMS)
│   ├── pages/               # Overview, AuctionFeed, AuctionDetail
│   ├── components/          # Layout, charts, filters, stats-card
│   └── lib/                 # Client-side types + data hooks
└── netlify/functions/
    ├── auctions.ts          # Athena queries (overview, bidder_summary, etc.)
    ├── logs.ts              # CloudWatch auction log queries
    └── lib/
        ├── athena-client.ts # AWS Athena SDK wrapper
        └── cloudwatch.ts    # AWS CloudWatch Logs SDK wrapper
```

### Deploy

The dashboard deploys from the CLI. There is no CI/CD pipeline — deploy manually:

```bash
cd dashboard
npx netlify deploy --prod
```

This builds the Vite app, bundles the Netlify Functions, and pushes everything live. The build command (`npm run build`) runs automatically as part of the deploy.

### Environment Variables

AWS credentials are set on Netlify with `SW_` prefix (Netlify reserves `AWS_*` names):

| Variable | Value | Purpose |
|----------|-------|---------|
| `SW_AWS_ACCESS_KEY_ID` | IAM access key | Athena + CloudWatch access |
| `SW_AWS_SECRET_ACCESS_KEY` | IAM secret key | Athena + CloudWatch access |
| `SW_AWS_REGION` | `us-west-1` | AWS region for Prebid Server infra |

To update env vars:

```bash
cd dashboard
npx netlify env:set SW_AWS_ACCESS_KEY_ID "new-key-value"
npx netlify env:set SW_AWS_SECRET_ACCESS_KEY "new-secret-value"
```

Or update them in the Netlify UI: **Site Settings > Environment Variables**.

The functions also fall back to `AWS_REGION` / default SDK credential chain, so local development works with your `~/.aws/credentials` without any extra setup.

### Authentication (Netlify Identity)

The dashboard uses **Netlify Identity** — the same auth system as the CMS (`sellwild-widget/cms`).

- The Netlify Identity widget script is loaded in `index.html`
- `useAuth.ts` hooks into `window.netlifyIdentity` for login/logout/session
- Unauthenticated users see a login page; authenticated users see the dashboard

**Managing users:**

1. Go to https://app.netlify.com/projects/sellwild-admin/identity
2. Click **Invite users** to add new team members
3. Set **Registration** to **Invite only** to prevent public signups

### Local Development

```bash
cd dashboard
npm install
npm run dev          # Vite dev server on http://localhost:3100
```

For functions to work locally, use the Netlify CLI:

```bash
npx netlify dev      # Runs Vite + Functions on http://localhost:8888
```

The Vite dev server proxies `/.netlify/functions/*` to `localhost:8888` so both modes work. Local functions use your `~/.aws/credentials` for AWS access.

### Updating the Dashboard

1. Make changes in `dashboard/`
2. Test locally: `npm run dev` or `npx netlify dev`
3. Type check: `npm run typecheck`
4. Deploy: `npx netlify deploy --prod`

---

## Checklist before first release

- [ ] Partner code and listings URL confirmed with publisher
- [ ] `widget.sellwild.com/widget.js` is live and serving the latest build
- [ ] GAM ad unit path created in Google Ad Manager for the publisher
- [ ] Zone IDs provisioned for publisher (if using zone-based delivery)
- [ ] Prebid bidder credentials collected from ad networks
- [ ] ATS / cleartext traffic configured in host app
- [ ] WebView debugging tested end-to-end in simulator/emulator
- [ ] Ad refresh limits confirmed with ad ops (typical: 5 refreshes / 30s interval)
- [ ] SDK version tagged and published to the appropriate registry
