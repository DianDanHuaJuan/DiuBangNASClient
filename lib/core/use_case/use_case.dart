/// 文件输入：Params 类型与返回结果泛型
/// 文件职责：定义 UseCase 统一接口约定，规范业务用例的执行方式
/// 文件对外接口：UseCase
/// 文件包含：UseCase
abstract class UseCase<Result, Params> {
  Future<Result> call(Params params);
}
