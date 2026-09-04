import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.local.carpe.telecom"
    compileSdk = 35

    defaultConfig {
        minSdk = 21
    }

    // This plugin is compiled alongside the app. Keep Java and Kotlin on the
    // same target so the Android Gradle Plugin does not reject the build.
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}
