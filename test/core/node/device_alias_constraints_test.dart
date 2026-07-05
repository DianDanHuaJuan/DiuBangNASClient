import 'package:flutter_test/flutter_test.dart';
import 'package:nasclient/core/node/device_alias_constraints.dart';

void main() {
  group('DeviceAliasConstraints', () {
    test('allows empty alias when clearing', () {
      expect(DeviceAliasConstraints.validate(''), isNull);
      expect(DeviceAliasConstraints.normalizeForSave(''), isNull);
    });

    test('rejects alias longer than maxLength', () {
      final longAlias = '中' * (DeviceAliasConstraints.maxLength + 1);
      expect(
        DeviceAliasConstraints.validate(longAlias),
        '别名不能超过 ${DeviceAliasConstraints.maxLength} 个字',
      );
      expect(
        () => DeviceAliasConstraints.normalizeForSave(longAlias),
        throwsArgumentError,
      );
    });

    test('normalizes whitespace', () {
      expect(DeviceAliasConstraints.normalize('  客厅  平板  '), '客厅 平板');
      expect(DeviceAliasConstraints.normalizeForSave('  客厅  平板  '), '客厅 平板');
    });
  });
}
