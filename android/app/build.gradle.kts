import java.util.Base64
import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

fun dartDefine(name: String): String? {
    val encodedDefines = project.findProperty("dart-defines")?.toString()
        ?: return null
    return encodedDefines
        .split(',')
        .mapNotNull { encoded ->
            runCatching {
                String(Base64.getDecoder().decode(encoded), Charsets.UTF_8)
            }.getOrNull()
        }
        .firstOrNull { it.startsWith("$name=") }
        ?.substringAfter('=')
        ?.takeIf { it.isNotBlank() }
}

val googleMapsApiKey = dartDefine("GOOGLE_MAPS_API_KEY")
    ?: System.getenv("GOOGLE_MAPS_API_KEY")?.takeIf { it.isNotBlank() }
    ?: ""
val revenueCatApiKeyAndroid = dartDefine("REVENUECAT_API_KEY_ANDROID")
    ?: System.getenv("REVENUECAT_API_KEY_ANDROID")?.takeIf { it.isNotBlank() }
    ?: ""
val admobAndroidAppId = dartDefine("ADMOB_ANDROID_APP_ID_PROD")
    ?: System.getenv("ADMOB_ANDROID_APP_ID_PROD")?.takeIf { it.isNotBlank() }
    ?: ""
val bannerAdUnitId = dartDefine("BANNER_AD_UNIT_ID")
    ?: System.getenv("ADMOB_ANDROID_BANNER_AD_UNIT_ID_PROD")?.takeIf { it.isNotBlank() }
    ?: ""
val interstitialAdUnitId = dartDefine("INTERSTITIAL_AD_UNIT_ID")
    ?: System.getenv("ADMOB_ANDROID_INTERSTITIAL_AD_UNIT_ID_PROD")?.takeIf { it.isNotBlank() }
    ?: ""

val releaseSigningProperties = Properties()
val releaseSigningPropertiesFile = rootProject.file("key.properties")
if (releaseSigningPropertiesFile.exists()) {
    releaseSigningPropertiesFile.inputStream().use(releaseSigningProperties::load)
}

fun releaseSigningValue(
    propertyName: String,
    environmentName: String,
    androidStudioPropertyName: String,
): String? =
    project.findProperty(androidStudioPropertyName)?.toString()?.takeIf { it.isNotBlank() }
        ?: System.getenv(environmentName)?.takeIf { it.isNotBlank() }
        ?: releaseSigningProperties.getProperty(propertyName)?.takeIf { it.isNotBlank() }

val releaseStoreFile =
    releaseSigningValue(
        "storeFile",
        "ANDROID_KEYSTORE_PATH",
        "android.injected.signing.store.file",
    )
val releaseStorePassword =
    releaseSigningValue(
        "storePassword",
        "ANDROID_KEYSTORE_PASSWORD",
        "android.injected.signing.store.password",
    )
val releaseKeyAlias =
    releaseSigningValue("keyAlias", "ANDROID_KEY_ALIAS", "android.injected.signing.key.alias")
val releaseKeyPassword =
    releaseSigningValue(
        "keyPassword",
        "ANDROID_KEY_PASSWORD",
        "android.injected.signing.key.password",
    )
val releaseSigningValues =
    mapOf(
        "storeFile / ANDROID_KEYSTORE_PATH" to releaseStoreFile,
        "storePassword / ANDROID_KEYSTORE_PASSWORD" to releaseStorePassword,
        "keyAlias / ANDROID_KEY_ALIAS" to releaseKeyAlias,
        "keyPassword / ANDROID_KEY_PASSWORD" to releaseKeyPassword,
    )
val hasCompleteReleaseSigning = releaseSigningValues.values.all { !it.isNullOrBlank() }
val releaseBuildRequested =
    gradle.startParameter.taskNames.any { it.contains("release", ignoreCase = true) }

val releaseRuntimeValues =
    mapOf(
        "GOOGLE_MAPS_API_KEY" to googleMapsApiKey,
        "REVENUECAT_API_KEY_ANDROID" to revenueCatApiKeyAndroid,
        "ADMOB_ANDROID_APP_ID_PROD" to admobAndroidAppId,
        "BANNER_AD_UNIT_ID" to bannerAdUnitId,
        "INTERSTITIAL_AD_UNIT_ID" to interstitialAdUnitId,
    )

if (releaseBuildRequested) {
    val missingRuntimeValues =
        releaseRuntimeValues
            .filterValues { it.isBlank() }
            .keys
            .joinToString()
    if (missingRuntimeValues.isNotEmpty()) {
        throw GradleException(
            "Android release runtime configuration is incomplete. Missing: " +
                "$missingRuntimeValues. Build with --dart-define-from-file=.dart_define.json " +
                "or provide the documented environment variables.",
        )
    }
}

if (releaseBuildRequested && !hasCompleteReleaseSigning) {
    val missingValues =
        releaseSigningValues
            .filterValues { it.isNullOrBlank() }
            .keys
            .joinToString()
    throw GradleException(
        "Android release signing is not configured. Missing: $missingValues. " +
            "Configure android/key.properties or provide the " +
            "ANDROID_KEYSTORE_* environment variables in CI.",
    )
}

if (
    releaseBuildRequested &&
    hasCompleteReleaseSigning &&
    !rootProject.file(requireNotNull(releaseStoreFile)).isFile
) {
    throw GradleException("Android release keystore does not exist: $releaseStoreFile")
}

android {
    namespace = "dev.asobo.worldnotes"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "dev.asobo.worldnotes"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24 // purchases_ui_flutter requires API 24+
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["googleMapsApiKey"] = googleMapsApiKey
        manifestPlaceholders["admobAppId"] =
            "ca-app-pub-3940256099942544~3347511713"
    }

    signingConfigs {
        if (hasCompleteReleaseSigning) {
            create("release") {
                storeFile = rootProject.file(requireNotNull(releaseStoreFile))
                storePassword = requireNotNull(releaseStorePassword)
                keyAlias = requireNotNull(releaseKeyAlias)
                keyPassword = requireNotNull(releaseKeyPassword)
            }
        }
    }

    buildTypes {
        release {
            if (hasCompleteReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            }
            manifestPlaceholders["admobAppId"] =
                admobAndroidAppId.takeIf { it.isNotBlank() }
                    ?: "ca-app-pub-3940256099942544~3347511713"
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
