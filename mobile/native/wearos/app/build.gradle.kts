import com.android.build.api.dsl.ApplicationExtension
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins { id("com.android.application"); id("org.jetbrains.kotlin.android") }
extensions.configure<ApplicationExtension>("android") {
    namespace = "app.crispycrust.wear"
    compileSdk = 37
    defaultConfig { applicationId = "app.crispycrust.mobile"; minSdk = 26; targetSdk = 36; versionCode = 1; versionName = "0.1.0" }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
}
dependencies { implementation("com.google.android.gms:play-services-wearable:19.0.0") }

kotlin {
    compilerOptions { jvmTarget.set(JvmTarget.JVM_17) }
}
