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
}
