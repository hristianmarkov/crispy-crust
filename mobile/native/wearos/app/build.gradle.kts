plugins { id("com.android.application"); id("org.jetbrains.kotlin.android") }
android {
    namespace = "app.crispycrust.wear"
    compileSdk = 36
    defaultConfig { applicationId = "app.crispycrust.crispy_crust"; minSdk = 26; targetSdk = 36; versionCode = 1; versionName = "0.1.0" }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
    kotlinOptions { jvmTarget = "17" }
}
dependencies { implementation("com.google.android.gms:play-services-wearable:19.0.0") }
