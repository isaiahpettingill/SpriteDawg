import com.android.build.api.dsl.LibraryExtension

plugins {
    id("com.android.library") apply false
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

// flutter_avif_android 3.1.0 predates AGP's built-in Kotlin and requests Java 11.
// Align only this plugin's Android DSL with AGP 9's Kotlin/JDK 17 target; do not
// suppress target validation or alter unrelated plugins.
subprojects {
    if (name == "flutter_avif_android") {
        // The pinned plugin's only Kotlin file duplicates its Java registrar.
        // AGP supplies Kotlin's default directory even when its DSL set is empty.
        // Do not compile that redundant template; Java and JNI remain unchanged.
        tasks.matching { it.name.startsWith("compile") && it.name.endsWith("Kotlin") }
            .configureEach { enabled = false }
        afterEvaluate {
            val kotlinTemplates = fileTree("src") { include("**/*.kt") }.files
            check(kotlinTemplates.size == 1 &&
                kotlinTemplates.single().relativeTo(projectDir).invariantSeparatorsPath ==
                    "src/main/kotlin/com/teknorota/flutter_avif/FlutterAvifPlugin.kt") {
                "Review flutter_avif_android source changes before skipping its duplicate registrar"
            }
            extensions.configure<LibraryExtension> {
                // Match the app's compile SDK for Flutter embedding AndroidX
                // dependencies; minimum supported Android remains unchanged.
                compileSdk = 36
                // Upstream ships equivalent Java and Kotlin registrar stubs.
                // AGP 9 compiles Kotlin automatically. Retain the Java stub
                // that upstream previously compiled, not the duplicate Kotlin
                // template. This pinned plugin contains no other Kotlin code.
                compileOptions {
                    sourceCompatibility = JavaVersion.VERSION_17
                    targetCompatibility = JavaVersion.VERSION_17
                }
            }
        }
    }
}
