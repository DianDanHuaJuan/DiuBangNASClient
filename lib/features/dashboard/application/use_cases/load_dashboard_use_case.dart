/// 文件输入：无参数
/// 文件职责：加载仪表盘汇总数据
/// 文件对外接口：LoadDashboardUseCase
/// 文件包含：LoadDashboardUseCase
import '../../../../core/use_case/use_case.dart';
import '../../../../core/use_case/no_params.dart';
import '../../../../core/result/app_result.dart';
import '../../domain/entities/dashboard_summary_entity.dart';
import '../../domain/repositories/dashboard_repository.dart';

class LoadDashboardUseCase
    implements UseCase<AppResult<DashboardSummaryEntity>, NoParams> {
  final DashboardRepository _repository;

  LoadDashboardUseCase({required DashboardRepository repository})
    : _repository = repository;

  @override
  Future<AppResult<DashboardSummaryEntity>> call(NoParams params) async {
    return await _repository.getDashboardSummary();
  }
}
