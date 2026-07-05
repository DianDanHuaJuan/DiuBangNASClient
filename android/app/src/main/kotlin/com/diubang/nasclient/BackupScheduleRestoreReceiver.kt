package com.diubang.nasclient

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class BackupScheduleRestoreReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action.orEmpty()
        if (
            action != Intent.ACTION_BOOT_COMPLETED &&
            action != Intent.ACTION_MY_PACKAGE_REPLACED &&
            action != Intent.ACTION_TIME_CHANGED &&
            action != Intent.ACTION_TIMEZONE_CHANGED
        ) {
            return
        }

        val result = goAsync()
        try {
            val manager = BackupSchedulerManager(context.applicationContext)
            val restoreResults = manager.restoreAllPlans()
            Log.i(
                TAG,
                "Restored ${restoreResults.size} backup plans after broadcast=$action",
            )
        } catch (error: Exception) {
            Log.e(TAG, "Failed to restore backup plans after broadcast=$action", error)
        } finally {
            result.finish()
        }
    }

    companion object {
        private const val TAG = "BackupScheduleRestore"
    }
}
