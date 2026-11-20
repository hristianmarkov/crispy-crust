// Supplied by the release process; credentials are never written into the runner.
val uploadSigningVariables = listOf(
    "CRISPY_ANDROID_KEYSTORE", "CRISPY_ANDROID_KEY_ALIAS",
    "CRISPY_ANDROID_STORE_PASSWORD", "CRISPY_ANDROID_KEY_PASSWORD",
)
val uploadSigningReady = uploadSigningVariables.all { !System.getenv(it).isNullOrBlank() }

configure<com.android.build.api.dsl.ApplicationExtension> {
    if (uploadSigningReady) {
        signingConfigs.create("crispyUpload") {
            storeFile = file(System.getenv("CRISPY_ANDROID_KEYSTORE"))
            keyAlias = System.getenv("CRISPY_ANDROID_KEY_ALIAS")
            storePassword = System.getenv("CRISPY_ANDROID_STORE_PASSWORD")
            keyPassword = System.getenv("CRISPY_ANDROID_KEY_PASSWORD")
        }
    }
    buildTypes.getByName("release").signingConfig = signingConfigs.findByName("crispyUpload")
}

gradle.taskGraph.whenReady {
    if (!uploadSigningReady && allTasks.any {
            it.project == project && it.name.contains("Release")
        }) {
        throw GradleException("Release signing is missing. Set the CRISPY_ANDROID_* signing environment variables.")
    }
}
