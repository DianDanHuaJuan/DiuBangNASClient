package com.diubang.nasclient

import android.content.ActivityNotFoundException
import android.app.AlarmManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import androidx.work.WorkManager
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.util.Calendar

class BackupSchedulerChannel(private val appContext: Context) {
    private val logTag = "BackupSchedulerChannel"
    private val schedulerManager = BackupSchedulerManager(appContext.applicationContext)

    fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "schedulePlan" -> {
                    val arguments = call.arguments as? Map<*, *>
                    if (arguments == null) {
                        result.error("INVALID_ARGUMENT", "schedulePlan requires a map payload", null)
                        return
                    }
                    val config = BackupPlanConfig.fromMap(arguments)
                    if (config == null) {
                        result.error("INVALID_ARGUMENT", "Unable to parse backup plan payload", null)
                        return
                    }
                    result.success(schedulerManager.schedulePlan(config).toMap())
                }

                "cancelPlan" -> {
                    val arguments = call.arguments as? Map<*, *>
                    val planId = arguments?.stringValue("planId")
                    if (planId.isNullOrBlank()) {
                        result.error("INVALID_ARGUMENT", "cancelPlan requires planId", null)
                        return
                    }
                    result.success(schedulerManager.cancelPlan(planId).toMap())
                }

                "stopCurrentRun" -> {
                    val arguments = call.arguments as? Map<*, *>
                    val planId = arguments?.stringValue("planId")
                    if (planId.isNullOrBlank()) {
                        result.error("INVALID_ARGUMENT", "stopCurrentRun requires planId", null)
                        return
                    }
                    result.success(schedulerManager.stopCurrentRun(planId).toMap())
                }

                "getWorkerStateSnapshot" -> {
                    result.success(schedulerManager.getWorkerStateSnapshot())
                }

                "getMediaAccessScope" -> {
                    val arguments = call.arguments as? Map<*, *>
                    val includeImages = arguments?.booleanValue("includeImages") ?: true
                    val includeVideos = arguments?.booleanValue("includeVideos") ?: true
                    result.success(
                        BackupMediaAccessEvaluator.resolve(
                            appContext,
                            includeImages = includeImages,
                            includeVideos = includeVideos,
                        ).toMap(),
                    )
                }

                "getScheduledBackupNotificationState" -> {
                    result.success(
                        resolveScheduledBackupNotificationState(appContext.applicationContext).toMap(),
                    )
                }

                "openScheduledBackupNotificationSettings" -> {
                    openScheduledBackupNotificationSettings()
                    result.success(null)
                }

                "openBatteryOptimizationSettings" -> {
                    openBatteryOptimizationSettings()
                    result.success(null)
                }

                "openAutoStartSettings" -> {
                    openAutoStartSettings()
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        } catch (error: Exception) {
            result.error("BACKUP_SCHEDULER_ERROR", error.message, null)
        }
    }

    private fun openBatteryOptimizationSettings() {
        val applicationContext = appContext.applicationContext
        val packageName = applicationContext.packageName
        val packageUri = Uri.parse("package:$packageName")
        val intents = mutableListOf<Intent>()

        intents += buildManufacturerBatteryIntents(packageName)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val powerManager =
                applicationContext.getSystemService(Context.POWER_SERVICE) as? PowerManager
            val isIgnoringOptimizations =
                powerManager?.isIgnoringBatteryOptimizations(packageName) == true

            if (!isIgnoringOptimizations) {
                intents += Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                    data = packageUri
                }
            }

            intents += Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
        }

        intents += Intent(Intent.ACTION_POWER_USAGE_SUMMARY)
        intents += Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = packageUri
        }

        val packageManager = applicationContext.packageManager
        val launchErrors = mutableListOf<String>()

        for (intent in intents) {
            if (!canLaunchIntent(packageManager, intent)) {
                continue
            }

            val targetIntent = Intent(intent).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            try {
                applicationContext.startActivity(targetIntent)
                Log.i(logTag, "Opened battery settings with intent: ${describeIntent(targetIntent)}")
                return
            } catch (error: ActivityNotFoundException) {
                val message =
                    "Battery settings activity missing: ${describeIntent(targetIntent)}"
                Log.w(logTag, message, error)
                launchErrors += message
            } catch (error: SecurityException) {
                val message =
                    "Battery settings activity not accessible: ${describeIntent(targetIntent)}"
                Log.w(logTag, message, error)
                launchErrors += message
            } catch (error: IllegalArgumentException) {
                val message =
                    "Battery settings intent invalid: ${describeIntent(targetIntent)}"
                Log.w(logTag, message, error)
                launchErrors += message
            }
        }

        if (launchErrors.isNotEmpty()) {
            throw IllegalStateException(
                "未找到可用的电池优化设置页面，已尝试: ${launchErrors.joinToString(" | ")}",
            )
        }
        throw IllegalStateException("系统中未找到可用的电池优化设置页面")
    }

    private fun openAutoStartSettings() {
        val applicationContext = appContext.applicationContext
        val intents = mutableListOf<Intent>()

        intents += buildManufacturerAutoStartIntents(applicationContext.packageName)
        intents += buildGenericAutoStartFallbackIntents()

        val launchErrors = mutableListOf<String>()

        for (intent in intents) {
            try {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                applicationContext.startActivity(intent)
                Log.i(logTag, "Opened auto-start settings with intent: ${describeIntent(intent)}")
                return
            } catch (error: ActivityNotFoundException) {
                launchErrors += "Auto-start page missing: ${describeIntent(intent)}"
            } catch (error: SecurityException) {
                launchErrors += "Auto-start page inaccessible: ${describeIntent(intent)}"
            }
        }

        if (launchErrors.isNotEmpty()) {
            val message = "未找到可用的自启动设置页面，已尝试: ${launchErrors.joinToString(" | ")}"
            Log.w(logTag, message)
            throw IllegalStateException(message)
        }
        throw IllegalStateException("系统中未找到可用的自启动设置页面")
    }

    private fun buildManufacturerAutoStartIntents(packageName: String): List<Intent> {
        val manufacturer = Build.MANUFACTURER.lowercase()
        val brand = Build.BRAND.lowercase()
        val intents = mutableListOf<Intent>()

        fun componentIntent(
            packageId: String,
            className: String,
            extras: Map<String, String> = emptyMap(),
        ): Intent {
            return Intent().apply {
                component = ComponentName(packageId, className)
                extras.forEach { (key, value) -> putExtra(key, value) }
            }
        }

        fun actionIntent(
            action: String,
            packageId: String? = null,
            extras: Map<String, String> = emptyMap(),
        ): Intent {
            return Intent(action).apply {
                packageId?.let { setPackage(it) }
                extras.forEach { (key, value) -> putExtra(key, value) }
            }
        }

        when {
            manufacturer.contains("xiaomi") || brand.contains("xiaomi") ||
                brand.contains("redmi") || brand.contains("poco") -> {
                intents += componentIntent(
                    "com.miui.securitycenter",
                    "com.miui.permcenter.autostart.AutoStartManagementActivity",
                )
            }

            manufacturer.contains("oppo") || manufacturer.contains("realme") ||
                manufacturer.contains("oneplus") || brand.contains("oppo") ||
                brand.contains("realme") || brand.contains("oneplus") -> {
                if (manufacturer.contains("realme") || brand.contains("realme")) {
                    intents += componentIntent(
                        "com.realme.securitycenter",
                        "com.realme.securitycenter.startup.manager.StartupAppListActivity",
                        mapOf(
                            "packageName" to packageName,
                            "package_name" to packageName,
                        ),
                    )
                }
                if (manufacturer.contains("oneplus") || brand.contains("oneplus")) {
                    intents += componentIntent(
                        "com.oneplus.security",
                        "com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity",
                        mapOf(
                            "packageName" to packageName,
                            "package_name" to packageName,
                        ),
                    )
                }
                intents += componentIntent(
                    "com.oplus.battery",
                    "com.oplus.startupapp.view.StartupAppListActivity",
                )
            }

            manufacturer.contains("vivo") || brand.contains("vivo") ||
                brand.contains("iqoo") || manufacturer.contains("iqoo") -> {
                intents += componentIntent(
                    "com.iqoo.secure",
                    "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity",
                    mapOf("packageName" to packageName),
                )
            }

            manufacturer.contains("huawei") || brand.contains("huawei") ||
                manufacturer.contains("honor") || brand.contains("honor") -> {
                intents += componentIntent(
                    "com.huawei.systemmanager",
                    "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity",
                )
                intents += componentIntent(
                    "com.huawei.systemmanager",
                    "com.huawei.systemmanager.optimize.process.ProtectActivity",
                )
            }
        }

        return intents
    }

    private fun buildGenericAutoStartFallbackIntents(): List<Intent> {
        return listOf(
            Intent(Settings.ACTION_APPLICATION_SETTINGS),
            Intent(Settings.ACTION_MANAGE_APPLICATIONS_SETTINGS),
            Intent(Settings.ACTION_SETTINGS),
        )
    }

    private fun openScheduledBackupNotificationSettings() {
        val applicationContext = appContext.applicationContext
        val packageName = applicationContext.packageName
        val packageUri = Uri.parse("package:$packageName")
        ensureScheduledBackupNotificationChannel(applicationContext)
        val intents = mutableListOf<Intent>()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            intents += Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS).apply {
                putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                putExtra(Settings.EXTRA_CHANNEL_ID, SCHEDULED_BACKUP_NOTIFICATION_CHANNEL_ID)
            }
        }

        intents += Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
            putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
            putExtra("app_package", packageName)
            putExtra("app_uid", applicationContext.applicationInfo.uid)
        }
        intents += Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = packageUri
        }

        val packageManager = applicationContext.packageManager
        val launchErrors = mutableListOf<String>()

        for (intent in intents) {
            if (!canLaunchIntent(packageManager, intent)) {
                continue
            }

            val targetIntent = Intent(intent).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            try {
                applicationContext.startActivity(targetIntent)
                Log.i(logTag, "Opened notification settings with intent: ${describeIntent(targetIntent)}")
                return
            } catch (error: ActivityNotFoundException) {
                val message =
                    "Notification settings activity missing: ${describeIntent(targetIntent)}"
                Log.w(logTag, message, error)
                launchErrors += message
            } catch (error: SecurityException) {
                val message =
                    "Notification settings activity not accessible: ${describeIntent(targetIntent)}"
                Log.w(logTag, message, error)
                launchErrors += message
            } catch (error: IllegalArgumentException) {
                val message =
                    "Notification settings intent invalid: ${describeIntent(targetIntent)}"
                Log.w(logTag, message, error)
                launchErrors += message
            }
        }

        if (launchErrors.isNotEmpty()) {
            throw IllegalStateException(
                "未找到可用的通知设置页面，已尝试: ${launchErrors.joinToString(" | ")}",
            )
        }
        throw IllegalStateException("系统中未找到可用的通知设置页面")
    }

    private fun buildManufacturerBatteryIntents(packageName: String): List<Intent> {
        val manufacturer = Build.MANUFACTURER.lowercase()
        val brand = Build.BRAND.lowercase()
        val packageUri = Uri.parse("package:$packageName")
        val intents = mutableListOf<Intent>()

        fun componentIntent(
            packageId: String,
            className: String,
            extras: Map<String, String> = emptyMap(),
        ): Intent {
            return Intent().apply {
                component = ComponentName(packageId, className)
                extras.forEach { (key, value) -> putExtra(key, value) }
            }
        }

        when {
            manufacturer.contains("xiaomi") || brand.contains("xiaomi") ||
                brand.contains("redmi") || brand.contains("poco") -> {
                intents += componentIntent(
                    "com.miui.powerkeeper",
                    "com.miui.powerkeeper.ui.HiddenAppsConfigActivity",
                    mapOf(
                        "package_name" to packageName,
                        "packageName" to packageName,
                    ),
                )
                intents += componentIntent(
                    "com.miui.powerkeeper",
                    "com.miui.powerkeeper.ui.HiddenAppsContainerManagementActivity",
                )
                intents += componentIntent(
                    "com.miui.securitycenter",
                    "com.miui.powercenter.PowerSettings",
                )
            }

            manufacturer.contains("oppo") || manufacturer.contains("realme") ||
                manufacturer.contains("oneplus") || brand.contains("oppo") ||
                brand.contains("realme") || brand.contains("oneplus") -> {
                intents += componentIntent(
                    "com.coloros.oppoguardelf",
                    "com.coloros.oppoguardelf.PowerUsageModelActivity",
                    mapOf(
                        "packageName" to packageName,
                        "package_name" to packageName,
                        "pkg_name" to packageName,
                    ),
                )
                intents += componentIntent(
                    "com.coloros.oppoguardelf",
                    "com.coloros.oppoguardelf.activity.PowerUsageTopActivity",
                )
                intents += componentIntent(
                    "com.oppo.oppoguardelf",
                    "com.oppo.oppoguardelf.PowerUsageModelActivity",
                    mapOf(
                        "packageName" to packageName,
                        "package_name" to packageName,
                        "pkg_name" to packageName,
                    ),
                )
                intents += componentIntent(
                    "com.coloros.powermanager",
                    "com.coloros.powermanager.fuelgaue.PowerConsumptionActivity",
                )
                intents += componentIntent(
                    "com.coloros.powermanager",
                    "com.coloros.powermanager.fuelgauge.PowerConsumptionActivity",
                )
                intents += componentIntent(
                    "com.coloros.phonemanager",
                    "com.coloros.phonemanager.activity.PowerConsumptionActivity",
                )
            }

            manufacturer.contains("vivo") || brand.contains("vivo") ||
                brand.contains("iqoo") || manufacturer.contains("iqoo") -> {
                intents += componentIntent(
                    "com.iqoo.powersave",
                    "com.iqoo.powersave.PowerSaveMainActivity",
                    mapOf("packagename" to packageName),
                )
                intents += componentIntent(
                    "com.iqoo.secure",
                    "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity",
                    mapOf("packageName" to packageName),
                )
            }

            manufacturer.contains("huawei") || brand.contains("huawei") ||
                manufacturer.contains("honor") || brand.contains("honor") -> {
                intents += componentIntent(
                    "com.huawei.systemmanager",
                    "com.huawei.systemmanager.optimize.process.ProtectActivity",
                )
                intents += componentIntent(
                    "com.huawei.systemmanager",
                    "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity",
                )
            }

            manufacturer.contains("samsung") || brand.contains("samsung") -> {
                intents += componentIntent(
                    "com.samsung.android.sm",
                    "com.samsung.android.sm.ui.battery.BatteryActivity",
                )
                intents += componentIntent(
                    "com.samsung.android.lool",
                    "com.samsung.android.sm.ui.battery.BatteryActivity",
                )
            }
        }

        intents += Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = packageUri
        }
        return intents
    }

    private fun canLaunchIntent(packageManager: PackageManager, intent: Intent): Boolean {
        val component = intent.component
        if (component != null) {
            return try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    packageManager.getActivityInfo(
                        component,
                        PackageManager.ComponentInfoFlags.of(0),
                    )
                } else {
                    @Suppress("DEPRECATION")
                    packageManager.getActivityInfo(component, 0)
                }
                true
            } catch (_: PackageManager.NameNotFoundException) {
                false
            }
        }
        return intent.resolveActivity(packageManager) != null
    }

    private fun describeIntent(intent: Intent): String {
        return buildString {
            append(intent.action ?: "no-action")
            intent.component?.let { component ->
                append(" ")
                append(component.flattenToShortString())
            }
            intent.data?.let { data ->
                append(" ")
                append(data)
            }
        }
    }
}

data class BackupPlanScheduleResult(
    val status: String,
    val nextRunAtMillis: Long? = null,
    val errorMessage: String? = null,
) {
    fun toMap(): Map<String, Any?> {
        return mapOf(
            "status" to status,
            "nextRunAtMillis" to nextRunAtMillis,
            "errorMessage" to errorMessage,
        )
    }

    companion object {
        fun scheduled(nextRunAtMillis: Long?): BackupPlanScheduleResult {
            return BackupPlanScheduleResult(
                status = "scheduled",
                nextRunAtMillis = nextRunAtMillis,
            )
        }

        fun unscheduled(): BackupPlanScheduleResult {
            return BackupPlanScheduleResult(status = "unscheduled")
        }

        fun failed(message: String): BackupPlanScheduleResult {
            return BackupPlanScheduleResult(
                status = "failed",
                errorMessage = message,
            )
        }
    }
}

data class BackupPlanConfig(
    val planId: String,
    val planName: String,
    val serverId: String,
    val serverUrl: String,
    val rootId: String,
    val accessToken: String,
    val refreshToken: String,
    val deviceId: String,
    val deviceName: String,
    val includeImages: Boolean,
    val includeVideos: Boolean,
    val scheduleType: String,
    val hour: Int,
    val minute: Int,
    val weekday: Int?,
    val dayOfMonth: Int?,
    val onceAtMillis: Long?,
    val requiresWifi: Boolean,
    val requiresCharging: Boolean,
    val rootCaPem: String,
    val leafSha256: String?,
) {
    fun isRecurring(): Boolean = scheduleType != "once"

    fun toJson(): String {
        return JSONObject(
            mapOf(
                "planId" to planId,
                "planName" to planName,
                "serverId" to serverId,
                "serverUrl" to serverUrl,
                "rootId" to rootId,
                "accessToken" to accessToken,
                "refreshToken" to refreshToken,
                "deviceId" to deviceId,
                "deviceName" to deviceName,
                "includeImages" to includeImages,
                "includeVideos" to includeVideos,
                "scheduleType" to scheduleType,
                "hour" to hour,
                "minute" to minute,
                "weekday" to weekday,
                "dayOfMonth" to dayOfMonth,
                "onceAtMillis" to onceAtMillis,
                "requiresWifi" to requiresWifi,
                "requiresCharging" to requiresCharging,
                "rootCaPem" to rootCaPem,
                "leafSha256" to leafSha256,
            ),
        ).toString()
    }

    companion object {
        fun fromMap(map: Map<*, *>): BackupPlanConfig? {
            val planId = map.stringValue("planId") ?: return null
            val serverUrl = map.stringValue("serverUrl") ?: return null
            val rootId = map.stringValue("rootId") ?: return null
            val accessToken = map.stringValue("accessToken") ?: return null
            val refreshToken = map.stringValue("refreshToken") ?: return null
            val deviceId = map.stringValue("deviceId") ?: return null
            val rootCaPem = map.stringValue("rootCaPem") ?: return null
            val scheduleType = map.stringValue("scheduleType") ?: return null
            val hour = map.intValue("hour") ?: return null
            val minute = map.intValue("minute") ?: return null

            return BackupPlanConfig(
                planId = planId,
                planName = map.stringValue("planName") ?: planId,
                serverId = map.stringValue("serverId") ?: "",
                serverUrl = serverUrl,
                rootId = rootId,
                accessToken = accessToken,
                refreshToken = refreshToken,
                deviceId = deviceId,
                deviceName = map.stringValue("deviceName") ?: "铥棒文件",
                includeImages = map.booleanValue("includeImages"),
                includeVideos = map.booleanValue("includeVideos"),
                scheduleType = scheduleType,
                hour = hour,
                minute = minute,
                weekday = map.intValue("weekday"),
                dayOfMonth = map.intValue("dayOfMonth"),
                onceAtMillis = map.longValue("onceAtMillis"),
                requiresWifi = map.booleanValue("requiresWifi"),
                requiresCharging = map.booleanValue("requiresCharging"),
                rootCaPem = rootCaPem,
                leafSha256 = map.stringValue("leafSha256"),
            )
        }

        fun fromJson(raw: String): BackupPlanConfig? {
            return try {
                val json = JSONObject(raw)
                fromMap(
                    mapOf(
                        "planId" to json.optString("planId"),
                        "planName" to json.optString("planName"),
                        "serverId" to json.optString("serverId"),
                        "serverUrl" to json.optString("serverUrl"),
                        "rootId" to json.optString("rootId"),
                        "accessToken" to json.optString("accessToken"),
                        "refreshToken" to json.optString("refreshToken"),
                        "deviceId" to json.optString("deviceId"),
                        "deviceName" to json.optString("deviceName"),
                        "includeImages" to json.optBoolean("includeImages"),
                        "includeVideos" to json.optBoolean("includeVideos"),
                        "scheduleType" to json.optString("scheduleType"),
                        "hour" to json.optInt("hour"),
                        "minute" to json.optInt("minute"),
                        "weekday" to json.optNullableInt("weekday"),
                        "dayOfMonth" to json.optNullableInt("dayOfMonth"),
                        "onceAtMillis" to json.optNullableLong("onceAtMillis"),
                        "requiresWifi" to json.optBoolean("requiresWifi"),
                        "requiresCharging" to json.optBoolean("requiresCharging"),
                        "rootCaPem" to json.optString("rootCaPem"),
                        "leafSha256" to json.optString("leafSha256").ifBlank { null },
                    ),
                )
            } catch (_: Exception) {
                null
            }
        }
    }
}

class BackupPlanConfigStore(context: Context) {
    private val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun save(config: BackupPlanConfig) {
        prefs.edit()
            .clear()
            .putString(key(config.planId), config.toJson())
            .apply()
    }

    fun load(planId: String): BackupPlanConfig? {
        val raw = prefs.getString(key(planId), null) ?: return null
        return BackupPlanConfig.fromJson(raw)
    }

    fun remove(planId: String) {
        prefs.edit().remove(key(planId)).apply()
    }

    fun loadAll(): List<BackupPlanConfig> {
        return prefs.all
            .filterKeys { key -> key.startsWith("backup_plan_") }
            .values
            .mapNotNull { raw ->
                (raw as? String)?.let(BackupPlanConfig::fromJson)
            }
            .sortedBy { config -> config.planId }
    }

    private fun key(planId: String): String = "backup_plan_${sanitizePlanId(planId)}"

    companion object {
        private const val PREFS_NAME = "backup_scheduler_configs"
    }
}

class BackupPlanScheduleStateStore(context: Context) {
    private val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun save(planId: String, nextRunAtMillis: Long) {
        prefs.edit()
            .clear()
            .putLong(key(planId), nextRunAtMillis)
            .apply()
    }

    fun load(planId: String): Long? {
        return if (prefs.contains(key(planId))) {
            prefs.getLong(key(planId), 0L)
        } else {
            null
        }
    }

    fun remove(planId: String) {
        prefs.edit().remove(key(planId)).apply()
    }

    private fun key(planId: String): String = "backup_state_${sanitizePlanId(planId)}"

    companion object {
        private const val PREFS_NAME = "backup_scheduler_state"
    }
}

class BackupSchedulerManager(
    private val context: Context,
    private val configStore: BackupPlanConfigStore = BackupPlanConfigStore(context),
    private val stateStore: BackupPlanScheduleStateStore = BackupPlanScheduleStateStore(context),
    private val syncStore: BackupWorkerStateStore = BackupWorkerStateStore(context),
) {
    fun schedulePlan(config: BackupPlanConfig): BackupPlanScheduleResult {
        configStore.save(config)
        return enqueue(config, referenceTimeMs = System.currentTimeMillis())
    }

    fun cancelPlan(planId: String, removeConfig: Boolean = true): BackupPlanScheduleResult {
        val activePlanId = configStore.loadAll().firstOrNull()?.planId
        if (activePlanId != null && activePlanId != planId) {
            stateStore.remove(planId)
            syncStore.setPlanEnabled(planId, false)
            syncStore.updatePlanScheduleState(planId, "unscheduled", null, null)
            if (removeConfig) {
                configStore.remove(planId)
            }
            return BackupPlanScheduleResult.unscheduled()
        }

        WorkManager.getInstance(context).cancelUniqueWork(uniqueWorkName(planId))
        cancelAlarm(planId)
        stateStore.remove(planId)
        syncStore.setPlanEnabled(planId, false)
        syncStore.updatePlanScheduleState(planId, "unscheduled", null, null)
        if (removeConfig) {
            configStore.remove(planId)
        }
        return BackupPlanScheduleResult.unscheduled()
    }

    fun stopCurrentRun(planId: String): BackupPlanScheduleResult {
        val config = configStore.load(planId)
            ?: return BackupPlanScheduleResult.failed("缺少计划配置，无法停止当前备份")
        syncStore.markUserStopRequested(planId)
        syncStore.markPlanRunStopping(planId, "正在停止本次备份…")
        WorkManager.getInstance(context).cancelUniqueWork(uniqueWorkName(planId))
        cancelAlarm(planId)
        return if (config.isRecurring()) {
            scheduleNextOccurrence(config, referenceTimeMs = System.currentTimeMillis() + 1000L)
        } else {
            stateStore.remove(planId)
            syncStore.updatePlanScheduleState(planId, "unscheduled", null, null)
            configStore.remove(planId)
            BackupPlanScheduleResult.unscheduled()
        }
    }

    fun scheduleNextRun(planId: String): BackupPlanScheduleResult {
        val config = configStore.load(planId) ?: return BackupPlanScheduleResult.failed("缺少计划配置")
        if (!config.isRecurring()) {
            return cancelPlan(planId)
        }
        return scheduleNextOccurrence(config, referenceTimeMs = System.currentTimeMillis() + 1000L)
    }

    fun restoreAllPlans(): List<Pair<String, BackupPlanScheduleResult>> {
        return configStore.loadAll().map { config ->
            config.planId to restorePlan(config)
        }
    }

    fun getWorkerStateSnapshot(): Map<String, Any?> = syncStore.snapshotMap()

    private fun restorePlan(config: BackupPlanConfig): BackupPlanScheduleResult {
        configStore.save(config)
        stateStore.remove(config.planId)
        cancelAlarm(config.planId)
        WorkManager.getInstance(context).cancelUniqueWork(uniqueWorkName(config.planId))
        return enqueue(config, referenceTimeMs = System.currentTimeMillis())
    }

    private fun enqueue(config: BackupPlanConfig, referenceTimeMs: Long): BackupPlanScheduleResult {
        cancelAlarm(config.planId)
        WorkManager.getInstance(context).cancelUniqueWork(uniqueWorkName(config.planId))
        return scheduleNextOccurrence(config, referenceTimeMs)
    }

    private fun scheduleNextOccurrence(
        config: BackupPlanConfig,
        referenceTimeMs: Long,
    ): BackupPlanScheduleResult {
        val notificationState = resolveScheduledBackupNotificationState(context)
        if (!notificationState.visibleInDrawer) {
            cancelAlarm(config.planId)
            WorkManager.getInstance(context).cancelUniqueWork(uniqueWorkName(config.planId))
            stateStore.remove(config.planId)
            syncStore.setPlanEnabled(config.planId, true)
            syncStore.updatePlanScheduleState(
                config.planId,
                "failed",
                null,
                notificationState.message,
            )
            return BackupPlanScheduleResult.failed(notificationState.message)
        }

        val nextRunAt = BackupScheduleCalculator.nextRunAt(config, referenceTimeMs) ?: run {
            return cancelPlan(config.planId)
        }
        if (!config.isRecurring() && nextRunAt <= System.currentTimeMillis()) {
            return cancelPlan(config.planId)
        }

        scheduleAlarm(config.planId, nextRunAt)

        stateStore.save(config.planId, nextRunAt)
        syncStore.setPlanEnabled(config.planId, true)
        syncStore.updatePlanScheduleState(config.planId, "scheduled", nextRunAt, null)
        return BackupPlanScheduleResult.scheduled(nextRunAt)
    }

    private fun scheduleAlarm(planId: String, triggerAtMs: Long) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        cancelAlarm(planId)
        val pendingIntent = BackupAlarmReceiver.createPendingIntent(context, planId, triggerAtMs)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            alarmManager.setAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                triggerAtMs,
                pendingIntent,
            )
        } else {
            alarmManager.set(
                AlarmManager.RTC_WAKEUP,
                triggerAtMs,
                pendingIntent,
            )
        }
    }

    private fun cancelAlarm(planId: String) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pendingIntent = BackupAlarmReceiver.findExistingPendingIntent(context, planId)
            ?: return
        alarmManager.cancel(pendingIntent)
        pendingIntent.cancel()
    }

    companion object {
        const val INPUT_PLAN_ID_KEY = "planId"
        const val INPUT_SCHEDULED_RUN_AT_MILLIS_KEY = "scheduledRunAtMillis"

        fun uniqueWorkName(planId: String): String = "backup-plan-active"

        private fun sanitizePlanId(planId: String): String {
            return planId.replace(Regex("[^A-Za-z0-9_-]"), "_")
        }
    }
}

object BackupScheduleCalculator {
    fun nextRunAt(config: BackupPlanConfig, referenceTimeMs: Long): Long? {
        val now = Calendar.getInstance().apply { timeInMillis = referenceTimeMs }
        return when (config.scheduleType) {
            "daily" -> nextDaily(config, now)
            "weekly" -> nextWeekly(config, now)
            "monthly" -> nextMonthly(config, now)
            "once" -> config.onceAtMillis
            else -> null
        }
    }

    fun shouldTreatAsMissed(
        config: BackupPlanConfig,
        scheduledRunAtMillis: Long,
        currentTimeMillis: Long,
    ): Boolean {
        if (scheduledRunAtMillis <= 0L || currentTimeMillis < scheduledRunAtMillis) {
            return false
        }
        if (config.isRecurring()) {
            val nextScheduledRunAt =
                nextRunAt(config, scheduledRunAtMillis + 1000L)
                    ?: return false
            return currentTimeMillis >= nextScheduledRunAt
        }
        return currentTimeMillis - scheduledRunAtMillis > 24 * 60 * 60 * 1000L
    }

    private fun nextDaily(config: BackupPlanConfig, now: Calendar): Long {
        val candidate = now.clone() as Calendar
        candidate.set(Calendar.HOUR_OF_DAY, config.hour)
        candidate.set(Calendar.MINUTE, config.minute)
        candidate.set(Calendar.SECOND, 0)
        candidate.set(Calendar.MILLISECOND, 0)
        if (!candidate.after(now)) {
            candidate.add(Calendar.DAY_OF_YEAR, 1)
        }
        return candidate.timeInMillis
    }

    private fun nextWeekly(config: BackupPlanConfig, now: Calendar): Long {
        val targetWeekday = flutterWeekdayToCalendarDay(config.weekday ?: 1)
        val candidate = now.clone() as Calendar
        candidate.set(Calendar.HOUR_OF_DAY, config.hour)
        candidate.set(Calendar.MINUTE, config.minute)
        candidate.set(Calendar.SECOND, 0)
        candidate.set(Calendar.MILLISECOND, 0)
        var daysUntil = (targetWeekday - now.get(Calendar.DAY_OF_WEEK) + 7) % 7
        if (daysUntil == 0 && !candidate.after(now)) {
            daysUntil = 7
        }
        candidate.add(Calendar.DAY_OF_YEAR, daysUntil)
        return candidate.timeInMillis
    }

    private fun nextMonthly(config: BackupPlanConfig, now: Calendar): Long {
        val candidate = now.clone() as Calendar
        candidate.set(Calendar.HOUR_OF_DAY, config.hour)
        candidate.set(Calendar.MINUTE, config.minute)
        candidate.set(Calendar.SECOND, 0)
        candidate.set(Calendar.MILLISECOND, 0)
        candidate.set(
            Calendar.DAY_OF_MONTH,
            clampDayOfMonth(
                candidate.getActualMaximum(Calendar.DAY_OF_MONTH),
                config.dayOfMonth ?: candidate.get(Calendar.DAY_OF_MONTH),
            ),
        )
        if (!candidate.after(now)) {
            candidate.add(Calendar.MONTH, 1)
            candidate.set(
                Calendar.DAY_OF_MONTH,
                clampDayOfMonth(
                    candidate.getActualMaximum(Calendar.DAY_OF_MONTH),
                    config.dayOfMonth ?: 1,
                ),
            )
        }
        return candidate.timeInMillis
    }

    private fun clampDayOfMonth(lastDay: Int, requestedDay: Int): Int {
        return requestedDay.coerceIn(1, lastDay)
    }

    private fun flutterWeekdayToCalendarDay(weekday: Int): Int {
        return when (weekday) {
            1 -> Calendar.MONDAY
            2 -> Calendar.TUESDAY
            3 -> Calendar.WEDNESDAY
            4 -> Calendar.THURSDAY
            5 -> Calendar.FRIDAY
            6 -> Calendar.SATURDAY
            7 -> Calendar.SUNDAY
            else -> Calendar.MONDAY
        }
    }
}

private fun Map<*, *>.stringValue(key: String): String? {
    val raw = this[key] ?: return null
    val value = raw.toString().trim()
    return value.ifEmpty { null }
}

private fun Map<*, *>.booleanValue(key: String): Boolean {
    return when (val raw = this[key]) {
        is Boolean -> raw
        is Number -> raw.toInt() != 0
        is String -> raw == "1" || raw.equals("true", ignoreCase = true)
        else -> false
    }
}

private fun Map<*, *>.intValue(key: String): Int? {
    return when (val raw = this[key]) {
        is Int -> raw
        is Long -> raw.toInt()
        is Number -> raw.toInt()
        is String -> raw.toIntOrNull()
        else -> null
    }
}

private fun Map<*, *>.longValue(key: String): Long? {
    return when (val raw = this[key]) {
        is Long -> raw
        is Int -> raw.toLong()
        is Number -> raw.toLong()
        is String -> raw.toLongOrNull()
        else -> null
    }
}

private fun JSONObject.optNullableInt(key: String): Int? {
    return if (isNull(key)) {
        null
    } else {
        optInt(key)
    }
}

private fun JSONObject.optNullableLong(key: String): Long? {
    return if (isNull(key)) {
        null
    } else {
        optLong(key)
    }
}

private fun sanitizePlanId(planId: String): String {
    return planId.replace(Regex("[^A-Za-z0-9_-]"), "_")
}
