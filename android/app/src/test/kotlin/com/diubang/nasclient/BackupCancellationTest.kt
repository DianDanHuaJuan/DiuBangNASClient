package com.diubang.nasclient

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test
import java.util.Calendar
import java.util.concurrent.atomic.AtomicBoolean

class BackupCancellationTest {
    @Test
    fun `throwIfBackupCancelled throws when cancelled`() {
        val cancelled = AtomicBoolean(true)

        val error = assertThrows(CancellationException::class.java) {
            throwIfBackupCancelled { cancelled.get() }
        }

        assertEquals("Backup cancelled by user", error.message)
    }

    @Test
    fun `throwIfBackupCancelled does nothing when active`() {
        throwIfBackupCancelled { false }
    }

    @Test
    fun `next run after user stop defers to next daily cycle`() {
        val stoppedAt = localMillis(2026, Calendar.JANUARY, 1, 10, 30, 1)
        val config = testConfig(scheduleType = "daily", hour = 9, minute = 0)

        val nextRunAt = BackupScheduleCalculator.nextRunAt(config, stoppedAt)

        assertEquals(localMillis(2026, Calendar.JANUARY, 2, 9, 0), nextRunAt)
    }

    private fun testConfig(
        scheduleType: String,
        hour: Int,
        minute: Int,
        weekday: Int? = null,
        dayOfMonth: Int? = null,
        onceAtMillis: Long? = null,
    ): BackupPlanConfig {
        return BackupPlanConfig(
            planId = "plan-1",
            planName = "Test Plan",
            serverId = "server-1",
            serverUrl = "https://example.com",
            rootId = "fs",
            accessToken = "token",
            refreshToken = "refresh",
            deviceId = "device-1",
            deviceName = "Test Device",
            includeImages = true,
            includeVideos = true,
            scheduleType = scheduleType,
            hour = hour,
            minute = minute,
            weekday = weekday,
            dayOfMonth = dayOfMonth,
            onceAtMillis = onceAtMillis,
            requiresWifi = false,
            requiresCharging = false,
            rootCaPem = "pem",
            leafSha256 = null,
        )
    }

    private fun localMillis(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        second: Int = 0,
    ): Long {
        return Calendar.getInstance().apply {
            set(Calendar.YEAR, year)
            set(Calendar.MONTH, month)
            set(Calendar.DAY_OF_MONTH, day)
            set(Calendar.HOUR_OF_DAY, hour)
            set(Calendar.MINUTE, minute)
            set(Calendar.SECOND, second)
            set(Calendar.MILLISECOND, 0)
        }.timeInMillis
    }
}
