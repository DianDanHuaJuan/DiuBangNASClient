/// 文件输入：用户可消费的失败码、失败消息、可选详情
/// 文件职责：表达上层统一失败对象，将异常转换为用户可理解的形式
/// 文件对外接口：AppFailure
/// 文件包含：AppFailure
class AppFailure {
  final String code;
  final String message;
  final Map<String, dynamic>? details;

  const AppFailure({required this.code, required this.message, this.details});

  factory AppFailure.fromException({
    required String code,
    required String message,
    Map<String, dynamic>? details,
  }) {
    return AppFailure(code: code, message: message, details: details);
  }

  @override
  String toString() => 'AppFailure(code: $code, message: $message)';
}
