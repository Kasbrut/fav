import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android plugin.
    id("dev.flutter.flutter-gradle-plugin")
}

// Local signing file is ignored by Git; CI supplies the same values as secrets.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}
fun signingValue(name: String, env: String): String? =
    System.getenv(env)?.takeIf { it.isNotBlank() } ?: keystoreProperties.getProperty(name)
val releaseStoreFile = signingValue("storeFile", "FAV_KEYSTORE_PATH")
val releaseStorePassword = signingValue("storePassword", "FAV_STORE_PASSWORD")
val releaseKeyAlias = signingValue("keyAlias", "FAV_KEY_ALIAS")
val releaseKeyPassword = signingValue("keyPassword", "FAV_KEY_PASSWORD")
val hasReleaseSigning = listOf(releaseStoreFile, releaseStorePassword, releaseKeyAlias, releaseKeyPassword)
    .all { !it.isNullOrBlank() }
val allowDebugSigning = System.getenv("FAV_ALLOW_DEBUG_SIGNING") == "true"

// Never silently produce a debug-signed public release.
if (gradle.startParameter.taskNames.any { it.contains("release", ignoreCase = true) }) {
    check(hasReleaseSigning || allowDebugSigning) {
        "Release signing is missing. Configure android/key.properties (see docs/building.md). " +
            "For local testing only, set FAV_ALLOW_DEBUG_SIGNING=true."
    }
}

android {
    namespace = "com.kasbrut.fav"
    // Required by flutter_secure_storage 11.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.kasbrut.fav"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(releaseStoreFile!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = when {
                hasReleaseSigning -> signingConfigs.getByName("release")
                allowDebugSigning -> signingConfigs.getByName("debug")
                else -> null
            }
        }
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
