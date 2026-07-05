package com.diubang.nasclient

import android.app.Notification
import android.app.PendingIntent
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.os.BatteryManager
import android.provider.MediaStore
import android.util.Base64
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.work.CoroutineWorker
import androidx.work.ForegroundInfo
import androidx.work.WorkerParameters
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import okio.BufferedSink
import okio.source
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayInputStream
import java.io.File
import java.net.URI
import java.security.KeyStore
import java.security.MessageDigest
import java.security.SecureRandom
import java.security.cert.Certificate
import java.security.cert.CertificateFactory
import java.util.concurrent.TimeUnit
import javax.net.ssl.HttpsURLConnection
import javax.net.ssl.SSLContext
import javax.net.ssl.TrustManager
import javax.net.ssl.TrustManagerFactory
import javax.net.ssl.X509TrustManager

private const val BACKUP_WORKER_TAG = "BackupExecutionWorker"
private const val BACKUP_BATCH_SIZE = 20
private const val MAX_RETRY_COUNT = 5
private const val RETRY_WINDOW_MILLIS = 5 * 60 * 1000L

internal fun throwIfBackupCancelled(isCancelled: () -> Boolean) {
    if (isCancelled()) {
        throw CancellationException("Backup cancelled by user")
    }
}

class BackupExecutionWorker(
    appContext: Context,
    workerParams: WorkerParameters,
) : CoroutineWorker(appContext, workerParams) {
    override suspend fun doWork() = withContext(Dispatchers.IO) {
        val planId = inputData.getString(BackupSchedulerManager.INPUT_PLAN_ID_KEY)
            ?: return@withContext Result.success()
        val scheduledRunAtMillis = inputData.getLong(
            BackupSchedulerManager.INPUT_SCHEDULED_RUN_AT_MILLIS_KEY,
            0L,
        )
        val configStore = BackupPlanConfigStore(applicationContext)
        val config = configStore.load(planId) ?: return@withContext Result.success()
        val schedulerManager = BackupSchedulerManager(applicationContext, configStore)
        val syncStore = BackupWorkerStateStore(applicationContext)
        val database = BackupNativeDatabase(applicationContext)
        val runId = "scheduled-$id"
        val startedAt = System.currentTimeMillis()
        val firstStartedAt = database.loadRunStartedAtMillis(runId) ?: startedAt

        var summary = BackupExecutionSummary.empty()
        var status = "completed"
        var errorMessage: String? = null
        var workerResult: Result = Result.success()
        var shouldFinalizeRun = true

        try {
            Log.i(
                BACKUP_WORKER_TAG,
                "Scheduled backup worker started: planId=$planId, attempt=$runAttemptCount, sdk=${Build.VERSION.SDK_INT}, scheduledRunAtMillis=$scheduledRunAtMillis",
            )
            if (runAttemptCount == 0) {
                syncStore.clearUserStopRequested(planId)
                database.insertRun(
                    runId = runId,
                    planId = config.planId,
                    triggerType = "scheduled",
                    status = "running",
                    startedAtMillis = startedAt,
                )
            } else {
                database.updateRunStatus(
                    runId = runId,
                    status = "running",
                    errorMessage = "正在进行第 $runAttemptCount 次重试",
                )
            }
            if (
                runAttemptCount == 0 &&
                BackupScheduleCalculator.shouldTreatAsMissed(
                    config = config,
                    scheduledRunAtMillis = scheduledRunAtMillis,
                    currentTimeMillis = startedAt,
                )
            ) {
                status = "missed"
                errorMessage = "计划时间已到，但执行约束未满足，本次定时备份已跳过"
                Log.w(
                    BACKUP_WORKER_TAG,
                    "Scheduled backup skipped because the allowed execution window was missed",
                )
                return@withContext Result.success()
            }
            if (
                runAttemptCount > 0 &&
                startedAt - firstStartedAt >= RETRY_WINDOW_MILLIS
            ) {
                status = "failed"
                errorMessage = "重试窗口已超过 5 分钟，本次定时备份已放弃"
                Log.w(
                    BACKUP_WORKER_TAG,
                    "Scheduled backup abandoned because the retry window expired",
                )
                return@withContext Result.success()
            }
            val requiresCharging = inputData.getBoolean("requiresCharging", false)
            if (requiresCharging && !isDeviceCharging(applicationContext)) {
                status = "skipped"
                errorMessage = "计划要求充电时才执行，当前未充电，本次定时备份已跳过"
                Log.i(BACKUP_WORKER_TAG, errorMessage)
                return@withContext Result.success()
            }
            val notificationState = resolveScheduledBackupNotificationState(applicationContext)
            Log.i(
                BACKUP_WORKER_TAG,
                "Scheduled backup notification state: runtimeGranted=${notificationState.runtimePermissionGranted}, appEnabled=${notificationState.appNotificationsEnabled}, channelEnabled=${notificationState.channelEnabled}, channelImportance=${notificationState.channelImportance}, visibleInDrawer=${notificationState.visibleInDrawer}",
            )
            if (!notificationState.visibleInDrawer) {
                status = "failed"
                errorMessage = notificationState.message
                database.updateRunStatus(
                    runId = runId,
                    status = status,
                    errorMessage = errorMessage,
                    progressMessage = errorMessage,
                )
                Log.w(
                    BACKUP_WORKER_TAG,
                    "Scheduled backup aborted because the foreground notification would not be visible in the drawer",
                )
                return@withContext Result.success()
            }
            Log.i(
                BACKUP_WORKER_TAG,
                "Promoting scheduled backup worker to foreground: planId=${config.planId}",
            )
            val initialProgress = BackupExecutionProgress(message = "正在准备启动定时备份…")
            database.updateRunProgress(runId, initialProgress)
            setForeground(createForegroundInfo(config.planId, config.planName, initialProgress))
            val progressReporter = BackupExecutionProgressReporter { progress ->
                database.updateRunProgress(runId, progress)
                setForeground(createForegroundInfo(config.planId, config.planName, progress))
            }
            val isCancelled = {
                isStopped || syncStore.isUserStopRequested(planId)
            }
            summary = BackupPlanExecutor(
                applicationContext,
                database,
                progressReporter,
            ).execute(config, isCancelled)
            status = if (summary.failedCount > 0) "partial_failed" else "completed"
            errorMessage = summary.errorMessage
            database.updatePlanLastRun(config.planId, System.currentTimeMillis())
            Log.d(BACKUP_WORKER_TAG, "Scheduled backup finished: uploaded=${summary.queuedCount}, skipped=${summary.skippedCount}, failed=${summary.failedCount}")
        } catch (error: Exception) {
            val userStopRequested = syncStore.isUserStopRequested(planId)
            val shouldRetry =
                !userStopRequested &&
                    runAttemptCount < MAX_RETRY_COUNT &&
                    startedAt - firstStartedAt < RETRY_WINDOW_MILLIS &&
                    error.isRetryableFailure()
            if (error is CancellationException || isStopped || userStopRequested) {
                status = "stopped"
                errorMessage = "用户已停止本次备份"
                Log.i(BACKUP_WORKER_TAG, "Scheduled backup stopped manually")
            } else if (shouldRetry) {
                shouldFinalizeRun = false
                workerResult = Result.retry()
                val nextAttempt = runAttemptCount + 1
                errorMessage =
                    "执行失败，将在约 1 分钟后进行第 $nextAttempt 次重试：${error.message ?: error}"
                database.updateRunStatus(
                    runId = runId,
                    status = "retrying",
                    errorMessage = errorMessage,
                    progressMessage = errorMessage,
                )
                Log.w(
                    BACKUP_WORKER_TAG,
                    "Scheduled backup failed and will retry (attempt $nextAttempt/$MAX_RETRY_COUNT)",
                    error,
                )
            } else {
                status = "failed"
                errorMessage = error.message ?: error.toString()
                Log.e(BACKUP_WORKER_TAG, "Scheduled backup failed", error)
            }
        } finally {
            if (shouldFinalizeRun) {
                database.completeRun(
                    runId = runId,
                    status = status,
                    scannedCount = summary.scannedCount,
                    queuedCount = summary.queuedCount,
                    skippedCount = summary.skippedCount,
                    failedCount = summary.failedCount,
                    finishedAtMillis = System.currentTimeMillis(),
                    errorMessage = errorMessage,
                )

                if (config.isRecurring()) {
                    val userStopRequested = syncStore.isUserStopRequested(planId)
                    if (!(status == "stopped" && userStopRequested)) {
                        val scheduleResult = schedulerManager.scheduleNextRun(config.planId)
                        database.updatePlanScheduleState(
                            planId = config.planId,
                            scheduleStatus = scheduleResult.status,
                            scheduledRunAtMillis = scheduleResult.nextRunAtMillis,
                            scheduleError = scheduleResult.errorMessage,
                        )
                    }
                    if (userStopRequested) {
                        syncStore.clearUserStopRequested(planId)
                    }
                } else {
                    database.disablePlan(config.planId)
                    schedulerManager.cancelPlan(config.planId)
                    database.updatePlanScheduleState(
                        planId = config.planId,
                        scheduleStatus = "unscheduled",
                        scheduledRunAtMillis = null,
                        scheduleError = null,
                    )
                }
            }
        }

        workerResult
    }

    private fun createForegroundInfo(
        planId: String,
        planName: String,
        progress: BackupExecutionProgress = BackupExecutionProgress(message = "正在准备执行 $planName"),
    ): ForegroundInfo {
        ensureScheduledBackupNotificationChannel(applicationContext)

        val builder = NotificationCompat.Builder(
            applicationContext,
            SCHEDULED_BACKUP_NOTIFICATION_CHANNEL_ID,
        )
            .setContentTitle(progress.titleText())
            .setContentText(progress.message)
            .setSubText(planName)
            .setStyle(NotificationCompat.BigTextStyle().bigText(progress.expandedText(planName)))
            .setSmallIcon(R.mipmap.ic_launcher)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)

        val launchPendingIntent = buildLaunchAppPendingIntent()
        if (launchPendingIntent != null) {
            builder.setContentIntent(launchPendingIntent)
            builder.addAction(
                android.R.drawable.ic_menu_view,
                "查看铥棒文件",
                launchPendingIntent,
            )
        }

        val stopPendingIntent = BackupStopReceiver.createPendingIntent(
            applicationContext,
            planId,
        )
        builder.addAction(
            android.R.drawable.ic_menu_close_clear_cancel,
            "停止备份",
            stopPendingIntent,
        )

        if (progress.hasDeterminateProgress) {
            builder.setProgress(progress.progressMax, progress.progressValue, false)
        } else {
            builder.setProgress(0, 0, true)
        }

        val notification: Notification = builder.build()

        return ForegroundInfo(
            NOTIFICATION_ID,
            notification,
            ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
        )
    }

    private fun buildLaunchAppPendingIntent(): PendingIntent? {
        val launchIntent = applicationContext.packageManager
            .getLaunchIntentForPackage(applicationContext.packageName)
            ?.apply {
                addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP,
                )
            }
            ?: return null

        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_IMMUTABLE
            } else {
                0
            }
        return PendingIntent.getActivity(
            applicationContext,
            0,
            launchIntent,
            flags,
        )
    }

    companion object {
        private const val NOTIFICATION_ID = 4101
    }
}

private data class BackupExecutionProgress(
    val message: String,
    val processedCount: Int? = null,
    val totalCount: Int? = null,
    val uploadedCount: Int = 0,
    val skippedCount: Int = 0,
    val failedCount: Int = 0,
) {
    val hasDeterminateProgress: Boolean
        get() = progressMax > 0

    val progressMax: Int
        get() = totalCount?.takeIf { it > 0 } ?: 0

    val progressValue: Int
        get() = processedCount?.coerceIn(0, progressMax.takeIf { it > 0 } ?: Int.MAX_VALUE) ?: 0

    fun titleText(): String {
        return if (hasDeterminateProgress) {
            "定时备份进行中 $progressValue / $progressMax"
        } else {
            "定时备份进行中"
        }
    }

    fun expandedText(planName: String): String {
        val lines = mutableListOf<String>()
        lines += message
        lines += "计划：$planName"
        if (hasDeterminateProgress) {
            lines += "进度：$progressValue / $progressMax"
        }
        lines += "上传 $uploadedCount · 跳过 $skippedCount · 失败 $failedCount"
        return lines.joinToString(separator = "\n")
    }
}

private class BackupExecutionProgressReporter(
    private val onProgress: suspend (BackupExecutionProgress) -> Unit,
) {
    private var lastProgress: BackupExecutionProgress? = null

    suspend fun report(
        message: String,
        force: Boolean = false,
        processedCount: Int? = null,
        totalCount: Int? = null,
        uploadedCount: Int = 0,
        skippedCount: Int = 0,
        failedCount: Int = 0,
    ) {
        val progress = BackupExecutionProgress(
            message = message,
            processedCount = processedCount,
            totalCount = totalCount,
            uploadedCount = uploadedCount,
            skippedCount = skippedCount,
            failedCount = failedCount,
        )
        if (!force && progress == lastProgress) {
            return
        }
        lastProgress = progress
        Log.i(BACKUP_WORKER_TAG, "Worker progress: $message")
        onProgress(progress)
    }
}

data class BackupExecutionSummary(
    val scannedCount: Int,
    val queuedCount: Int,
    val skippedCount: Int,
    val failedCount: Int,
    val errorMessage: String?,
) {
    companion object {
        fun empty(): BackupExecutionSummary {
            return BackupExecutionSummary(
                scannedCount = 0,
                queuedCount = 0,
                skippedCount = 0,
                failedCount = 0,
                errorMessage = null,
            )
        }
    }
}

private class BackupPlanExecutor(
    private val context: Context,
    private val database: BackupNativeDatabase,
    private val progressReporter: BackupExecutionProgressReporter,
) {
    suspend fun execute(
        config: BackupPlanConfig,
        isCancelled: () -> Boolean = { false },
    ): BackupExecutionSummary {
        throwIfBackupCancelled(isCancelled)
        progressReporter.report("正在扫描本地媒体库…", force = true)
        val mediaItems = BackupMediaStoreReader(context).loadAllMedia(config)
        throwIfBackupCancelled(isCancelled)
        if (mediaItems.isEmpty()) {
            progressReporter.report("未找到可备份的媒体文件", force = true)
            return BackupExecutionSummary.empty()
        }
        progressReporter.report(
            "已发现 ${mediaItems.size} 个媒体文件，开始准备上传",
            force = true,
            processedCount = 0,
            totalCount = mediaItems.size,
        )

        val cachedStates = database.loadAssetStates(
            serverId = config.serverId.ifBlank { config.serverUrl },
            rootId = config.rootId,
            sourceFingerprints = mediaItems.map { it.sourceFingerprint },
        )
        val client = BackupHttpClient(config, context.contentResolver)
        val stateUpdates = mutableListOf<BackupAssetStateRecord>()
        val totalHashCount = mediaItems.count { item ->
            cachedStates[item.sourceFingerprint] == null
        }
        var hashedCount = 0
        var hashTargetCount = 0
        var uploadedProgressCount = 0

        var skippedCount = 0
        var uploadedCount = 0
        var failedCount = 0
        var firstError: String? = null

        for ((batchIndex, batch) in mediaItems.chunked(BACKUP_BATCH_SIZE).withIndex()) {
            throwIfBackupCancelled(isCancelled)
            progressReporter.report(
                "正在处理第 ${batchIndex + 1} 批，共 ${mediaItems.size} 个文件",
                force = batchIndex == 0,
                processedCount = uploadedProgressCount,
                totalCount = mediaItems.size,
                uploadedCount = uploadedCount,
                skippedCount = skippedCount,
                failedCount = failedCount,
            )
            progressReporter.report(
                "正在向服务端预检第 ${batchIndex + 1} 批（${batch.size} 个）",
                force = true,
                processedCount = uploadedProgressCount,
                totalCount = mediaItems.size,
                uploadedCount = uploadedCount,
                skippedCount = skippedCount,
                failedCount = failedCount,
            )
            val decisionMap = mutableMapOf<String, BackupPreflightDecision>()
            client.preflight(
                config.rootId,
                batch.map { item -> PreparedBackupItem(item, null) },
            ).forEach { decision ->
                decisionMap[decision.id] = decision
            }

            val preparedById = mutableMapOf<String, PreparedBackupItem>()
            val itemsNeedingHash = mutableListOf<PreparedBackupItem>()
            for (item in batch) {
                throwIfBackupCancelled(isCancelled)
                val decision = decisionMap[item.sourceFingerprint] ?: continue
                if (decision.action != "need_hash") {
                    continue
                }

                val cachedHash = cachedStates[item.sourceFingerprint]
                val contentHash = cachedHash ?: client.computeContentHash(item.contentUri)
                if (cachedHash == null) {
                    hashTargetCount += 1
                    hashedCount += 1
                    if (
                        hashedCount == 1 ||
                        hashedCount == hashTargetCount ||
                        hashedCount % 5 == 0
                    ) {
                        progressReporter.report(
                            "正在生成文件指纹",
                            processedCount = hashedCount,
                            totalCount = hashTargetCount,
                            uploadedCount = uploadedCount,
                            skippedCount = skippedCount,
                            failedCount = failedCount,
                        )
                    }
                }
                val prepared = PreparedBackupItem(item, contentHash)
                itemsNeedingHash += prepared
                preparedById[item.sourceFingerprint] = prepared
            }

            if (itemsNeedingHash.isNotEmpty()) {
                client.preflight(config.rootId, itemsNeedingHash).forEach { decision ->
                    decisionMap[decision.id] = decision
                }
            }

            for (item in batch) {
                throwIfBackupCancelled(isCancelled)
                val decision = decisionMap[item.sourceFingerprint]
                if (decision == null) {
                    failedCount += 1
                    firstError = firstError ?: "${item.displayName}: 服务端预检返回缺失"
                    continue
                }

                var contentHash = preparedById[item.sourceFingerprint]?.contentHash
                    ?: cachedStates[item.sourceFingerprint]
                if (contentHash == null && decision.action == "upload") {
                    hashTargetCount += 1
                    hashedCount += 1
                    contentHash = client.computeContentHash(item.contentUri)
                    progressReporter.report(
                        "正在生成文件指纹",
                        processedCount = hashedCount,
                        totalCount = hashTargetCount,
                        uploadedCount = uploadedCount,
                        skippedCount = skippedCount,
                        failedCount = failedCount,
                    )
                }

                if (contentHash != null && decision.action != "need_hash") {
                    stateUpdates += BackupAssetStateRecord(
                        serverId = config.serverId.ifBlank { config.serverUrl },
                        rootId = config.rootId,
                        sourceFingerprint = item.sourceFingerprint,
                        sourceId = item.sourceId,
                        displayName = item.displayName,
                        localPath = item.contentUri.toString(),
                        sizeBytes = item.sizeBytes,
                        modifiedMs = item.modifiedMs,
                        mimeType = item.mimeType,
                        contentHash = contentHash,
                        remotePath = decision.relativePath,
                        updatedAtMillis = System.currentTimeMillis(),
                    )
                }

                if (decision.action == "skip") {
                    skippedCount += 1
                    uploadedProgressCount += 1
                    if (uploadedProgressCount == mediaItems.size || uploadedProgressCount % 5 == 0) {
                        progressReporter.report(
                            "正在上传媒体文件",
                            processedCount = uploadedProgressCount,
                            totalCount = mediaItems.size,
                            uploadedCount = uploadedCount,
                            skippedCount = skippedCount,
                            failedCount = failedCount,
                        )
                    }
                    continue
                }
                if (decision.action == "need_hash") {
                    failedCount += 1
                    firstError = firstError ?: "${item.displayName}: 服务端未返回最终预检结果"
                    continue
                }
                if (contentHash == null) {
                    failedCount += 1
                    firstError = firstError ?: "${item.displayName}: 无法生成备份指纹"
                    continue
                }

                try {
                    client.upload(
                        item = item,
                        rootId = config.rootId,
                        relativePath = decision.relativePath,
                        metadataHeader = buildBackupMetadataHeader(
                            sourceFingerprint = item.sourceFingerprint,
                            contentHash = contentHash,
                            deviceId = config.deviceId,
                            sourceId = item.sourceId,
                            sizeBytes = item.sizeBytes,
                            modifiedMs = item.modifiedMs,
                        ),
                        isCancelled = isCancelled,
                    )
                    uploadedCount += 1
                    uploadedProgressCount += 1
                    if (uploadedProgressCount == mediaItems.size || uploadedProgressCount % 5 == 0) {
                        progressReporter.report(
                            "正在上传媒体文件",
                            processedCount = uploadedProgressCount,
                            totalCount = mediaItems.size,
                            uploadedCount = uploadedCount,
                            skippedCount = skippedCount,
                            failedCount = failedCount,
                        )
                    }
                } catch (error: Exception) {
                    failedCount += 1
                    uploadedProgressCount += 1
                    firstError = firstError ?: "${item.displayName}: ${error.message ?: error}"
                    Log.e(BACKUP_WORKER_TAG, "Failed to upload ${item.displayName}", error)
                    if (uploadedProgressCount == mediaItems.size || uploadedProgressCount % 5 == 0) {
                        progressReporter.report(
                            "正在上传媒体文件",
                            processedCount = uploadedProgressCount,
                            totalCount = mediaItems.size,
                            uploadedCount = uploadedCount,
                            skippedCount = skippedCount,
                            failedCount = failedCount,
                        )
                    }
                }
            }
        }

        if (stateUpdates.isNotEmpty()) {
            database.upsertAssetStates(stateUpdates)
        }

        progressReporter.report(
            "备份完成：上传 $uploadedCount，跳过 $skippedCount，失败 $failedCount",
            force = true,
            processedCount = mediaItems.size,
            totalCount = mediaItems.size,
            uploadedCount = uploadedCount,
            skippedCount = skippedCount,
            failedCount = failedCount,
        )

        return BackupExecutionSummary(
            scannedCount = mediaItems.size,
            queuedCount = uploadedCount,
            skippedCount = skippedCount,
            failedCount = failedCount,
            errorMessage = firstError,
        )
    }

    private fun buildBackupMetadataHeader(
        sourceFingerprint: String,
        contentHash: String,
        deviceId: String,
        sourceId: String,
        sizeBytes: Long,
        modifiedMs: Long,
    ): String {
        val payload = JSONObject(
            mapOf(
                "sourceFingerprint" to sourceFingerprint,
                "contentHash" to contentHash,
                "deviceId" to deviceId,
                "sourceId" to sourceId,
                "sizeBytes" to sizeBytes,
                "modifiedMs" to modifiedMs,
            ),
        ).toString()
        return Base64.encodeToString(
            payload.toByteArray(Charsets.UTF_8),
            Base64.URL_SAFE or Base64.NO_WRAP,
        )
    }
}

private data class BackupMediaItem(
    val sourceId: String,
    val sourceFingerprint: String,
    val contentUri: Uri,
    val displayName: String,
    val sizeBytes: Long,
    val modifiedMs: Long,
    val mimeType: String?,
    val extension: String,
)

private data class PreparedBackupItem(
    val item: BackupMediaItem,
    val contentHash: String?,
)

private class BackupMediaStoreReader(private val context: Context) {
    fun loadAllMedia(config: BackupPlanConfig): List<BackupMediaItem> {
        if (!config.includeImages && !config.includeVideos) {
            return emptyList()
        }

        val accessState = BackupMediaAccessEvaluator.resolve(
            context,
            includeImages = config.includeImages,
            includeVideos = config.includeVideos,
        )
        Log.i(
            BACKUP_WORKER_TAG,
            "Media scan access: scope=${accessState.scope.rawValue}, includeImages=${config.includeImages}, includeVideos=${config.includeVideos}, hasImagePermission=${accessState.hasImagePermission}, hasVideoPermission=${accessState.hasVideoPermission}, hasSelectedPhotosPermission=${accessState.hasSelectedPhotosPermission}",
        )
        accessState.blockingMessage()?.let { message ->
            throw BackupMediaAccessException(message)
        }

        val collection = MediaStore.Files.getContentUri("external")
        val projection = arrayOf(
            MediaStore.Files.FileColumns._ID,
            MediaStore.Files.FileColumns.MEDIA_TYPE,
            MediaStore.MediaColumns.DISPLAY_NAME,
            MediaStore.MediaColumns.SIZE,
            MediaStore.MediaColumns.MIME_TYPE,
            MediaStore.MediaColumns.DATE_MODIFIED,
        )

        val selectionArgs = mutableListOf<String>()
        val selection = buildString {
            append("(")
            when {
                config.includeImages && config.includeVideos -> {
                    append("${MediaStore.Files.FileColumns.MEDIA_TYPE} = ? OR ${MediaStore.Files.FileColumns.MEDIA_TYPE} = ?")
                    selectionArgs += MediaStore.Files.FileColumns.MEDIA_TYPE_IMAGE.toString()
                    selectionArgs += MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO.toString()
                }

                config.includeImages -> {
                    append("${MediaStore.Files.FileColumns.MEDIA_TYPE} = ?")
                    selectionArgs += MediaStore.Files.FileColumns.MEDIA_TYPE_IMAGE.toString()
                }

                else -> {
                    append("${MediaStore.Files.FileColumns.MEDIA_TYPE} = ?")
                    selectionArgs += MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO.toString()
                }
            }
            append(")")
        }

        val deviceId = config.deviceId
        val items = mutableListOf<BackupMediaItem>()
        val cursor = try {
            context.contentResolver.query(
                collection,
                projection,
                selection,
                selectionArgs.toTypedArray(),
                "${MediaStore.MediaColumns.DATE_MODIFIED} DESC",
            )
        } catch (error: SecurityException) {
            Log.e(BACKUP_WORKER_TAG, "MediaStore query failed due to missing permission", error)
            throw BackupMediaAccessException(
                "系统未允许后台读取整机图库。请在系统设置中把铥棒文件的照片和视频访问改为“允许全部”。",
                error,
            )
        } ?: return emptyList()

        Log.i(
            BACKUP_WORKER_TAG,
            "MediaStore query opened: rowCount=${cursor.count}, selection=$selection, selectionArgs=${selectionArgs.joinToString(prefix = "[", postfix = "]")}",
        )

        cursor.use {
            val idIndex = it.getColumnIndexOrThrow(MediaStore.Files.FileColumns._ID)
            val nameIndex = it.getColumnIndexOrThrow(MediaStore.MediaColumns.DISPLAY_NAME)
            val sizeIndex = it.getColumnIndexOrThrow(MediaStore.MediaColumns.SIZE)
            val mimeTypeIndex = it.getColumnIndexOrThrow(MediaStore.MediaColumns.MIME_TYPE)
            val modifiedIndex = it.getColumnIndexOrThrow(MediaStore.MediaColumns.DATE_MODIFIED)

            while (it.moveToNext()) {
                val mediaId = it.getLong(idIndex)
                val displayName = it.getString(nameIndex)?.trim().orEmpty()
                if (displayName.isBlank()) {
                    continue
                }
                val sizeBytes = it.getLong(sizeIndex)
                if (sizeBytes <= 0L) {
                    continue
                }
                val modifiedMs = it.getLong(modifiedIndex) * 1000L
                val sourceId = "media:$mediaId"
                val sourceFingerprint = "$deviceId|$sourceId|$sizeBytes|$modifiedMs"
                items += BackupMediaItem(
                    sourceId = sourceId,
                    sourceFingerprint = sourceFingerprint,
                    contentUri = ContentUris.withAppendedId(collection, mediaId),
                    displayName = displayName,
                    sizeBytes = sizeBytes,
                    modifiedMs = modifiedMs,
                    mimeType = it.getString(mimeTypeIndex),
                    extension = resolveExtension(displayName),
                )
            }
        }

        Log.i(BACKUP_WORKER_TAG, "MediaStore scan finished: discovered=${items.size}")
        return items
    }

    private fun resolveExtension(displayName: String): String {
        val dotIndex = displayName.lastIndexOf('.')
        if (dotIndex < 0 || dotIndex == displayName.lastIndex) {
            return ""
        }
        return displayName.substring(dotIndex).lowercase()
    }
}

private class BackupMediaAccessException(
    message: String,
    cause: Throwable? = null,
) : IllegalStateException(message, cause)

private data class BackupPreflightDecision(
    val id: String,
    val action: String,
    val relativePath: String,
)

private class BackupHttpClient(
    private val config: BackupPlanConfig,
    private val contentResolver: android.content.ContentResolver,
) {
    private val httpClient: OkHttpClient by lazy { buildClient() }
    private var bearerAuthHeader: String? = null

    fun computeContentHash(contentUri: Uri): String {
        val digest = MessageDigest.getInstance("SHA-256")
        contentResolver.openInputStream(contentUri).use { input ->
            requireNotNull(input) { "无法读取媒体内容: $contentUri" }
            val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
            while (true) {
                val read = input.read(buffer)
                if (read <= 0) {
                    break
                }
                digest.update(buffer, 0, read)
            }
        }
        return digest.digest().joinToString("") { byte -> "%02x".format(byte) }
    }

    fun preflight(rootId: String, items: List<PreparedBackupItem>): List<BackupPreflightDecision> {
        val payload = JSONObject()
        payload.put("rootId", rootId)
        val rawItems = JSONArray()
        for (item in items) {
            val json = JSONObject()
            json.put("id", item.item.sourceFingerprint)
            json.put("sourceFingerprint", item.item.sourceFingerprint)
            if (!item.contentHash.isNullOrBlank()) {
                json.put("contentHash", item.contentHash)
            }
            json.put("extension", item.item.extension)
            json.put("sizeBytes", item.item.sizeBytes)
            json.put("modifiedMs", item.item.modifiedMs)
            json.put("mimeType", item.item.mimeType)
            rawItems.put(json)
        }
        payload.put("items", rawItems)

        try {
            val requestFactory = { authHeader: String ->
                Request.Builder()
                    .url("${config.serverUrl.trimEnd('/')}/api/v1/backup/preflight")
                    .post(payload.toString().toRequestBody("application/json; charset=utf-8".toMediaTypeOrNull()))
                    .header("Authorization", authHeader)
                    .header("Accept", "application/json")
                    .header("Content-Type", "application/json")
                    .header("X-NAS-Device-Id", config.deviceId)
                    .header("X-NAS-Device-Name", config.deviceName)
                    .build()
            }
            Log.d(
                BACKUP_WORKER_TAG,
                "Preflight request started: url=${config.serverUrl.trimEnd('/')}/api/v1/backup/preflight, itemCount=${items.size}",
            )
            executeAuthorized(requestFactory).use { response ->
                if (!response.isSuccessful) {
                    throw IllegalStateException("预检请求失败: HTTP ${response.code}")
                }
                val body = response.body?.string().orEmpty()
                val json = JSONObject(body)
                val result = mutableListOf<BackupPreflightDecision>()
                val rawResponseItems = json.optJSONArray("items") ?: JSONArray()
                for (index in 0 until rawResponseItems.length()) {
                    val entry = rawResponseItems.optJSONObject(index) ?: continue
                    result += BackupPreflightDecision(
                        id = entry.optString("id"),
                        action = entry.optString("action", "upload"),
                        relativePath = entry.optString("relativePath", "/"),
                    )
                }
                Log.d(BACKUP_WORKER_TAG, "Preflight request finished: decisions=${result.size}")
                return result
            }
        } catch (error: Exception) {
            Log.e(BACKUP_WORKER_TAG, "Preflight request failed", error)
            throw error
        }
    }

    fun upload(
        item: BackupMediaItem,
        rootId: String,
        relativePath: String,
        metadataHeader: String,
        isCancelled: () -> Boolean = { false },
    ) {
        val requestFactory = { authHeader: String ->
            Request.Builder()
                .url(buildWebdavUploadUrl(rootId, relativePath))
                .put(
                    object : RequestBody() {
                        override fun contentType() = item.mimeType?.toMediaTypeOrNull()

                        override fun contentLength(): Long = item.sizeBytes

                        override fun writeTo(sink: BufferedSink) {
                            contentResolver.openInputStream(item.contentUri).use { input ->
                                requireNotNull(input) { "无法读取媒体内容: ${item.contentUri}" }
                                val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                                while (true) {
                                    throwIfBackupCancelled(isCancelled)
                                    val read = input.read(buffer)
                                    if (read <= 0) {
                                        break
                                    }
                                    sink.write(buffer, 0, read)
                                }
                            }
                        }
                    },
                )
                .header("Authorization", authHeader)
                .header("X-NAS-Device-Id", config.deviceId)
                .header("X-NAS-Device-Name", config.deviceName)
                .header("X-NAS-Backup-Metadata", metadataHeader)
                .build()
        }

        executeAuthorized(requestFactory).use { response ->
            if (!response.isSuccessful) {
                throw IllegalStateException("上传失败: HTTP ${response.code}")
            }
        }
    }

    private fun executeAuthorized(requestFactory: (String) -> Request): okhttp3.Response {
        var authHeader = requireBearerAuthHeader()
        var response = httpClient.newCall(requestFactory(authHeader)).execute()
        if (response.code == 401) {
            response.close()
            authHeader = requireBearerAuthHeader(forceRefresh = true)
            response = httpClient.newCall(requestFactory(authHeader)).execute()
        }
        return response
    }

    private fun requireBearerAuthHeader(forceRefresh: Boolean = false): String {
        if (!forceRefresh) {
            bearerAuthHeader?.let { return it }
        }

        if (!forceRefresh && config.accessToken.trim().isNotEmpty()) {
            return "Bearer ${config.accessToken.trim()}".also { bearerAuthHeader = it }
        }

        val payload = JSONObject(mapOf("refreshToken" to config.refreshToken))
        val request = Request.Builder()
            .url("${config.serverUrl.trimEnd('/')}/api/v1/auth/device/refresh")
            .post(payload.toString().toRequestBody("application/json; charset=utf-8".toMediaTypeOrNull()))
            .header("Accept", "application/json")
            .header("Content-Type", "application/json")
            .header("X-NAS-Device-Id", config.deviceId)
            .header("X-NAS-Device-Name", config.deviceName)
            .build()

        Log.d(BACKUP_WORKER_TAG, "Device token refresh started: url=${request.url}")
        httpClient.newCall(request).execute().use { response ->
            if (!response.isSuccessful) {
                throw IllegalStateException("刷新设备会话失败: HTTP ${response.code}")
            }
            val json = JSONObject(response.body?.string().orEmpty())
            val accessToken = json.optString("accessToken").trim()
            if (accessToken.isEmpty()) {
                throw IllegalStateException("刷新设备会话失败: 服务端未返回 accessToken")
            }
            val tokenType = json.optString("tokenType").trim().ifEmpty { "Bearer" }
            return "$tokenType $accessToken".also { bearerAuthHeader = it }
        }
    }

    private fun buildClient(): OkHttpClient {
        val certificateFactory = CertificateFactory.getInstance("X.509")
        val keyStore = KeyStore.getInstance(KeyStore.getDefaultType()).apply {
            load(null, null)
        }
        val certificates = certificateFactory.generateCertificates(
            ByteArrayInputStream(config.rootCaPem.toByteArray(Charsets.UTF_8)),
        )
        require(certificates.isNotEmpty()) { "缺少服务端根证书" }
        certificates.forEachIndexed { index, certificate ->
            keyStore.setCertificateEntry("nas-root-$index", certificate)
        }
        val trustManagerFactory = TrustManagerFactory.getInstance(
            TrustManagerFactory.getDefaultAlgorithm(),
        ).apply {
            init(keyStore)
        }
        val trustManager = trustManagerFactory.trustManagers
            .firstOrNull { it is X509TrustManager } as? X509TrustManager
            ?: throw IllegalStateException("缺少 X509TrustManager")
        val sslContext = SSLContext.getInstance("TLS").apply {
            init(null, arrayOf<TrustManager>(trustManager), SecureRandom())
        }
        val expectedHost = Uri.parse(config.serverUrl).host
        val pinnedLeafSha256 = config.leafSha256?.trim()?.lowercase()

        return OkHttpClient.Builder()
            .connectTimeout(30, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.MINUTES)
            .writeTimeout(30, TimeUnit.MINUTES)
            .sslSocketFactory(sslContext.socketFactory, trustManager)
            .hostnameVerifier { hostname, session ->
                val verificationHost = expectedHost?.ifBlank { hostname } ?: hostname
                if (
                    HttpsURLConnection.getDefaultHostnameVerifier().verify(
                        verificationHost,
                        session,
                    )
                ) {
                    true
                } else if (!pinnedLeafSha256.isNullOrEmpty()) {
                    val presentedLeafSha256 = session.peerCertificates
                        .firstOrNull()
                        ?.let(::calculateCertificateSha256)
                    val matched = presentedLeafSha256 == pinnedLeafSha256
                    if (!matched) {
                        Log.e(
                            BACKUP_WORKER_TAG,
                            "Hostname verification failed and pinned leaf mismatch: expectedHost=$verificationHost, presentedLeaf=$presentedLeafSha256",
                        )
                    }
                    matched
                } else {
                    Log.e(
                        BACKUP_WORKER_TAG,
                        "Hostname verification failed: expectedHost=$verificationHost, requestedHost=$hostname",
                    )
                    false
                }
            }
            .build()
    }

    private fun calculateCertificateSha256(certificate: Certificate): String {
        return MessageDigest.getInstance("SHA-256")
            .digest(certificate.encoded)
            .joinToString("") { byte -> "%02x".format(byte) }
    }

    private fun buildWebdavUploadUrl(rootId: String, relativePath: String): String {
        val prefix = when (rootId) {
            "library" -> "/dav/library"
            else -> "/dav/fs"
        }
        val normalizedPath = if (relativePath.startsWith("/")) relativePath else "/$relativePath"
        val baseUri = Uri.parse(config.serverUrl)
        val combinedPath = "$prefix$normalizedPath"
        return URI(
            baseUri.scheme,
            requireNotNull(baseUri.encodedAuthority) { "缺少服务端地址" },
            combinedPath,
            null,
            null,
        ).toASCIIString()
    }
}

private class BackupNativeDatabase(context: Context) {
    private val syncStore = BackupWorkerStateStore(context)
    private val assetDatabase = BackupWorkerAssetDatabase(context)

    fun insertRun(
        runId: String,
        planId: String,
        triggerType: String,
        status: String,
        startedAtMillis: Long,
    ) {
        syncStore.insertRun(runId, planId, triggerType, status, startedAtMillis)
    }

    fun completeRun(
        runId: String,
        status: String,
        scannedCount: Int,
        queuedCount: Int,
        skippedCount: Int,
        failedCount: Int,
        finishedAtMillis: Long,
        errorMessage: String?,
    ) {
        syncStore.completeRun(
            runId = runId,
            status = status,
            scannedCount = scannedCount,
            queuedCount = queuedCount,
            skippedCount = skippedCount,
            failedCount = failedCount,
            finishedAtMillis = finishedAtMillis,
            errorMessage = errorMessage,
        )
    }

    fun updateRunStatus(
        runId: String,
        status: String,
        errorMessage: String?,
        progressMessage: String? = null,
    ) {
        syncStore.updateRunStatus(runId, status, errorMessage, progressMessage)
    }

    fun updateRunProgress(
        runId: String,
        progress: BackupExecutionProgress,
    ) {
        syncStore.updateRunProgress(
            runId = runId,
            progressMessage = progress.message,
            processedCount = progress.processedCount,
            totalCount = progress.totalCount,
            uploadedCount = progress.uploadedCount,
            skippedCount = progress.skippedCount,
            failedCount = progress.failedCount,
        )
    }

    fun loadRunStartedAtMillis(runId: String): Long? {
        return syncStore.loadRunStartedAtMillis(runId)
    }

    fun updatePlanLastRun(planId: String, timestampMillis: Long) {
        syncStore.updatePlanLastRun(planId, timestampMillis)
    }

    fun disablePlan(planId: String) {
        syncStore.setPlanEnabled(planId, false)
    }

    fun updatePlanScheduleState(
        planId: String,
        scheduleStatus: String,
        scheduledRunAtMillis: Long?,
        scheduleError: String?,
    ) {
        syncStore.updatePlanScheduleState(planId, scheduleStatus, scheduledRunAtMillis, scheduleError)
    }

    fun loadAssetStates(
        serverId: String,
        rootId: String,
        sourceFingerprints: List<String>,
    ): Map<String, String> {
        return assetDatabase.loadAssetStates(serverId, rootId, sourceFingerprints)
    }

    fun upsertAssetStates(states: List<BackupAssetStateRecord>) {
        assetDatabase.upsertAssetStates(states)
    }
}

data class BackupAssetStateRecord(
    val serverId: String,
    val rootId: String,
    val sourceFingerprint: String,
    val sourceId: String,
    val displayName: String,
    val localPath: String,
    val sizeBytes: Long,
    val modifiedMs: Long,
    val mimeType: String?,
    val contentHash: String,
    val remotePath: String,
    val updatedAtMillis: Long,
)

private fun isDeviceCharging(context: Context): Boolean {
    val intent = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
    val status = intent?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
    return status == BatteryManager.BATTERY_STATUS_CHARGING ||
        status == BatteryManager.BATTERY_STATUS_FULL
}

private fun Exception.isRetryableFailure(): Boolean {
    val rawMessage = message.orEmpty()
    val httpStatus = Regex("""HTTP\s+(\d{3})""")
        .find(rawMessage)
        ?.groupValues
        ?.getOrNull(1)
        ?.toIntOrNull()
    if (httpStatus != null) {
        if (httpStatus == 408 || httpStatus == 429) {
            return true
        }
        if (httpStatus in 400..499) {
            return false
        }
    }
    return !rawMessage.contains("无法读取媒体内容") &&
        !rawMessage.contains("缺少服务端根证书") &&
        !rawMessage.contains("缺少 X509TrustManager") &&
        !rawMessage.contains("服务端未返回 accessToken")
}
