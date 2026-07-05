/// 文件输入：启动状态类型
/// 文件职责：表达启动页的各种状态
/// 文件对外接口：StartupState
/// 文件包含：StartupState
abstract class StartupState {
  const StartupState();
}

class StartupInitial extends StartupState {
  const StartupInitial();
}

class StartupLoading extends StartupState {
  const StartupLoading();
}

class StartupRedirectToServerList extends StartupState {
  const StartupRedirectToServerList();
}

class StartupRedirectToLogin extends StartupState {
  const StartupRedirectToLogin();
}

class StartupRedirectToHome extends StartupState {
  const StartupRedirectToHome({this.shouldRestoreSession = false});

  final bool shouldRestoreSession;
}
