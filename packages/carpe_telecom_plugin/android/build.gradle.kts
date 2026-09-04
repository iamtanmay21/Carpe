plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.local.carpe.telecom"
    compileSdk = 35

    // This plugin is compiled alongside the app. Keep Java and Kotlin on the
    // same target so the Android Gradle Plugin does not reject the build.
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        minSdk = 21
    }
}
