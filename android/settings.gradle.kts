// 本机 HTTP 代理一键开关（android/gradle.properties: localProxyEnabled）
run {
    val props = java.util.Properties()
    val propsFile = file("gradle.properties")
    if (propsFile.exists()) {
        propsFile.inputStream().use { props.load(it) }
    }
    val enabled = props.getProperty("localProxyEnabled", "false").equals("true", ignoreCase = true)
    if (enabled) {
        val host = props.getProperty("localProxyHost", "127.0.0.1").trim()
        val port = props.getProperty("localProxyPort", "7890").trim()
        System.setProperty("http.proxyHost", host)
        System.setProperty("http.proxyPort", port)
        System.setProperty("https.proxyHost", host)
        System.setProperty("https.proxyPort", port)
        println("[localProxy] enabled $host:$port")
    }
}

pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}

include(":app")
