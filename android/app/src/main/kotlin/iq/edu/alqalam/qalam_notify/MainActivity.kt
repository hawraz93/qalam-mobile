package iq.edu.alqalam.qalam_notify

import android.app.NotificationManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Small bridge the Dart side uses to find out why a push might not show on this phone
 * (notifications blocked, channel muted, battery optimisation) and to open the matching
 * system settings page. Everything here is Android framework only; no extra packages.
 */
// FlutterFragmentActivity: required by local_auth (fingerprint / face unlock)
class MainActivity : FlutterFragmentActivity() {
    private val channelId = "qalam_alerts"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "qalam/device").setMethodCallHandler { call, result ->
            when (call.method) {
                "status" -> result.success(status())
                "openNotificationSettings" -> result.success(openNotificationSettings(call.argument<Boolean>("channel") == true))
                "requestIgnoreBatteryOptimizations" -> result.success(requestIgnoreBatteryOptimizations())
                "openAutostartSettings" -> result.success(openAutostartSettings())
                "openSoundSettings" -> result.success(openSoundSettings())
                "updateFile" -> result.success(updateFile())
                "installApk" -> result.success(installApk(call.argument<String>("path") ?: ""))
                "installerSource" -> result.success(installerSource())
                else -> result.notImplemented()
            }
        }
    }

    private fun status(): Map<String, Any?> {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager

        var channelImportance: Int? = null
        var channelSound = true
        var channelSoundUri: String? = null
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = manager.getNotificationChannel(channelId)
            if (channel != null) {
                channelImportance = channel.importance
                channelSoundUri = channel.sound?.toString()
                // "Silent" in the phone settings lowers the importance; "Sound: none" clears the sound
                channelSound = channel.importance >= NotificationManager.IMPORTANCE_DEFAULT && channel.sound != null
            }
        }

        val batteryOptimized = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            !(getSystemService(Context.POWER_SERVICE) as PowerManager).isIgnoringBatteryOptimizations(packageName)
        } else {
            false
        }

        // 1 = INTERRUPTION_FILTER_ALL (Do Not Disturb off)
        val dndFilter = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) manager.currentInterruptionFilter else 1

        return mapOf(
            "manufacturer" to Build.MANUFACTURER,
            "model" to Build.MODEL,
            "androidVersion" to Build.VERSION.RELEASE,
            "notificationsEnabled" to manager.areNotificationsEnabled(),
            "channelImportance" to channelImportance,
            "channelSound" to channelSound,
            "channelSoundUri" to channelSoundUri,
            "batteryOptimized" to batteryOptimized,
            // 0 = silent, 1 = vibrate, 2 = normal
            "ringerMode" to audio.ringerMode,
            "notificationVolume" to audio.getStreamVolume(AudioManager.STREAM_NOTIFICATION),
            "notificationMaxVolume" to audio.getStreamMaxVolume(AudioManager.STREAM_NOTIFICATION),
            "dndFilter" to dndFilter,
        )
    }

    /** Where the update APK is downloaded to; an older download is removed first. */
    private fun updateFile(): String {
        val dir = File(cacheDir, "updates").apply { mkdirs() }
        dir.listFiles()?.forEach { it.delete() }
        return File(dir, "update.apk").absolutePath
    }

    /**
     * Opens the system installer for the downloaded APK. It installs over the current app
     * (same package and signing key), so data and sign-in stay. On Android 8+ the user first
     * allows this app to install updates; the Dart side retries when they come back.
     */
    private fun installApk(path: String): String {
        val file = File(path)
        if (!file.exists()) return "failed"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !packageManager.canRequestPackageInstalls()) {
            startFirst(listOf(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName"))))
            return "permission"
        }
        val uri = FileProvider.getUriForFile(this, "$packageName.updates", file)
        val intent = Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, "application/vnd.android.package-archive")
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        return if (startFirst(listOf(intent))) "started" else "failed"
    }

    /** "com.android.vending" once the app comes from Google Play; null for a downloaded APK. */
    private fun installerSource(): String? = try {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            packageManager.getInstallSourceInfo(packageName).installingPackageName
        } else {
            @Suppress("DEPRECATION")
            packageManager.getInstallerPackageName(packageName)
        }
    } catch (_: Exception) {
        null
    }

    private fun openSoundSettings(): Boolean = startFirst(listOf(Intent(Settings.ACTION_SOUND_SETTINGS)))

    /** The app's notification page, or the alerts channel page when only the sound is the problem. */
    private fun openNotificationSettings(channel: Boolean): Boolean {
        val intents = mutableListOf<Intent>()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            if (channel) {
                intents += Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS)
                    .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                    .putExtra(Settings.EXTRA_CHANNEL_ID, channelId)
            }
            intents += Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
        }
        intents += Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))
        return startFirst(intents)
    }

    /** System dialog "Allow app to always run in background?", falling back to the list page. */
    private fun requestIgnoreBatteryOptimizations(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return false
        return startFirst(
            listOf(
                Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:$packageName")),
                Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS),
            )
        )
    }

    /**
     * Xiaomi, Huawei, Oppo, Vivo, OnePlus and Samsung stop background apps unless the user
     * allows "autostart" / background activity in a vendor-specific page. Opens the first one that exists.
     */
    private fun openAutostartSettings(): Boolean {
        val pages = listOf(
            // Xiaomi / Redmi / POCO
            "com.miui.securitycenter" to "com.miui.permcenter.autostart.AutoStartManagementActivity",
            // Huawei / Honor
            "com.huawei.systemmanager" to "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity",
            "com.huawei.systemmanager" to "com.huawei.systemmanager.appcontrol.activity.StartupAppControlActivity",
            "com.huawei.systemmanager" to "com.huawei.systemmanager.optimize.process.ProtectActivity",
            // Oppo / Realme
            "com.coloros.safecenter" to "com.coloros.safecenter.permission.startup.StartupAppListActivity",
            "com.coloros.safecenter" to "com.coloros.safecenter.startupapp.StartupAppListActivity",
            "com.oppo.safe" to "com.oppo.safe.permission.startup.StartupAppListActivity",
            // Vivo / iQOO
            "com.vivo.permissionmanager" to "com.vivo.permissionmanager.activity.BgStartUpManagerActivity",
            "com.iqoo.secure" to "com.iqoo.secure.ui.phoneoptimize.BgStartUpManager",
            "com.iqoo.secure" to "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity",
            // OnePlus
            "com.oneplus.security" to "com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity",
            // Samsung (battery -> background usage limits)
            "com.samsung.android.lool" to "com.samsung.android.sm.ui.battery.BatteryActivity",
            "com.samsung.android.sm_cn" to "com.samsung.android.sm.ui.battery.BatteryActivity",
            // Asus
            "com.asus.mobilemanager" to "com.asus.mobilemanager.powersaver.PowerSaverSettings",
            "com.asus.mobilemanager" to "com.asus.mobilemanager.autostart.AutoStartActivity",
            // Nokia / HMD
            "com.evenwell.powersaving.g3" to "com.evenwell.powersaving.g3.exception.PowerSaverExceptionActivity",
        )

        val intents = pages.map { (pkg, cls) -> Intent().setComponent(ComponentName(pkg, cls)) } +
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))

        return startFirst(intents)
    }

    private fun startFirst(intents: List<Intent>): Boolean {
        for (intent in intents) {
            try {
                startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                return true
            } catch (_: Exception) {
                // Page does not exist on this phone (or is not exported); try the next one
            }
        }
        return false
    }
}
