import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Read android/key.properties if it exists. Without it, release builds
// fall back to debug signing (still works for local testing, but the
// resulting APK cannot be uploaded to Play Console).
//
// To set up release signing:
//
//   1. Generate a keystore (one-time):
//        keytool -genkey -v -keystore ~/donefirst-upload.jks \
//                -alias donefirst -keyalg RSA -keysize 2048 -validity 10000
//
//   2. Copy android/key.properties.example to android/key.properties and
//      fill in storeFile, storePassword, keyAlias, keyPassword.
//
//   3. The keystore file path is relative to android/ (the directory
//      containing this build.gradle.kts).
//
//   4. Add BOTH `android/key.properties` and `*.jks` to .gitignore
//      (already done — see project .gitignore).
val keystorePropertiesFile = rootProject.file("key.properties")
val hasKeystore = keystorePropertiesFile.exists()

android {
    namespace = "com.donefirst.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.donefirst.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // google_sign_in_android 7.x requires minSdk 21, but the
        // kid-side kiosk / lock-task / flutter_screentime features
        // require API 23 (Marshmallow). Bumping to 23 covers both.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasKeystore) {
            val props = Properties().apply {
                load(FileInputStream(keystorePropertiesFile))
            }
            create("release") {
                keyAlias = props.getProperty("keyAlias")
                keyPassword = props.getProperty("keyPassword")
                storeFile = file(props.getProperty("storeFile"))
                storePassword = props.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // If a keystore is configured, sign with the release config.
            // Otherwise fall back to the debug keystore so `flutter build`
            // still works locally (the resulting APK will not be
            // publishable, which is the correct failure mode).
            signingConfig = if (hasKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}
