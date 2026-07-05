package com.diubang.nasclient

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.content.ContextCompat

internal enum class BackupMediaAccessScope(val rawValue: String) {
    FULL("full"),
    PARTIAL("partial"),
    DENIED("denied"),
}

internal data class BackupMediaAccessState(
    val scope: BackupMediaAccessScope,
    val includeImages: Boolean,
    val includeVideos: Boolean,
    val hasImagePermission: Boolean,
    val hasVideoPermission: Boolean,
    val hasSelectedPhotosPermission: Boolean,
) {
    val isFullAccess: Boolean
        get() = scope == BackupMediaAccessScope.FULL

    fun blockingMessage(): String? {
        return when (scope) {
            BackupMediaAccessScope.FULL -> null
            BackupMediaAccessScope.PARTIAL ->
                "当前仅授予了“所选照片和视频”权限，整机图库备份在后台无法稳定读取全部媒体。请到系统设置中把铥棒文件的照片和视频访问改为“允许全部”，再重新执行整机图库备份。"

            BackupMediaAccessScope.DENIED ->
                "当前未授予铥棒文件读取照片和视频的权限。请在系统弹窗或系统设置中允许访问全部照片和视频后，再执行整机图库备份。"
        }
    }

    fun toMap(): Map<String, Any?> {
        return mapOf(
            "scope" to scope.rawValue,
            "isFullAccess" to isFullAccess,
            "includeImages" to includeImages,
            "includeVideos" to includeVideos,
            "hasImagePermission" to hasImagePermission,
            "hasVideoPermission" to hasVideoPermission,
            "hasSelectedPhotosPermission" to hasSelectedPhotosPermission,
            "message" to blockingMessage(),
        )
    }
}

internal object BackupMediaAccessEvaluator {
    fun resolve(
        context: Context,
        includeImages: Boolean,
        includeVideos: Boolean,
    ): BackupMediaAccessState {
        val hasImagePermission = !includeImages || hasMediaPermission(context, imagePermissionName())
        val hasVideoPermission = !includeVideos || hasMediaPermission(context, videoPermissionName())
        val hasSelectedPhotosPermission =
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE &&
                hasMediaPermission(context, Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED)

        val scope = when {
            hasImagePermission && hasVideoPermission -> BackupMediaAccessScope.FULL
            hasSelectedPhotosPermission -> BackupMediaAccessScope.PARTIAL
            else -> BackupMediaAccessScope.DENIED
        }

        return BackupMediaAccessState(
            scope = scope,
            includeImages = includeImages,
            includeVideos = includeVideos,
            hasImagePermission = hasImagePermission,
            hasVideoPermission = hasVideoPermission,
            hasSelectedPhotosPermission = hasSelectedPhotosPermission,
        )
    }

    private fun imagePermissionName(): String {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            Manifest.permission.READ_MEDIA_IMAGES
        } else {
            Manifest.permission.READ_EXTERNAL_STORAGE
        }
    }

    private fun videoPermissionName(): String {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            Manifest.permission.READ_MEDIA_VIDEO
        } else {
            Manifest.permission.READ_EXTERNAL_STORAGE
        }
    }

    private fun hasMediaPermission(context: Context, permission: String): Boolean {
        return ContextCompat.checkSelfPermission(
            context,
            permission,
        ) == PackageManager.PERMISSION_GRANTED
    }
}
