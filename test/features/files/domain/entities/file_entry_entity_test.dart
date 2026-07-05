import 'package:flutter_test/flutter_test.dart';
import 'package:nasclient/features/files/domain/entities/file_entry_entity.dart';
import 'package:nasclient/features/files/domain/entities/file_category.dart';
import 'package:nasclient/features/files/domain/entities/file_type.dart';

void main() {
  test('treats 3gp files as videos for thumbnail rendering', () {
    const entity = FileEntryEntity(
      name: 'clip.3gp',
      path: '/videos/clip.3gp',
      type: FileType.file,
      size: 1024,
    );

    expect(entity.isVideo, isTrue);
    expect(FileCategory.fromExtension(entity.extension), FileCategory.video);
  });
}
