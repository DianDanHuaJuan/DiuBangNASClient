import java.io.FileInputStream
import java.util.Properties
import com.android.build.gradle.internal.api.ApkVariantOutputImpl

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.diubang.nasclient"
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
        applicationId = "com.diubang.nasclient"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = keystoreProperties["storeFile"]?.let { file(it) }
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

@Suppress("DEPRECATION")
android.applicationVariants.configureEach {
    if (buildType.name == "release") {
        outputs.configureEach {
            (this as ApkVariantOutputImpl).outputFileName =
                "diubang_nasclient_${versionName}.apk"
        }
    }
}

afterEvaluate {
    tasks.named("assembleRelease").configure {
        doLast {
            val version = android.defaultConfig.versionName ?: "1.0.0"
            val fileName = "diubang_nasclient_${version}.apk"
            val releaseApk = layout.buildDirectory.file("outputs/apk/release/$fileName").get().asFile
            val flutterApkDir =
                rootProject.projectDir.parentFile.resolve("build/app/outputs/flutter-apk")
            if (releaseApk.exists()) {
                flutterApkDir.mkdirs()
                releaseApk.copyTo(flutterApkDir.resolve(fileName), overwrite = true)
            }
        }
    }
}

configurations.all {
    resolutionStrategy {
        // photo_manager pulls Glide 5.0.0 which has split artifacts not yet
        // published to Maven Central. Force 4.x until the ecosystem catches up.
        force("com.github.bumptech.glide:glide:4.16.0")
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.work:work-runtime-ktx:2.10.1")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    testImplementation("junit:junit:4.13.2")
}
