import 'dart:async';

import 'backup_plan_scheduler_service.dart';

typedef ScheduledBackupPollListener =
    void Function(
      BackupWorkerStateSnapshot snapshot,
      BackupWorkerRunSnapshot? activeRun,
      bool runTransitioned,
    );

/// Adaptive polling for scheduled backup worker state.
/// Polls at 2s only while a run is active or shortly after user schedule/stop
/// actions; otherwise idle (no periodic channel calls).
class ScheduledBackupPollController {
  ScheduledBackupPollController({
    required BackupPlanSchedulerService scheduler,
    required String planId,
    required ScheduledBackupPollListener onUpdated,
  }) : _scheduler = scheduler,
       _planId = planId,
       _onUpdated = onUpdated;

  final BackupPlanSchedulerService _scheduler;
  final String _planId;
  ScheduledBackupPollListener _onUpdated;

  Timer? _timer;
  bool _started = false;
  bool _paused = false;
  BackupWorkerRunSnapshot? _lastActiveRun;

  void setListener(ScheduledBackupPollListener onUpdated) {
    _onUpdated = onUpdated;
  }

  void start() {
    _started = true;
    _paused = false;
    unawaited(refreshOnce(forcePersist: true));
    _scheduleNextTick();
  }

  void stop() {
    _started = false;
    _paused = false;
    _timer?.cancel();
    _timer = null;
  }

  void pause() {
    _paused = true;
    _timer?.cancel();
    _timer = null;
  }

  void resume() {
    if (!_started) {
      return;
    }
    _paused = false;
    unawaited(refreshOnce(forcePersist: true));
    _scheduleNextTick();
  }

  void boostPollWindow() {
    _scheduler.boostPollWindow();
    if (_started && !_paused) {
      _scheduleNextTick();
    }
  }

  Future<void> refreshOnce({bool forcePersist = false}) async {
    final previousRunId = _lastActiveRun?.id;
    final snapshot = await _scheduler.refreshWorkerSnapshotForUi(
      planId: _planId,
      forcePersist: forcePersist,
    );
    final activeRun = snapshot.findActiveRun(_planId);
    _lastActiveRun = activeRun;
    final runTransitioned =
        previousRunId != activeRun?.id ||
        (previousRunId != null && activeRun == null);
    _onUpdated(snapshot, activeRun, runTransitioned);
    _scheduleNextTick();
  }

  void _scheduleNextTick() {
    _timer?.cancel();
    if (!_started || _paused) {
      return;
    }

    final interval = _scheduler.pollIntervalFor(
      hasActiveScheduledRun: _lastActiveRun?.isActive == true,
      pollingEnabled: true,
    );
    if (interval == null) {
      return;
    }

    _timer = Timer(interval, () async {
      await refreshOnce();
      _scheduleNextTick();
    });
  }
}
