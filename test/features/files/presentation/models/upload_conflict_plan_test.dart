/// 文件输入：UploadConflictPlanBuilder、目录项、本地媒体项
/// 文件职责：验证普通上传前的重名检测与默认跳过策略
/// 文件对外接口：main
/// 文件包含：main
import 'package:flutter_test/flutter_test.dart';
import 'package:nasclient/core/device/local_media_picker.dart';
import 'package:nasclient/core/protocol/upload_contract.dart';
import 'package:nasclient/features/files/domain/entities/file_entry_entity.dart';
import 'package:nasclient/features/files/domain/entities/file_type.dart';
import 'package:nasclient/features/transfer/domain/entities/upload_conflict_resolution.dart';
import 'package:nasclient/features/transfer/presentation/models/upload_conflict_plan.dart';

/// 输入：Flutter test runtime。
/// 职责：覆盖普通上传的目录重名检测与选择内重名检测。
/// 对外接口：main。
void main() {
  group('UploadConflictPlanBuilder', () {
    test(
      'marks names that already exist in current directory as conflicts',
      () {
        const builder = UploadConflictPlanBuilder();

        final plan = builder.build(
          selectedItems: const [
            PickedLocalMediaItem(
              id: '1',
              localPath: 'C:\\camera\\photo.jpg',
              displayName: 'photo.jpg',
              size: 120,
            ),
            PickedLocalMediaItem(
              id: '2',
              localPath: 'C:\\camera\\clip.mp4',
              displayName: 'clip.mp4',
              size: 300,
            ),
          ],
          currentEntries: const [
            FileEntryEntity(
              name: 'photo.jpg',
              path: '/photo.jpg',
              type: FileType.file,
              size: 120,
            ),
          ],
          resolveFileName: (item) => item.displayName,
        );

        expect(plan.uploadableItems.map((item) => item.displayName), [
          'clip.mp4',
        ]);
        expect(plan.conflictCount, 1);
        expect(plan.existingEntryConflictCount, 1);
        expect(plan.selectedDuplicateConflictCount, 0);
        expect(
          plan.conflictItems.single.type,
          UploadConflictType.existingEntry,
        );
        expect(plan.uniqueConflictFileNames, ['photo.jpg']);
      },
    );

    test('keeps first selected file and flags later duplicate names', () {
      const builder = UploadConflictPlanBuilder();

      final plan = builder.build(
        selectedItems: const [
          PickedLocalMediaItem(
            id: '1',
            localPath: 'C:\\camera\\clip-a.mp4',
            displayName: 'clip.mp4',
            size: 300,
          ),
          PickedLocalMediaItem(
            id: '2',
            localPath: 'C:\\camera\\clip-b.mp4',
            displayName: 'clip.mp4',
            size: 320,
          ),
          PickedLocalMediaItem(
            id: '3',
            localPath: 'C:\\camera\\note.jpg',
            displayName: 'note.jpg',
            size: 90,
          ),
        ],
        currentEntries: const [],
        resolveFileName: (item) => item.displayName,
      );

      expect(plan.uploadableItems.map((item) => item.displayName), [
        'clip.mp4',
        'note.jpg',
      ]);
      expect(plan.conflictCount, 1);
      expect(plan.existingEntryConflictCount, 0);
      expect(plan.selectedDuplicateConflictCount, 1);
      expect(
        plan.conflictItems.single.type,
        UploadConflictType.selectedDuplicate,
      );
      expect(plan.uniqueConflictFileNames, ['clip.mp4']);
    });

    test(
      'applies overwrite policy only to conflicting items and keeps order',
      () {
        const builder = UploadConflictPlanBuilder();

        final plan = builder.build(
          selectedItems: const [
            PickedLocalMediaItem(
              id: '1',
              localPath: 'C:\\camera\\clip.mp4',
              displayName: 'clip.mp4',
              size: 300,
            ),
            PickedLocalMediaItem(
              id: '2',
              localPath: 'C:\\camera\\photo.jpg',
              displayName: 'photo.jpg',
              size: 120,
            ),
          ],
          currentEntries: const [
            FileEntryEntity(
              name: 'photo.jpg',
              path: '/photo.jpg',
              type: FileType.file,
              size: 100,
            ),
          ],
          resolveFileName: (item) => item.displayName,
        );

        final prepared = plan.applyBatchResolution(
          UploadConflictBatchResolution.overwrite,
        );

        expect(prepared.skippedCount, 0);
        expect(prepared.queuedItems.map((item) => item.fileName), [
          'clip.mp4',
          'photo.jpg',
        ]);
        expect(prepared.queuedItems.map((item) => item.conflictPolicy), [
          UploadConflictPolicy.fail,
          UploadConflictPolicy.overwrite,
        ]);
        expect(
          prepared.queuedItems.every(
            (item) => !item.requiresConflictResolution,
          ),
          isTrue,
        );
      },
    );

    test('prepares one-by-one resolution for conflicting items only', () {
      const builder = UploadConflictPlanBuilder();

      final plan = builder.build(
        selectedItems: const [
          PickedLocalMediaItem(
            id: '1',
            localPath: 'C:\\camera\\clip-a.mp4',
            displayName: 'clip.mp4',
            size: 300,
          ),
          PickedLocalMediaItem(
            id: '2',
            localPath: 'C:\\camera\\clip-b.mp4',
            displayName: 'clip.mp4',
            size: 320,
          ),
          PickedLocalMediaItem(
            id: '3',
            localPath: 'C:\\camera\\note.jpg',
            displayName: 'note.jpg',
            size: 90,
          ),
        ],
        currentEntries: const [],
        resolveFileName: (item) => item.displayName,
      );

      final prepared = plan.applyBatchResolution(
        UploadConflictBatchResolution.individually,
      );

      expect(prepared.skippedCount, 0);
      expect(prepared.queuedItems.map((item) => item.fileName), [
        'clip.mp4',
        'clip.mp4',
        'note.jpg',
      ]);
      expect(
        prepared.queuedItems.map((item) => item.requiresConflictResolution),
        [false, true, false],
      );
      expect(prepared.queuedItems[1].conflictPolicy, UploadConflictPolicy.fail);
    });
  });
}
