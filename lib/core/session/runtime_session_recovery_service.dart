import '../../features/auth/application/use_cases/restore_session_use_case.dart';
import '../use_case/no_params.dart';
import 'current_session.dart';

typedef SessionBaseUrlApplier = Future<void> Function(String baseUrl);

class RuntimeSessionRecoveryService {
  RuntimeSessionRecoveryService({
    required RestoreSessionUseCase restoreSessionUseCase,
    required CurrentSession currentSession,
    required SessionBaseUrlApplier applyBaseUrl,
  }) : _restoreSessionUseCase = restoreSessionUseCase,
       _currentSession = currentSession,
       _applyBaseUrl = applyBaseUrl;

  final RestoreSessionUseCase _restoreSessionUseCase;
  final CurrentSession _currentSession;
  final SessionBaseUrlApplier _applyBaseUrl;

  Future<bool>? _inFlightRecovery;

  Future<bool> recoverSession() async {
    final inFlightRecovery = _inFlightRecovery;
    if (inFlightRecovery != null) {
      return inFlightRecovery;
    }

    final recovery = _recoverInternal();
    _inFlightRecovery = recovery;
    try {
      return await recovery;
    } finally {
      if (identical(_inFlightRecovery, recovery)) {
        _inFlightRecovery = null;
      }
    }
  }

  Future<bool> _recoverInternal() async {
    final result = await _restoreSessionUseCase.call(const NoParams());
    if (result.isFailure) {
      return false;
    }

    final serverUrl = _currentSession.serverUrl;
    if (serverUrl == null || serverUrl.trim().isEmpty) {
      return false;
    }

    await _applyBaseUrl(serverUrl);
    return true;
  }
}
