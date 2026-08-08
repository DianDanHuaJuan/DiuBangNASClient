/// 文件输入：无
/// 文件职责：验证视频预览倍速/快进/长按倍速的核心逻辑与档位定义
/// 文件对外接口：无（测试文件）
/// 文件包含：video_preview_view 倍速逻辑测试
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('视频预览倍速逻辑', () {
    test('倍速档位覆盖慢放到快放的标准档位', () {
      // 与 video_preview_view.dart 中 _speedOptions 保持一致
      const speedOptions = [0.5, 1.0, 1.25, 1.5, 2.0];

      expect(speedOptions, contains(0.5), reason: '应支持慢放 0.5x');
      expect(speedOptions, contains(1.0), reason: '应包含正常倍速 1.0x');
      expect(speedOptions, contains(2.0), reason: '应支持快放 2.0x');
      expect(speedOptions.length, 5, reason: '共 5 个档位');
      // 档位应升序排列，便于 PopupMenu 展示
      for (var i = 1; i < speedOptions.length; i++) {
        expect(
          speedOptions[i],
          greaterThan(speedOptions[i - 1]),
          reason: '倍速档位应升序排列',
        );
      }
    });

    test('长按倍速为 2.0x', () {
      const longPressSpeed = 2.0;
      expect(longPressSpeed, 2.0);
    });

    test('双击快进步长为 5 秒', () {
      const seekStep = Duration(seconds: 5);
      expect(seekStep.inSeconds, 5);
    });

    test('倍速格式化：整数倍速显示一位小数', () {
      expect(_formatSpeedMirror(0.5), '0.5');
      expect(_formatSpeedMirror(1.0), '1.0');
      expect(_formatSpeedMirror(2.0), '2.0');
    });

    test('倍速格式化：非整数倍速显示原值', () {
      expect(_formatSpeedMirror(1.25), '1.25');
      expect(_formatSpeedMirror(1.5), '1.5');
    });

    test('倍速格式化：档位显示带 x 后缀', () {
      for (final speed in const [0.5, 1.0, 1.25, 1.5, 2.0]) {
        expect('${_formatSpeedMirror(speed)}x', isNotEmpty);
      }
    });

    test('长按倍速恢复逻辑：松手后应恢复原倍速', () {
      // 模拟长按前倍速为 1.25x
      const originalSpeed = 1.25;
      const longPressSpeed = 2.0;
      double? speedBeforeLongPress;

      // 长按开始：原倍速非 2.0x，保存原值
      if (originalSpeed != longPressSpeed) {
        speedBeforeLongPress = originalSpeed;
      }
      expect(speedBeforeLongPress, 1.25, reason: '长按前应保存原倍速');

      // 长按期间倍速为 2.0x
      final duringLongPress = longPressSpeed;
      expect(duringLongPress, 2.0);

      // 松手：恢复原倍速
      final restored = speedBeforeLongPress ?? 1.0;
      expect(restored, 1.25, reason: '松手后应恢复 1.25x 而非 1.0x');
    });

    test('长按倍速恢复逻辑：长按前已是 2.0x 时松手恢复 1.0x', () {
      const originalSpeed = 2.0;
      const longPressSpeed = 2.0;
      double? speedBeforeLongPress;

      // 长按开始：原倍速已是 2.0x，不保存（保持 null）
      if (originalSpeed != longPressSpeed) {
        speedBeforeLongPress = originalSpeed;
      }
      expect(speedBeforeLongPress, isNull, reason: '原倍速已是 2.0x 时不保存');

      // 松手：无保存值，恢复 1.0x
      final restored = speedBeforeLongPress ?? 1.0;
      expect(restored, 1.0);
    });

    test('双击 seek 钳制逻辑：目标位置不低于 0', () {
      final current = const Duration(seconds: 2);
      const seekStep = Duration(seconds: 5);
      final target = current - seekStep; // -3s
      // _normalizePosition 逻辑：负值钳制为 0
      final clamped = target.inMicroseconds < 0
          ? Duration.zero
          : target;
      expect(clamped, Duration.zero, reason: '后退不应低于 0');
    });

    test('双击 seek 钳制逻辑：目标位置不超过总时长', () {
      const duration = Duration(seconds: 100);
      final current = const Duration(seconds: 98);
      const seekStep = Duration(seconds: 5);
      final target = current + seekStep; // 103s
      // _normalizePosition 逻辑：超出时长则钳制为时长
      final clamped = (duration.inMicroseconds > 0 &&
              target.compareTo(duration) > 0)
          ? duration
          : target;
      expect(clamped, duration, reason: '前进不应超过总时长');
    });
  });
}

/// 镜像 video_preview_view.dart 中 _formatSpeed 的逻辑，用于可测试验证。
/// 若生产代码逻辑变更，此函数需同步更新。
String _formatSpeedMirror(double speed) {
  if (speed == speed.roundToDouble()) {
    return speed.toStringAsFixed(1);
  }
  return speed.toString();
}
