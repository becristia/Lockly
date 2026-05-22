import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

fun releaseSigningValue(name: String, propertyName: String): String? {
    return (findProperty(name) as String?)
        ?: System.getenv(name)
        ?: keystoreProperties.getProperty(propertyName)
}

fun requireReleaseSigningValue(name: String, propertyName: String): String {
    return releaseSigningValue(name, propertyName)
        ?: throw GradleException("Missing release signing value: $name")
}

val validateReleaseSigning = tasks.register("validateReleaseSigning") {
    doLast {
        val storeFilePath = requireReleaseSigningValue("LOCKLY_RELEASE_STORE_FILE", "storeFile")
        requireReleaseSigningValue("LOCKLY_RELEASE_STORE_PASSWORD", "storePassword")
        requireReleaseSigningValue("LOCKLY_RELEASE_KEY_ALIAS", "keyAlias")
        requireReleaseSigningValue("LOCKLY_RELEASE_KEY_PASSWORD", "keyPassword")
        if (!file(storeFilePath).isFile) {
            throw GradleException("Release signing keystore does not exist: $storeFilePath")
        }
    }
}

android {
    namespace = "com.lockly.securebox"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.lockly.securebox"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            releaseSigningValue("LOCKLY_RELEASE_STORE_FILE", "storeFile")?.let {
                storeFile = file(it)
            }
            storePassword = releaseSigningValue("LOCKLY_RELEASE_STORE_PASSWORD", "storePassword")
            keyAlias = releaseSigningValue("LOCKLY_RELEASE_KEY_ALIAS", "keyAlias")
            keyPassword = releaseSigningValue("LOCKLY_RELEASE_KEY_PASSWORD", "keyPassword")
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.appcompat:appcompat:1.7.1")
}

tasks.matching {
    it.name == "assembleRelease" ||
        it.name == "bundleRelease" ||
        it.name == "packageRelease"
}.configureEach {
    dependsOn(validateReleaseSigning)
}
