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
dependencies { testImplementation("junit:junit:4.13.2") }
