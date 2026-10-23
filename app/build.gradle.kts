plugins { id("com.android.application"); id("org.jetbrains.kotlin.android"); id("org.jetbrains.kotlin.plugin.compose") }
android {
 namespace = "org.pocketpixel"
 compileSdk = 35
 defaultConfig { applicationId = "org.pocketpixel"; minSdk = 29; targetSdk = 35; versionCode = 2; versionName = "0.1.1"; testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner" }
 buildFeatures { compose = true }
 compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
 kotlinOptions { jvmTarget = "17" }
}
dependencies {
 implementation(platform("androidx.compose:compose-bom:2024.12.01"))
 implementation("androidx.activity:activity-compose:1.9.3")
 implementation("androidx.compose.material3:material3")
 implementation("androidx.compose.ui:ui")
 implementation("androidx.compose.foundation:foundation")
 testImplementation("junit:junit:4.13.2")
 androidTestImplementation(platform("androidx.compose:compose-bom:2024.12.01"))
 androidTestImplementation("androidx.compose.ui:ui-test-junit4")
 androidTestImplementation("androidx.test:runner:1.6.2")
 debugImplementation("androidx.compose.ui:ui-test-manifest")
}

// CI release signing is optional for local debug builds. Never commit a private key.
val releaseStore = System.getenv("POCKET_KEYSTORE")
android {
    if (!releaseStore.isNullOrBlank()) {
        signingConfigs {
            create("releaseKey") {
                storeFile = file(releaseStore)
                storePassword = System.getenv("POCKET_STORE_PASSWORD")
                keyAlias = System.getenv("POCKET_KEY_ALIAS")
                keyPassword = System.getenv("POCKET_KEY_PASSWORD")
            }
        }
        buildTypes.getByName("release") { signingConfig = signingConfigs.getByName("releaseKey") }
    }
}
