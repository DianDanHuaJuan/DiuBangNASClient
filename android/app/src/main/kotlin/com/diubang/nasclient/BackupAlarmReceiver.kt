package com.diubang.nasclient

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.Data
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import java.util.concurrent.TimeUnit

class BackupAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val planId = intent.getStringExtra(EXTRA_PLAN_ID)
            ?: return
        val scheduledRunAtMillis = intent.getLongExtra(EXTRA_SCHEDULED_RUN_AT_MILLIS, System.currentTimeMillis())

        val configStore = BackupPlanConfigStore(context.applicationContext)
        val config = configStore.load(planId) ?: run {
            Log.w(TAG, "Alarm fired but config not found for planId=$planId")
            return
        }

        Log.i(TAG, "Alarm fired for planId=$planId, enqueuing worker immediately")

        val constraints = Constraints.Builder()
            .setRequiredNetworkType(
                if (config.requiresWifi) {
                    NetworkType.UNMETERED
                } else {
                    NetworkType.CONNECTED
                },
            )
            .setRequiresStorageNotLow(true)
            .build()

        val request = OneTimeWorkRequestBuilder<BackupExecutionWorker>()
            .setInputData(
                Data.Builder()
                    .putString(BackupSchedulerManager.INPUT_PLAN_ID_KEY, planId)
                    .putLong(
                        BackupSchedulerManager.INPUT_SCHEDULED_RUN_AT_MILLIS_KEY,
                        scheduledRunAtMillis,
                    )
                    .putBoolean("requiresCharging", config.requiresCharging)
                    .build(),
            )
            .setConstraints(constraints)
            .setBackoffCriteria(BackoffPolicy.LINEAR, 1, TimeUnit.MINUTES)
            .addTag(uniqueWorkName(planId))
            .build()

        WorkManager.getInstance(context.applicationContext)
            .enqueueUniqueWork(
                uniqueWorkName(planId),
                ExistingWorkPolicy.KEEP,
                request,
            )
    }

    companion object {
        private const val TAG = "BackupAlarmReceiver"
        private const val EXTRA_PLAN_ID = "planId"
        private const val EXTRA_SCHEDULED_RUN_AT_MILLIS = "scheduledRunAtMillis"

        fun createPendingIntent(context: Context, planId: String, scheduledRunAtMillis: Long): PendingIntent {
            val intent = Intent(context, BackupAlarmReceiver::class.java).apply {
                putExtra(EXTRA_PLAN_ID, planId)
                putExtra(EXTRA_SCHEDULED_RUN_AT_MILLIS, scheduledRunAtMillis)
            }
            return PendingIntent.getBroadcast(
                context,
                alarmRequestCode(planId),
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        fun findExistingPendingIntent(context: Context, planId: String): PendingIntent? {
            val intent = Intent(context, BackupAlarmReceiver::class.java)
            return PendingIntent.getBroadcast(
                context,
                alarmRequestCode(planId),
                intent,
                PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        private fun uniqueWorkName(planId: String): String {
            return BackupSchedulerManager.uniqueWorkName(planId)
        }

        private fun alarmRequestCode(planId: String): Int {
            return (planId + "_alarm").hashCode()
        }
    }
}
