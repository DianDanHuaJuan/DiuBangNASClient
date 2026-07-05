/// 文件输入：登录状态类型、错误消息
/// 文件职责：表达登录页的各种状态
/// 文件对外接口：LoginState
/// 文件包含：LoginState
abstract class LoginState {
  const LoginState();
}

class LoginInitial extends LoginState {
  const LoginInitial();
}

class LoginLoading extends LoginState {
  const LoginLoading();
}

class LoginSuccess extends LoginState {
  final String serverUrl;
  const LoginSuccess({required this.serverUrl});
}

class LoginFailure extends LoginState {
  final String message;
  const LoginFailure(this.message);
}
