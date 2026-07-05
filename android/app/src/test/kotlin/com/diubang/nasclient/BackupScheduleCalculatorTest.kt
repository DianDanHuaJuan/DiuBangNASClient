package com.diubang.nasclient

import org.junit.Assert.assertEquals
import org.junit.Test
import java.util.Calendar

class BackupScheduleCalculatorTest {
    @Test
    fun `daily schedule rolls to same day when time not passed`() {
        val reference = localMillis(2026, Calendar.JANUARY, 1, 20, 15)
        val config = testConfig(scheduleType = "daily", hour = 22, minute = 30)

        val nextRunAt = BackupScheduleCalculator.nextRunAt(config, reference)

        assertEquals(localMillis(2026, Calendar.JANUARY, 1, 22, 30), nextRunAt)
    }

    @Test
    fun `weekly schedule targets selected weekday`() {
        val reference = localMillis(2026, Calendar.JANUARY, 5, 10, 30)
        val config = testConfig(
            scheduleType = "weekly",
            hour = 9,
            minute = 0,
            weekday = 5,
        )

        val nextRunAt = BackupScheduleCalculator.nextRunAt(config, reference)

        assertEquals(localMillis(2026, Calendar.JANUARY, 9, 9, 0), nextRunAt)
    }

    @Test
    fun `monthly schedule clamps to shorter month last day`() {
        val reference = localMillis(2026, Calendar.FEBRUARY, 1, 8, 0)
        val config = testConfig(
            scheduleType = "monthly",
            hour = 7,
            minute = 15,
            dayOfMonth = 31,
        )

        val nextRunAt = BackupScheduleCalculator.nextRunAt(config, reference)

        assertEquals(localMillis(2026, Calendar.FEBRUARY, 28, 7, 15), nextRunAt)
    }

    @Test
    fun `once schedule uses explicit timestamp`() {
        val onceAt = localMillis(2026, Calendar.MARCH, 12, 6, 45)
        val config = testConfig(
            scheduleType = "once",
            hour = 6,
            minute = 45,
            onceAtMillis = onceAt,
        )

        val nextRunAt = BackupScheduleCalculator.nextRunAt(
            config,
            localMillis(2026, Calendar.MARCH, 10, 8, 0),
        )

        assertEquals(onceAt, nextRunAt)
    }

    @Test
    fun `recurring run is not missed when it starts later on the same cycle`() {
        val scheduledAt = localMillis(2026, Calendar.JANUARY, 1, 9, 0)
        val startedAt = localMillis(2026, Calendar.JANUARY, 1, 10, 30)
        val config = testConfig(scheduleType = "daily", hour = 9, minute = 0)

        val missed = BackupScheduleCalculator.shouldTreatAsMissed(
            config = config,
            scheduledRunAtMillis = scheduledAt,
            currentTimeMillis = startedAt,
        )

        assertEquals(false, missed)
    }

    @Test
    fun `recurring run is missed once the next occurrence begins`() {
        val scheduledAt = localMillis(2026, Calendar.JANUARY, 1, 9, 0)
        val startedAt = localMillis(2026, Calendar.JANUARY, 2, 9, 0)
        val config = testConfig(scheduleType = "daily", hour = 9, minute = 0)

        val missed = BackupScheduleCalculator.shouldTreatAsMissed(
            config = config,
            scheduledRunAtMillis = scheduledAt,
            currentTimeMillis = startedAt,
        )

        assertEquals(true, missed)
    }

    @Test
    fun `one-off schedule allows a long grace window before missed`() {
        val scheduledAt = localMillis(2026, Calendar.MARCH, 12, 6, 45)
        val config = testConfig(
            scheduleType = "once",
            hour = 6,
            minute = 45,
            onceAtMillis = scheduledAt,
        )

        assertEquals(
            false,
            BackupScheduleCalculator.shouldTreatAsMissed(
                config = config,
                scheduledRunAtMillis = scheduledAt,
                currentTimeMillis = localMillis(2026, Calendar.MARCH, 12, 20, 0),
            ),
        )
        assertEquals(
            true,
            BackupScheduleCalculator.shouldTreatAsMissed(
                config = config,
                scheduledRunAtMillis = scheduledAt,
                currentTimeMillis = localMillis(2026, Calendar.MARCH, 13, 7, 0),
            ),
        )
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
            planName = "Test",
            serverId = "server-1",
            serverUrl = "https://server.test",
            rootId = "fs",
            accessToken = "access-token",
            refreshToken = "refresh-token",
            deviceId = "device-1",
            deviceName = "Device",
            includeImages = true,
            includeVideos = true,
            scheduleType = scheduleType,
            hour = hour,
            minute = minute,
            weekday = weekday,
            dayOfMonth = dayOfMonth,
            onceAtMillis = onceAtMillis,
            requiresWifi = true,
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
    ): Long {
        return Calendar.getInstance().apply {
            set(Calendar.YEAR, year)
            set(Calendar.MONTH, month)
            set(Calendar.DAY_OF_MONTH, day)
            set(Calendar.HOUR_OF_DAY, hour)
            set(Calendar.MINUTE, minute)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }.timeInMillis
    }
}
