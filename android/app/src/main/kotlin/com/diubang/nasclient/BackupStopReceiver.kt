package com.diubang.nasclient

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class BackupStopReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val planId = intent.getStringExtra(EXTRA_PLAN_ID)?.trim().orEmpty()
        if (planId.isEmpty()) {
            return
        }

        Log.i(TAG, "Stop backup requested from notification for planId=$planId")
        BackupSchedulerManager(context.applicationContext).stopCurrentRun(planId)
    }

    companion object {
        private const val TAG = "BackupStopReceiver"
        private const val EXTRA_PLAN_ID = "planId"

        fun createPendingIntent(context: Context, planId: String): PendingIntent {
            val intent = Intent(context, BackupStopReceiver::class.java).apply {
                putExtra(EXTRA_PLAN_ID, planId)
            }
            return PendingIntent.getBroadcast(
                context,
                stopRequestCode(planId),
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        private fun stopRequestCode(planId: String): Int {
            return (planId + "_stop").hashCode()
        }
    }
}
