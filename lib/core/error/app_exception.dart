/// 文件输入：底层异常信息、原始错误码、原始报错内容
/// 文件职责：统一封装底层异常，将各类底层错误转换为统一的异常类型
/// 文件对外接口：AppException
/// 文件包含：AppException
class AppException implements Exception {
  final String code;
  final String message;
  final dynamic originalError;
  final StackTrace? stackTrace;

  const AppException({
    required this.code,
    required this.message,
    this.originalError,
    this.stackTrace,
  });

  @override
  String toString() => 'AppException(code: $code, message: $message)';
}
