plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}
android {
    namespace = "org.pocketpixel"
    compileSdk = 36
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    defaultConfig {
        applicationId = "org.pocketpixel"
        minSdk = 29
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }
    sourceSets.getByName("test").resources.srcDir("../../app/src/test/resources")
    // Provider metadata tests use Config.NONE and need no app resources/assets.
    // Including them also pulls Flutter's assets into AGP's host-test packaging.
    testOptions.unitTests.all {
        it.jvmArgs(
            "--add-opens=java.base/java.lang=ALL-UNNAMED",
            "--add-opens=java.base/java.util=ALL-UNNAMED",
            "--add-opens=java.base/java.io=ALL-UNNAMED",
            "--add-opens=java.base/java.net=ALL-UNNAMED",
            "--add-opens=java.base/java.security=ALL-UNNAMED",
            "--add-opens=java.base/java.text=ALL-UNNAMED",
            "--add-opens=java.base/jdk.internal.access=ALL-UNNAMED",
            "--add-opens=java.desktop/java.awt.font=ALL-UNNAMED",
            "--add-opens=jdk.compiler/com.sun.tools.javac.api=ALL-UNNAMED",
        )
    }
    buildTypes.getByName("debug") {
        applicationIdSuffix = ".debug"
        versionNameSuffix = "-dev"
    }
    val releaseStore = System.getenv("POCKET_KEYSTORE")
    if (!releaseStore.isNullOrBlank()) {
        signingConfigs.create("releaseKey") {
            storeFile = file(releaseStore)
            storePassword = System.getenv("POCKET_STORE_PASSWORD")
            keyAlias = System.getenv("POCKET_KEY_ALIAS")
            keyPassword = System.getenv("POCKET_KEY_PASSWORD")
        }
        buildTypes.getByName("release") { signingConfig = signingConfigs.getByName("releaseKey") }
    }
}
kotlin { compilerOptions { jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17 } }
flutter { source = "../.." }
dependencies {
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.robolectric:robolectric:4.17")
}
