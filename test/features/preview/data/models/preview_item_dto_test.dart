/// 文件输入：PreviewItemDto
/// 文件职责：验证服务端预览策略到客户端策略枚举的映射行为
/// 文件对外接口：main
/// 文件包含：main
import 'package:flutter_test/flutter_test.dart';
import 'package:nasclient/features/preview/data/models/preview_item_dto.dart';
import 'package:nasclient/features/preview/domain/entities/preview_strategy.dart';

void main() {
  group('PreviewItemDto.strategyEnum', () {
    test('maps direct to native', () {
      const dto = PreviewItemDto(strategy: 'direct', kind: 'image');

      expect(dto.strategyEnum, PreviewStrategy.native);
      expect(dto.isSupported, isTrue);
    });

    test('maps progressive to progressive', () {
      const dto = PreviewItemDto(strategy: 'progressive', kind: 'video');

      expect(dto.strategyEnum, PreviewStrategy.progressive);
      expect(dto.isSupported, isTrue);
    });

    test('maps hls to streaming', () {
      const dto = PreviewItemDto(strategy: 'hls', kind: 'video');

      expect(dto.strategyEnum, PreviewStrategy.streaming);
      expect(dto.isSupported, isTrue);
    });

    test('treats unsupported and unknown strategies as unsupported', () {
      const unsupportedDto = PreviewItemDto(
        strategy: 'unsupported',
        kind: 'document',
      );
      const unknownDto = PreviewItemDto(strategy: 'mystery', kind: 'image');

      expect(unsupportedDto.strategyEnum, PreviewStrategy.unsupported);
      expect(unsupportedDto.isSupported, isFalse);
      expect(unknownDto.strategyEnum, PreviewStrategy.unsupported);
      expect(unknownDto.isSupported, isFalse);
    });
  });
}
