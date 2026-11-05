#!/usr/bin/env node
// Checks for the React Native native bridges (react-native/ios and
// react-native/android). Those files only run for real inside an RN host app,
// which this repo does not build, so they are outside the coverage gate. These
// checks run what can run without one:
//
//   --swift   ios/main.swift against react-native/ios/SellwildRNBridgeRules.swift
//             (Foundation only), built and run on the Mac with xcrun swiftc;
//             then every react-native/ios file type-checked against the
//             SellwildSDK module scripts/coverage/ios.sh builds (skipped when
//             it has not been built) and a React stand-in (ios/React.swift).
//   --kotlin  android/checks/*.kt against every react-native/android glue file,
//             compiled at Kotlin language 1.9 (as react-native/android/build.gradle
//             pins it) and run on the JVM. React Native and the Prebid fork are
//             replaced by android/api-stubs (compile time) and
//             android/runtime-stubs (run time); the Sellwild Android SDK is
//             its own compiled classes.
//
// Usage (from anywhere; both when neither flag is given):
//   node react-native/native-checks/run.mjs [--swift] [--kotlin]
//
// Needs: Xcode (--swift). JDK 17, the Android SDK platform
// jar, the Kotlin compiler in the Gradle cache (the version android/ pins), and
// the Android SDK compiled once: bash scripts/coverage/android.sh, or
// cd android && ./gradlew compileDebugKotlin (--kotlin). It builds into
// native-checks/.build (git-ignored) from scratch on every run, so a changed
// glue file is always what runs. Exit 0 when every check passes.
import { spawnSync } from 'node:child_process'
import { existsSync, mkdirSync, readdirSync, readFileSync, rmSync, statSync } from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const HERE = path.dirname(fileURLToPath(import.meta.url))
const RN = path.dirname(HERE)
const ROOT = path.dirname(RN)
const OUT = process.env.NATIVE_CHECKS_OUT ?? path.join(HERE, '.build')

class Setup extends Error {}

function run (label, cmd, args) {
  const res = spawnSync(cmd, args, { stdio: 'inherit' })
  if (res.error) throw new Setup(`${label}: ${res.error.message}`)
  return res.status ?? 1
}

function must (label, cmd, args) {
  const status = run(label, cmd, args)
  if (status !== 0) throw new Setup(`${label} failed (exit ${status})`)
}

/** Every file under `dir` ending in `ext`, sorted. */
function filesIn (dir, ext) {
  const out = []
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name)
    if (entry.isDirectory()) out.push(...filesIn(full, ext))
    else if (entry.name.endsWith(ext)) out.push(full)
  }
  return out.sort()
}

function newestMtime (dir) {
  let newest = 0
  for (const file of filesIn(dir, '')) newest = Math.max(newest, statSync(file).mtimeMs)
  return newest
}

function swift () {
  const out = path.join(OUT, 'swift')
  rmSync(out, { recursive: true, force: true })
  mkdirSync(out, { recursive: true })
  const bin = path.join(out, 'rules')
  must('swiftc', 'xcrun', ['swiftc', '-o', bin, path.join(RN, 'ios', 'SellwildRNBridgeRules.swift'), path.join(HERE, 'ios', 'main.swift')])
  const status = run('swift checks', bin, [])
  return typecheckIosGlue(out) || status
}

// The iOS SDK as scripts/coverage/ios.sh builds it for the simulator.
const IOS_PRODUCTS = path.join(ROOT, '.coverage-tmp', 'ios-dd', 'Build', 'Products', 'Debug-iphonesimulator')
const IOS_TARGET = 'arm64-apple-ios15.0-simulator'

/**
 * Type-checks every react-native/ios file against the built SellwildSDK
 * module and the React stand-in (ios/React.swift). Skipped, with a note, when
 * the iOS SDK has not been built. 0 when it type-checks.
 */
function typecheckIosGlue (out) {
  if (!existsSync(path.join(IOS_PRODUCTS, 'SellwildSDK.swiftmodule'))) {
    console.warn('native-checks: the iOS glue type-check was skipped: build the iOS SDK once (bash scripts/coverage/ios.sh)')
    return 0
  }
  const react = path.join(out, 'react')
  mkdirSync(react, { recursive: true })
  const sim = ['--sdk', 'iphonesimulator', 'swiftc', '-target', IOS_TARGET]
  must('swiftc React stand-in', 'xcrun', [...sim, '-emit-module', '-module-name', 'React', '-o', path.join(react, 'React.swiftmodule'), path.join(HERE, 'ios', 'React.swift')])
  const status = run('swiftc -typecheck react-native/ios', 'xcrun', [...sim, '-typecheck', '-I', react, '-I', IOS_PRODUCTS, ...filesIn(path.join(RN, 'ios'), '.swift')])
  console.log(status === 0 ? 'react-native/ios type-checks' : 'react-native/ios does not type-check')
  return status
}

// ── Kotlin ──────────────────────────────────────────────────────────────────

const GRADLE_CACHE = path.join(process.env.GRADLE_USER_HOME ?? path.join(os.homedir(), '.gradle'), 'caches', 'modules-2', 'files-2.1')

/** A jar (or pom) from the Gradle cache. */
function cached (group, artifact, version, ext = 'jar') {
  const dir = path.join(GRADLE_CACHE, group, artifact, version)
  const name = `${artifact}-${version}.${ext}`
  if (existsSync(dir)) {
    for (const hash of readdirSync(dir)) {
      const file = path.join(dir, hash, name)
      if (existsSync(file)) return file
    }
  }
  throw new Setup(`${group}:${name} is not in the Gradle cache (${GRADLE_CACHE}). Build the Android SDK once: bash scripts/coverage/android.sh`)
}

/** The newest version of an artifact in the Gradle cache. */
function newestCached (group, artifact) {
  const dir = path.join(GRADLE_CACHE, group, artifact)
  const versions = existsSync(dir) ? readdirSync(dir) : []
  versions.sort((a, b) => a.localeCompare(b, 'en', { numeric: true }))
  if (!versions.length) throw new Setup(`${group}:${artifact} is not in the Gradle cache`)
  return cached(group, artifact, versions[versions.length - 1])
}

/** The Kotlin version android/settings.gradle.kts pins. */
function kotlinVersion () {
  const settings = readFileSync(path.join(ROOT, 'android', 'settings.gradle.kts'), 'utf8')
  const match = /id\("org\.jetbrains\.kotlin\.android"\) version "([^"]+)"/.exec(settings)
  if (!match) throw new Setup('no Kotlin version in android/settings.gradle.kts')
  return match[1]
}

/** The Kotlin compiler's jars: kotlin-compiler-embeddable and its runtime dependencies from its pom. */
function kotlinCompiler (version) {
  const pom = readFileSync(cached('org.jetbrains.kotlin', 'kotlin-compiler-embeddable', version, 'pom'), 'utf8')
  const jars = [cached('org.jetbrains.kotlin', 'kotlin-compiler-embeddable', version)]
  for (const [, block] of pom.matchAll(/<dependency>([\s\S]*?)<\/dependency>/g)) {
    const tag = (name) => new RegExp(`<${name}>([^<]+)</${name}>`).exec(block)?.[1]
    if (['test', 'provided'].includes(tag('scope'))) continue
    jars.push(cached(tag('groupId'), tag('artifactId'), tag('version')))
  }
  return jars
}

function javaHome () {
  const pinned = '/Library/Java/JavaVirtualMachines/jdk-17.0.1.jdk/Contents/Home'
  if (process.env.JAVA_HOME_17) return process.env.JAVA_HOME_17
  if (existsSync(pinned)) return pinned
  const found = spawnSync('/usr/libexec/java_home', ['-v', '17'], { encoding: 'utf8' })
  if (found.status === 0) return found.stdout.trim()
  throw new Setup('no JDK 17 (set JAVA_HOME_17)')
}

/** The android.jar of the platform android/build.gradle.kts compiles against. */
function androidJar () {
  const sdk = process.env.ANDROID_HOME ?? process.env.ANDROID_SDK_ROOT ?? path.join(os.homedir(), 'Library', 'Android', 'sdk')
  const build = readFileSync(path.join(ROOT, 'android', 'build.gradle.kts'), 'utf8')
  const level = /compileSdk\s*=\s*(\d+)/.exec(build)?.[1]
  const jar = path.join(sdk, 'platforms', `android-${level}`, 'android.jar')
  if (!level || !existsSync(jar)) throw new Setup(`no android.jar for compileSdk ${level} under ${sdk}/platforms`)
  return jar
}

function kotlin () {
  const out = path.join(OUT, 'android')
  rmSync(out, { recursive: true, force: true })
  const api = path.join(out, 'api')
  const runtime = path.join(out, 'runtime')
  const classes = path.join(out, 'classes')
  for (const dir of [api, runtime, classes]) mkdirSync(dir, { recursive: true })

  const java = javaHome()
  const version = kotlinVersion()
  const stdlib = cached('org.jetbrains.kotlin', 'kotlin-stdlib', version)
  const annotations = cached('org.jetbrains', 'annotations', '13.0')
  const json = newestCached('org.json', 'json')
  const platform = androidJar()
  const sdkClasses = path.join(ROOT, 'android', 'build', 'tmp', 'kotlin-classes', 'debug')
  if (!existsSync(sdkClasses)) {
    throw new Setup('the Android SDK is not compiled. Run: bash scripts/coverage/android.sh (or cd android && ./gradlew compileDebugKotlin)')
  }
  if (newestMtime(path.join(ROOT, 'android', 'src', 'main')) > newestMtime(sdkClasses)) {
    console.warn('native-checks: android/src/main changed since the SDK was last compiled; these checks run against the older SDK classes')
  }

  must('javac api-stubs', path.join(java, 'bin', 'javac'), ['-nowarn', '-d', api, '-cp', [platform, annotations].join(':'), ...filesIn(path.join(HERE, 'android', 'api-stubs'), '.java')])
  must('javac runtime-stubs', path.join(java, 'bin', 'javac'), ['-nowarn', '-d', runtime, '-cp', api, ...filesIn(path.join(HERE, 'android', 'runtime-stubs'), '.java')])

  // The glue and the checks in one compile. The API stubs come before the
  // runtime ones, so the glue compiles against the React Native API; the
  // Prebid stand-ins are only in the runtime set. The friend path lets the
  // checks bind a fake failure sink (SellwildFailures internals).
  const glue = filesIn(path.join(RN, 'android', 'src', 'main', 'java'), '.kt')
  const checks = filesIn(path.join(HERE, 'android', 'checks'), '.kt')
  must('kotlinc', path.join(java, 'bin', 'java'), [
    // annotations comes with kotlin-stdlib (a dependency of its own).
    '-Xmx768m', '-cp', [...kotlinCompiler(version), annotations].join(':'), 'org.jetbrains.kotlin.cli.jvm.K2JVMCompiler',
    '-no-reflect', '-no-stdlib', '-nowarn', '-jvm-target', '17', '-language-version', '1.9', '-api-version', '1.9',
    `-Xfriend-paths=${sdkClasses}`,
    '-classpath', [api, runtime, sdkClasses, platform, annotations, stdlib].join(':'),
    '-d', classes, ...glue, ...checks,
  ])

  // Run time: the runtime stand-ins first (a ReactContext with no Android
  // Context, a UI thread that queues), org.json before android.jar (whose
  // copy is a stub that throws).
  return run('kotlin checks', path.join(java, 'bin', 'java'), [
    '-Xmx256m', '-cp', [runtime, api, classes, sdkClasses, stdlib, json, platform].join(':'), 'com.sellwild.rnsdk.GlueChecksKt',
  ])
}

const args = process.argv.slice(2)
const unknown = args.filter((a) => !['--swift', '--kotlin'].includes(a))
if (unknown.length) {
  console.error(`native-checks: unknown option ${unknown.join(' ')}. Use --swift, --kotlin or neither.`)
  process.exit(2)
}
const suites = args.length ? args.map((a) => a.slice(2)) : ['swift', 'kotlin']
let status = 0
for (const suite of suites) {
  console.log(`native-checks: ${suite}`)
  try {
    const code = suite === 'swift' ? swift() : kotlin()
    if (code !== 0) status = 1
  } catch (error) {
    if (!(error instanceof Setup)) throw error
    console.error(`native-checks: ${error.message}`)
    status = 2
  }
}
process.exit(status)
