plugins {
    id("com.android.application")
    id("kotlin-android")
    // Le plugin Gradle de Flutter doit venir après ceux d'Android et de Kotlin.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "org.chadracklonde.andika"
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
        applicationId = "org.chadracklonde.andika"
        // Android 8.0 (API 26) minimum, voir cahier des charges section 5.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // arm64-v8a pour les téléphones, x86_64 pour l'émulateur.
        ndk {
            abiFilters += listOf("arm64-v8a", "x86_64")
        }
    }

    buildTypes {
        release {
            // À remplacer par une vraie clé de signature avant publication (lot L11).
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
