import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

// Load signing properties
val keyPropertiesFile = rootProject.file("key.properties")
val keyProperties = Properties()
if (keyPropertiesFile.exists()) {
    keyProperties.load(FileInputStream(keyPropertiesFile))
}

android {
    namespace = "com.app.cardiag"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    kotlin {
        compilerOptions {
            jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11
        }
    }

    // key.properties is git-ignored. Only create the release signing config
    // when it exists — the old unconditional `as String` casts threw during
    // Gradle configuration on a fresh clone/CI, breaking even debug builds.
    signingConfigs {
        if (keyPropertiesFile.exists()) {
            create("release") {
                keyAlias      = keyProperties["keyAlias"]      as String
                keyPassword   = keyProperties["keyPassword"]   as String
                storeFile     = file(keyProperties["storeFile"] as String)
                storePassword = keyProperties["storePassword"] as String
            }
        }
    }

    defaultConfig {
        applicationId = "com.app.cardiag"
        minSdk        = flutter.minSdkVersion
        targetSdk     = flutter.targetSdkVersion
        versionCode   = flutter.versionCode
        versionName   = flutter.versionName
    }

    buildTypes {
        release {
            // null when key.properties is absent — the taskGraph check below
            // then stops the release build instead of shipping a debug-signed
            // "release" by mistake.
            signingConfig = signingConfigs.findByName("release")
            isMinifyEnabled   = false
            isShrinkResources = false
            // Only applied if minify is ever turned on; keeps plugin classes
            // (flutter_blue_plus, notifications/Gson) from being stripped by R8.
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

// Release builds must be signed with the release key; debug builds don't
// need key.properties at all.
gradle.taskGraph.whenReady {
    val releasePackaging = allTasks.any {
        it.project == project &&
            (it.name.startsWith("assemble") || it.name.startsWith("bundle")) &&
            it.name.endsWith("Release")
    }
    if (releasePackaging && !keyPropertiesFile.exists()) {
        throw GradleException(
            "android/key.properties not found: release builds must be signed " +
                "with the release key (keyAlias, keyPassword, storeFile, " +
                "storePassword).",
        )
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    // Firebase BoM keeps versions of any Firebase native libraries (including
    // the ones pulled in transitively by the firebase_core/firebase_messaging
    // Flutter plugins) aligned. No explicit Firebase products need to be
    // listed here — the Flutter plugins bring in what they need.
    implementation(platform("com.google.firebase:firebase-bom:34.17.0"))
}

// Applied conditionally, only once google-services.json exists — keeps
// `flutter build apk` working before Firebase is set up. Push notifications
// stay disabled (NotificationService no-ops) until it's added.
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}
