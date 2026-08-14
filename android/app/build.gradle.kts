import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Upload-key credentials, kept out of the repository.
//
// `android/key.properties` is gitignored along with the keystore itself. When
// it is absent — a fresh clone, or CI without secrets — the release build falls
// back to debug signing so `flutter run --release` still works. That fallback
// produces a binary Play will reject, which is correct: an unsigned-for-upload
// build should fail at upload time, not silently masquerade as shippable.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasUploadKey = keystorePropertiesFile.exists()
if (hasUploadKey) {
    keystorePropertiesFile.inputStream().use(keystoreProperties::load)
}

android {
    namespace = "app.circa.circa"
    compileSdk = flutter.compileSdkVersion
    // Pinned rather than tracking `flutter.ndkVersion`.
    //
    // Flutter's tooling warns that flutter_timezone, purchases_flutter,
    // sqflite_android and integration_test "require" 28.2.13676358. They do not
    // require it in any real sense: each simply declares
    // `ndkVersion = flutter.ndkVersion`, so the warning is the SDK comparing
    // its own default against ours. None of them ship native C/C++ —
    // sqflite_android binds Android's own SQLite and the rest are Kotlin/Java —
    // so no NDK toolchain is actually invoked for this project.
    //
    // Taking the default would pull ~3 GB for a patch release functionally
    // identical to one already installed. If a future dependency does add
    // native code, raise this to the highest version the plugins ask for
    // (NDKs are backward compatible) rather than removing the pin.
    ndkVersion = "28.1.13356709"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "app.circa.circa"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasUploadKey) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasUploadKey) {
                signingConfigs.getByName("release")
            } else {
                logger.warn(
                    "Circa: android/key.properties not found — signing the " +
                        "release build with debug keys. Play will reject this AAB."
                )
                signingConfigs.getByName("debug")
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
