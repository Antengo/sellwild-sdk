package com.sellwild.sdk.support

import org.junit.platform.launcher.LauncherSession
import org.junit.platform.launcher.LauncherSessionListener

/**
 * Installs [NetworkBlock] when the JUnit Platform launcher opens its session, before any test
 * class loads. Registered in
 * `src/test/resources/META-INF/services/org.junit.platform.launcher.LauncherSessionListener`;
 * android/build.gradle.kts runs the JUnit 4 tests on the platform's vintage engine.
 *
 * Not `-Djava.protocol.handler.pkgs`: set at JVM start, it reorders the Gradle worker's
 * classpath so android.jar's org.json stubs shadow org.json:json and the JSON tests fail.
 */
class NetworkBlockSessionListener : LauncherSessionListener {
    override fun launcherSessionOpened(session: LauncherSession) {
        NetworkBlock.install(by = INSTALLER)
    }

    companion object {
        const val INSTALLER = "NetworkBlockSessionListener"
    }
}
