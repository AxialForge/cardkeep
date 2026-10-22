import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing: android/key.properties (git-ignored; CI writes it from secrets).
// Without it a release build stops (audit MOB-BLD-0002), so an APK signed with the
// debug key can never ship by accident. For a throwaway local check, opt in with
// CARDKEEP_DEBUG_SIGNING=1 in the environment.
val keyProps = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}

android {
    namespace = "com.axialforge.cardkeep"
    // 37: permission_handler 13 requires it. Does not change which phones can install (minSdk).
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true // flutter_local_notifications (java.time on older Android)
    }

    defaultConfig {
        applicationId = "com.axialforge.cardkeep"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keyProps.containsKey("storeFile")) {
            create("release") {
                storeFile = rootProject.file(keyProps.getProperty("storeFile"))
                storePassword = keyProps.getProperty("storePassword")
                keyAlias = keyProps.getProperty("keyAlias")
                keyPassword = keyProps.getProperty("keyPassword")
                // v3 lets the signing key be rotated later without breaking updates (MOB-BLD-0005).
                enableV2Signing = true
                enableV3Signing = true
            }
        }
    }

    buildTypes {
        release {
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfig = signingConfigs.findByName("release")
                ?: if (System.getenv("CARDKEEP_DEBUG_SIGNING") == "1") {
                    signingConfigs.getByName("debug")
                } else {
                    null
                }
        }
    }
}

// No release key and no opt-in: fail the release build instead of shipping a debug-signed APK.
gradle.taskGraph.whenReady {
    val release = allTasks.any { it.project == project && (it.name == "assembleRelease" || it.name == "bundleRelease") }
    if (release && android.buildTypes.getByName("release").signingConfig == null) {
        throw GradleException("No android/key.properties: release builds need the release key (set CARDKEEP_DEBUG_SIGNING=1 for a local test build)")
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
