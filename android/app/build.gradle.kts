plugins {
    id("com.android.application")
    id("kotlin-android")
    id("com.google.devtools.ksp")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePath = providers.environmentVariable("KEYSTORE_PATH").orNull?.takeIf { it.isNotEmpty() }
val keystoreAlias = providers.environmentVariable("KEYSTORE_ALIAS").orNull?.takeIf { it.isNotEmpty() }
val keystorePassword = providers.environmentVariable("KEYSTORE_PASSWORD").orNull?.takeIf { it.isNotEmpty() }
val hasReleaseSigning = keystorePath != null || keystoreAlias != null || keystorePassword != null
require(!hasReleaseSigning || (keystorePath != null && keystoreAlias != null && keystorePassword != null)) {
    "Release signing requires KEYSTORE_PATH, KEYSTORE_ALIAS, and KEYSTORE_PASSWORD."
}

android {
    namespace = "tw.avianjay.tako"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = providers.gradleProperty("tako.applicationId").get()
        manifestPlaceholders["takoAppName"] = providers.gradleProperty("tako.appName").get()
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Google Play restricts AccessibilityService use, so screen control lives
    // in the `full` flavor (GitHub Releases / F-Droid) and `play` omits it.
    flavorDimensions += "distribution"
    productFlavors {
        create("full") {
            dimension = "distribution"
        }
        create("play") {
            dimension = "distribution"
        }
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(requireNotNull(keystorePath))
                storePassword = keystorePassword
                keyAlias = keystoreAlias
                keyPassword = keystorePassword
            }
        }
    }

    buildTypes {
        release {
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            // Local and pull-request builds use the debug key when no signing environment is set.
            signingConfig = signingConfigs.getByName(if (hasReleaseSigning) "release" else "debug")
        }
    }
}

flutter {
    source = "../.."
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

dependencies {
    implementation("com.google.mlkit:genai-prompt:1.0.0-beta4")
    ksp("com.google.mlkit:genai-schema-compiler:1.0.0-alpha1")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
}
