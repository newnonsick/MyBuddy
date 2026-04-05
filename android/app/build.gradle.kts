import java.util.Properties

import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

dependencies {
    implementation(project(":unityLibrary"))
    // Required for flutter_local_notifications desugaring
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { stream ->
        keystoreProperties.load(stream)
    }
}

val releaseTaskRequested = gradle.startParameter.taskNames.any {
    it.contains("Release", ignoreCase = true)
}

val strictReleaseSigning = providers.gradleProperty("strictReleaseSigning")
    .orNull
    ?.toBooleanStrictOrNull()
    ?: false

val isCiBuild = providers.environmentVariable("CI")
    .orNull
    ?.equals("true", ignoreCase = true)
    ?: false

android {
    namespace = "com.example.mybuddy"
    compileSdk = 36
    ndkVersion = "29.0.13113456"

    signingConfigs {
        create("release") {
            val storeFilePath = keystoreProperties.getProperty("storeFile")
            if (!storeFilePath.isNullOrBlank()) {
                storeFile = file(storeFilePath)
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    compileOptions {
        // Enable core library desugaring for flutter_local_notifications
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlin {
        compilerOptions {
            jvmTarget.set(JvmTarget.JVM_11)
        }
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.mybuddy"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            val hasReleaseSigning =
                !keystoreProperties.getProperty("storeFile").isNullOrBlank()

            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            } else {
                signingConfig = signingConfigs.getByName("debug")

                if (releaseTaskRequested && (strictReleaseSigning || isCiBuild)) {
                    throw org.gradle.api.GradleException(
                        "Release signing is not configured. Create android/key.properties with storeFile, storePassword, keyAlias, and keyPassword.",
                    )
                }

                if (releaseTaskRequested) {
                    logger.warn(
                        "Release signing is not configured. Falling back to debug signing for local build.",
                    )
                }
            }
        }
    }
}

flutter {
    source = "../.."
}
