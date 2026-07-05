/// 文件输入：成功值或失败值
/// 文件职责：统一表达 UseCase 和 Repository 的结果类型，封装成功/失败的统一返回值
/// 文件对外接口：AppResult
/// 文件包含：AppResult
import '../error/app_failure.dart';

sealed class AppResult<T> {
  const AppResult();

  bool get isSuccess => this is Success<T>;
  bool get isFailure => this is Failure<T>;

  T? get dataOrNull {
    if (this is Success<T>) {
      return (this as Success<T>).data;
    }
    return null;
  }

  AppFailure? get failureOrNull {
    if (this is Failure<T>) {
      return (this as Failure<T>).failure;
    }
    return null;
  }

  R when<R>({
    required R Function(T data) success,
    required R Function(AppFailure failure) failure,
  }) {
    if (this is Success<T>) {
      return success((this as Success<T>).data);
    } else {
      return failure((this as Failure<T>).failure);
    }
  }
}

class Success<T> extends AppResult<T> {
  final T data;
  const Success(this.data);
}

class Failure<T> extends AppResult<T> {
  final AppFailure failure;
  const Failure(this.failure);
}
