package com.diubang.nasclient

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

class BackupWorkerStateStore(context: Context) {
    private val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun insertRun(
        runId: String,
        planId: String,
        triggerType: String,
        status: String,
        startedAtMillis: Long,
    ) {
        val now = System.currentTimeMillis()
        prefs.edit()
            .putLong(runStartedAtKey(runId), startedAtMillis)
            .apply()
        upsertRun(runId) { current ->
            (current ?: BackupWorkerRunState(id = runId, startedAtMillis = startedAtMillis)).copy(
                planId = planId,
                triggerType = triggerType,
                status = status,
                startedAtMillis = startedAtMillis,
                finishedAtMillis = null,
                errorMessage = null,
                progressMessage = null,
                updatedAtMillis = now,
            )
        }
    }

    fun updateRunStatus(
        runId: String,
        status: String,
        errorMessage: String?,
        progressMessage: String? = null,
    ) {
        val now = System.currentTimeMillis()
        upsertRun(runId) { current ->
            (current ?: BackupWorkerRunState(id = runId)).copy(
                status = status,
                errorMessage = errorMessage,
                progressMessage = progressMessage ?: current?.progressMessage,
                updatedAtMillis = now,
            )
        }
    }

    fun updateRunProgress(
        runId: String,
        progressMessage: String,
        processedCount: Int? = null,
        totalCount: Int? = null,
        uploadedCount: Int? = null,
        skippedCount: Int? = null,
        failedCount: Int? = null,
    ) {
        val now = System.currentTimeMillis()
        upsertRun(runId) { current ->
            (current ?: BackupWorkerRunState(id = runId)).copy(
                progressMessage = progressMessage,
                processedCount = processedCount ?: current?.processedCount,
                totalCount = totalCount ?: current?.totalCount,
                queuedCount = uploadedCount ?: current?.queuedCount ?: 0,
                skippedCount = skippedCount ?: current?.skippedCount ?: 0,
                failedCount = failedCount ?: current?.failedCount ?: 0,
                updatedAtMillis = now,
            )
        }
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
        val now = System.currentTimeMillis()
        upsertRun(runId) { current ->
            (current ?: BackupWorkerRunState(id = runId)).copy(
                status = status,
                scannedCount = scannedCount,
                queuedCount = queuedCount,
                skippedCount = skippedCount,
                failedCount = failedCount,
                finishedAtMillis = finishedAtMillis,
                errorMessage = errorMessage,
                progressMessage = errorMessage ?: current?.progressMessage,
                updatedAtMillis = now,
            )
        }
        prefs.edit().remove(runStartedAtKey(runId)).apply()
    }

    fun loadRunStartedAtMillis(runId: String): Long? {
        return if (prefs.contains(runStartedAtKey(runId))) {
            prefs.getLong(runStartedAtKey(runId), 0L)
        } else {
            null
        }
    }

    fun updatePlanLastRun(planId: String, timestampMillis: Long) {
        upsertPlan(planId) { current ->
            (current ?: BackupWorkerPlanState(planId = planId)).copy(
                lastRunAtMillis = timestampMillis,
            )
        }
    }

    fun updatePlanScheduleState(
        planId: String,
        scheduleStatus: String,
        scheduledRunAtMillis: Long?,
        scheduleError: String?,
    ) {
        upsertPlan(planId) { current ->
            (current ?: BackupWorkerPlanState(planId = planId)).copy(
                scheduleStatus = scheduleStatus,
                scheduledRunAtMillis = scheduledRunAtMillis,
                scheduleErrorMessage = scheduleError,
            )
        }
    }

    fun setPlanEnabled(planId: String, enabled: Boolean) {
        upsertPlan(planId) { current ->
            (current ?: BackupWorkerPlanState(planId = planId)).copy(enabled = enabled)
        }
    }

    fun snapshotMap(): Map<String, Any?> {
        return mapOf(
            "plans" to loadPlans().map { it.toMap() },
            "runs" to loadRuns().map { it.toMap() },
        )
    }

    fun markPlanRunStopping(planId: String, message: String): Boolean {
        val runs = loadRuns()
        val index = runs.indexOfFirst { run ->
            run.planId == planId && run.status in ACTIVE_RUN_STATUSES
        }
        if (index < 0) {
            return false
        }
        runs[index] = runs[index].copy(
            status = "stopping",
            progressMessage = message,
            updatedAtMillis = System.currentTimeMillis(),
        )
        saveRuns(runs.take(MAX_RUN_RECORDS))
        return true
    }

    fun markUserStopRequested(planId: String) {
        prefs.edit().putBoolean(userStopKey(planId), true).apply()
    }

    fun clearUserStopRequested(planId: String) {
        prefs.edit().remove(userStopKey(planId)).apply()
    }

    fun isUserStopRequested(planId: String): Boolean {
        return prefs.getBoolean(userStopKey(planId), false)
    }

    private fun upsertPlan(
        planId: String,
        update: (BackupWorkerPlanState?) -> BackupWorkerPlanState,
    ) {
        val plans = loadPlans()
        val index = plans.indexOfFirst { it.planId == planId }
        val current = plans.getOrNull(index)
        val updated = update(current)
        if (index >= 0) {
            plans[index] = updated
        } else {
            plans += updated
        }
        savePlans(plans)
    }

    private fun upsertRun(
        runId: String,
        update: (BackupWorkerRunState?) -> BackupWorkerRunState,
    ) {
        val runs = loadRuns()
        val index = runs.indexOfFirst { it.id == runId }
        val current = runs.getOrNull(index)
        val updated = update(current)
        if (index >= 0) {
            runs[index] = updated
        } else {
            runs += updated
        }
        runs.sortByDescending { it.startedAtMillis }
        saveRuns(runs.take(MAX_RUN_RECORDS))
    }

    private fun loadPlans(): MutableList<BackupWorkerPlanState> {
        return parseArray(prefs.getString(PLANS_KEY, null)) { raw ->
            BackupWorkerPlanState.fromJson(raw)
        }
    }

    private fun savePlans(plans: List<BackupWorkerPlanState>) {
        val array = JSONArray()
        plans.forEach { plan ->
            array.put(plan.toJson())
        }
        prefs.edit().putString(PLANS_KEY, array.toString()).apply()
    }

    private fun loadRuns(): MutableList<BackupWorkerRunState> {
        return parseArray(prefs.getString(RUNS_KEY, null)) { raw ->
            BackupWorkerRunState.fromJson(raw)
        }
    }

    private fun saveRuns(runs: List<BackupWorkerRunState>) {
        val array = JSONArray()
        runs.forEach { run ->
            array.put(run.toJson())
        }
        prefs.edit().putString(RUNS_KEY, array.toString()).apply()
    }

    private fun <T> parseArray(
        raw: String?,
        convert: (JSONObject) -> T?,
    ): MutableList<T> {
        if (raw.isNullOrBlank()) {
            return mutableListOf()
        }
        return try {
            val array = JSONArray(raw)
            val values = mutableListOf<T>()
            for (index in 0 until array.length()) {
                val entry = array.optJSONObject(index) ?: continue
                convert(entry)?.let(values::add)
            }
            values
        } catch (_: Exception) {
            mutableListOf()
        }
    }

    private fun runStartedAtKey(runId: String): String = "run_started_${sanitizeBackupWorkerKey(runId)}"

    private fun userStopKey(planId: String): String = "user_stop_${sanitizeBackupWorkerKey(planId)}"

    companion object {
        private const val PREFS_NAME = "backup_worker_state"
        private const val PLANS_KEY = "plans"
        private const val RUNS_KEY = "runs"
        private const val MAX_RUN_RECORDS = 50
        private val ACTIVE_RUN_STATUSES = setOf("running", "retrying", "stopping")
    }
}

class BackupWorkerAssetDatabase(context: Context) {
    private val databasePath = context.getDatabasePath("nas_client_backup_worker.db").path

    fun loadAssetStates(
        serverId: String,
        rootId: String,
        sourceFingerprints: List<String>,
    ): Map<String, String> {
        if (sourceFingerprints.isEmpty()) {
            return emptyMap()
        }
        val result = mutableMapOf<String, String>()
        openDatabase().use { db ->
            for (chunk in sourceFingerprints.chunked(200)) {
                val placeholders = chunk.joinToString(",") { "?" }
                val args = arrayOf(serverId, rootId, *chunk.toTypedArray())
                val cursor = db.rawQuery(
                    """
                    SELECT source_fingerprint, content_hash
                    FROM backup_asset_state
                    WHERE server_id = ? AND root_id = ? AND source_fingerprint IN ($placeholders)
                    """.trimIndent(),
                    args,
                )
                cursor.use {
                    while (it.moveToNext()) {
                        result[it.getString(0)] = it.getString(1)
                    }
                }
            }
        }
        return result
    }

    fun upsertAssetStates(states: List<BackupAssetStateRecord>) {
        if (states.isEmpty()) {
            return
        }
        openDatabase().use { db ->
            db.beginTransaction()
            try {
                for (state in states) {
                    val values = ContentValues().apply {
                        put("server_id", state.serverId)
                        put("root_id", state.rootId)
                        put("source_fingerprint", state.sourceFingerprint)
                        put("source_id", state.sourceId)
                        put("display_name", state.displayName)
                        put("local_path", state.localPath)
                        put("size_bytes", state.sizeBytes)
                        put("modified_ms", state.modifiedMs)
                        put("mime_type", state.mimeType)
                        put("content_hash", state.contentHash)
                        put("remote_path", state.remotePath)
                        put("updated_at", backupWorkerIso8601(state.updatedAtMillis))
                    }
                    db.insertWithOnConflict(
                        "backup_asset_state",
                        null,
                        values,
                        SQLiteDatabase.CONFLICT_REPLACE,
                    )
                }
                db.setTransactionSuccessful()
            } finally {
                db.endTransaction()
            }
        }
    }

    private fun openDatabase(): SQLiteDatabase {
        val databaseFile = File(databasePath)
        databaseFile.parentFile?.mkdirs()
        val db = SQLiteDatabase.openOrCreateDatabase(databaseFile, null)
        ensureSchema(db)
        return db
    }

    private fun ensureSchema(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS backup_asset_state (
              server_id TEXT NOT NULL,
              root_id TEXT NOT NULL,
              source_fingerprint TEXT PRIMARY KEY,
              source_id TEXT NOT NULL,
              display_name TEXT NOT NULL,
              local_path TEXT NOT NULL,
              size_bytes INTEGER NOT NULL,
              modified_ms INTEGER NOT NULL,
              mime_type TEXT,
              content_hash TEXT NOT NULL,
              remote_path TEXT NOT NULL,
              updated_at TEXT NOT NULL
            )
            """.trimIndent(),
        )
        db.execSQL(
            """
            CREATE INDEX IF NOT EXISTS idx_backup_asset_state_server_root
            ON backup_asset_state(server_id, root_id, updated_at DESC)
            """.trimIndent(),
        )
    }
}

private data class BackupWorkerPlanState(
    val planId: String,
    val enabled: Boolean = true,
    val lastRunAtMillis: Long? = null,
    val scheduleStatus: String = "unscheduled",
    val scheduledRunAtMillis: Long? = null,
    val scheduleErrorMessage: String? = null,
) {
    fun toJson(): JSONObject {
        return JSONObject().apply {
            put("planId", planId)
            put("enabled", enabled)
            put("lastRunAtMillis", lastRunAtMillis)
            put("scheduleStatus", scheduleStatus)
            put("scheduledRunAtMillis", scheduledRunAtMillis)
            put("scheduleErrorMessage", scheduleErrorMessage)
        }
    }

    fun toMap(): Map<String, Any?> {
        return mapOf(
            "planId" to planId,
            "enabled" to enabled,
            "lastRunAtMillis" to lastRunAtMillis,
            "scheduleStatus" to scheduleStatus,
            "scheduledRunAtMillis" to scheduledRunAtMillis,
            "scheduleErrorMessage" to scheduleErrorMessage,
        )
    }

    companion object {
        fun fromJson(json: JSONObject): BackupWorkerPlanState? {
            val planId = json.optString("planId").trim()
            if (planId.isEmpty()) {
                return null
            }
            return BackupWorkerPlanState(
                planId = planId,
                enabled = json.optBoolean("enabled", true),
                lastRunAtMillis = json.optNullableLong("lastRunAtMillis"),
                scheduleStatus = json.optString("scheduleStatus", "unscheduled"),
                scheduledRunAtMillis = json.optNullableLong("scheduledRunAtMillis"),
                scheduleErrorMessage = json.optString("scheduleErrorMessage").ifBlank { null },
            )
        }
    }
}

private data class BackupWorkerRunState(
    val id: String,
    val planId: String? = null,
    val triggerType: String = "scheduled",
    val status: String = "running",
    val scannedCount: Int = 0,
    val queuedCount: Int = 0,
    val skippedCount: Int = 0,
    val failedCount: Int = 0,
    val processedCount: Int? = null,
    val totalCount: Int? = null,
    val startedAtMillis: Long = System.currentTimeMillis(),
    val finishedAtMillis: Long? = null,
    val errorMessage: String? = null,
    val progressMessage: String? = null,
    val updatedAtMillis: Long = System.currentTimeMillis(),
) {
    fun toJson(): JSONObject {
        return JSONObject().apply {
            put("id", id)
            put("planId", planId)
            put("triggerType", triggerType)
            put("status", status)
            put("scannedCount", scannedCount)
            put("queuedCount", queuedCount)
            put("skippedCount", skippedCount)
            put("failedCount", failedCount)
            put("processedCount", processedCount)
            put("totalCount", totalCount)
            put("startedAtMillis", startedAtMillis)
            put("finishedAtMillis", finishedAtMillis)
            put("errorMessage", errorMessage)
            put("progressMessage", progressMessage)
            put("updatedAtMillis", updatedAtMillis)
        }
    }

    fun toMap(): Map<String, Any?> {
        return mapOf(
            "id" to id,
            "planId" to planId,
            "triggerType" to triggerType,
            "status" to status,
            "scannedCount" to scannedCount,
            "queuedCount" to queuedCount,
            "skippedCount" to skippedCount,
            "failedCount" to failedCount,
            "processedCount" to processedCount,
            "totalCount" to totalCount,
            "startedAtMillis" to startedAtMillis,
            "finishedAtMillis" to finishedAtMillis,
            "errorMessage" to errorMessage,
            "progressMessage" to progressMessage,
            "updatedAtMillis" to updatedAtMillis,
        )
    }

    companion object {
        fun fromJson(json: JSONObject): BackupWorkerRunState? {
            val id = json.optString("id").trim()
            if (id.isEmpty()) {
                return null
            }
            return BackupWorkerRunState(
                id = id,
                planId = json.optString("planId").ifBlank { null },
                triggerType = json.optString("triggerType", "scheduled"),
                status = json.optString("status", "running"),
                scannedCount = json.optInt("scannedCount", 0),
                queuedCount = json.optInt("queuedCount", 0),
                skippedCount = json.optInt("skippedCount", 0),
                failedCount = json.optInt("failedCount", 0),
                processedCount = json.optNullableInt("processedCount"),
                totalCount = json.optNullableInt("totalCount"),
                startedAtMillis = json.optLong("startedAtMillis", System.currentTimeMillis()),
                finishedAtMillis = json.optNullableLong("finishedAtMillis"),
                errorMessage = json.optString("errorMessage").ifBlank { null },
                progressMessage = json.optString("progressMessage").ifBlank { null },
                updatedAtMillis = json.optLong("updatedAtMillis", System.currentTimeMillis()),
            )
        }
    }
}

private fun JSONObject.optNullableLong(key: String): Long? {
    return if (has(key) && !isNull(key)) {
        optLong(key)
    } else {
        null
    }
}

private fun JSONObject.optNullableInt(key: String): Int? {
    return if (has(key) && !isNull(key)) {
        optInt(key)
    } else {
        null
    }
}

private fun sanitizeBackupWorkerKey(value: String): String {
    return value.replace(Regex("[^A-Za-z0-9_-]"), "_")
}

private fun backupWorkerIso8601(timestampMillis: Long): String {
    val formatter = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US)
    formatter.timeZone = TimeZone.getTimeZone("UTC")
    return formatter.format(Date(timestampMillis))
}
