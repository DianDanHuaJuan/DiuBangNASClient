package com.diubang.nasclient

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat

internal const val SCHEDULED_BACKUP_NOTIFICATION_CHANNEL_ID = "scheduled_backup_progress_v2"

data class ScheduledBackupNotificationState(
    val runtimePermissionGranted: Boolean,
    val appNotificationsEnabled: Boolean,
    val channelEnabled: Boolean,
    val channelImportance: Int?,
    val message: String,
) {
    val visibleInDrawer: Boolean
        get() = runtimePermissionGranted && appNotificationsEnabled && channelEnabled

    fun toMap(): Map<String, Any?> {
        return mapOf(
            "runtimePermissionGranted" to runtimePermissionGranted,
            "appNotificationsEnabled" to appNotificationsEnabled,
            "channelEnabled" to channelEnabled,
            "channelImportance" to channelImportance,
            "visibleInDrawer" to visibleInDrawer,
            "message" to message,
        )
    }
}

fun ensureScheduledBackupNotificationChannel(context: Context) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
        return
    }
    val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    val existing = manager.getNotificationChannel(SCHEDULED_BACKUP_NOTIFICATION_CHANNEL_ID)
    if (existing != null) {
        return
    }

    val channel = NotificationChannel(
        SCHEDULED_BACKUP_NOTIFICATION_CHANNEL_ID,
        "定时备份",
        NotificationManager.IMPORTANCE_DEFAULT,
    ).apply {
        description = "显示定时备份的执行进度"
        setShowBadge(false)
        enableVibration(false)
        setSound(null, null)
    }
    manager.createNotificationChannel(channel)
}

fun resolveScheduledBackupNotificationState(context: Context): ScheduledBackupNotificationState {
    ensureScheduledBackupNotificationChannel(context)

    val runtimePermissionGranted =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.POST_NOTIFICATIONS,
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
    val notificationsEnabled = NotificationManagerCompat.from(context).areNotificationsEnabled()
    val channelImportance =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.getNotificationChannel(SCHEDULED_BACKUP_NOTIFICATION_CHANNEL_ID)?.importance
        } else {
            null
        }
    val channelEnabled =
        channelImportance == null || channelImportance != NotificationManager.IMPORTANCE_NONE

    val message =
        when {
            !runtimePermissionGranted ->
                "系统通知权限未开启，Android 13 及以上会把前台备份通知隐藏到任务管理器，不显示在下拉状态栏。"
            !notificationsEnabled ->
                "系统已关闭铥棒文件通知，定时备份进度不会显示在下拉状态栏。"
            !channelEnabled ->
                "“定时备份”通知渠道已被关闭，定时备份进度不会显示在下拉状态栏。"
            else -> "定时备份通知可正常显示。"
        }

    return ScheduledBackupNotificationState(
        runtimePermissionGranted = runtimePermissionGranted,
        appNotificationsEnabled = notificationsEnabled,
        channelEnabled = channelEnabled,
        channelImportance = channelImportance,
        message = message,
    )
}
