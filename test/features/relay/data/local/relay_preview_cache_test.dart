import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nasclient/core/storage/key_value_store.dart';
import 'package:nasclient/features/relay/data/local/relay_preview_cache.dart';
import 'package:nasclient/features/relay/domain/relay_media_kind.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('RelayPreviewCache dual-track', () {
    test('persists thumbnail and original paths independently', () async {
      SharedPreferences.setMockInitialValues({});
      final store = KeyValueStore(prefs: await SharedPreferences.getInstance());
      final cache = RelayPreviewCache(keyValueStore: store);
      final thumbFile = File(
        '${Directory.systemTemp.path}/relay-1_thumb.jpg',
      );
      final originalFile = File(
        '${Directory.systemTemp.path}/relay_original.jpg',
      );
      await thumbFile.writeAsBytes(<int>[1, 2, 3]);
      await originalFile.writeAsBytes(<int>[4, 5, 6]);

      await cache.putThumbnail(
        transferId: 'relay-1',
        thumbnailPath: thumbFile.path,
        kind: RelayMediaKind.image,
      );
      await cache.putOriginal(
        transferId: 'relay-1',
        originalPath: originalFile.path,
        kind: RelayMediaKind.image,
      );

      final reloaded = RelayPreviewCache(keyValueStore: store);
      await reloaded.load();

      expect(reloaded.thumbnailPathFor('relay-1'), thumbFile.path);
      expect(reloaded.originalPathFor('relay-1'), originalFile.path);
      expect(reloaded.originalIsContentUri('relay-1'), isFalse);

      await thumbFile.delete();
      await originalFile.delete();
    });

    test('putOriginal does not overwrite thumbnailPath', () async {
      SharedPreferences.setMockInitialValues({});
      final store = KeyValueStore(prefs: await SharedPreferences.getInstance());
      final cache = RelayPreviewCache(keyValueStore: store);
      final thumbFile = File(
        '${Directory.systemTemp.path}/relay-2_thumb.jpg',
      );
      await thumbFile.writeAsBytes(<int>[1]);

      await cache.putThumbnail(
        transferId: 'relay-2',
        thumbnailPath: thumbFile.path,
        kind: RelayMediaKind.video,
      );
      await cache.putOriginal(
        transferId: 'relay-2',
        originalPath: 'content://media/external/video/1',
        kind: RelayMediaKind.video,
        isContentUri: true,
      );

      expect(cache.thumbnailPathFor('relay-2'), thumbFile.path);
      expect(
        cache.originalPathFor('relay-2'),
        'content://media/external/video/1',
      );

      await thumbFile.delete();
    });

    test('clearThumbnail keeps originalPath index', () async {
      SharedPreferences.setMockInitialValues({});
      final store = KeyValueStore(prefs: await SharedPreferences.getInstance());
      final cache = RelayPreviewCache(keyValueStore: store);
      final thumbFile = File(
        '${Directory.systemTemp.path}/relay-3_thumb.jpg',
      );
      await thumbFile.writeAsBytes(<int>[1]);

      await cache.putThumbnail(
        transferId: 'relay-3',
        thumbnailPath: thumbFile.path,
        kind: RelayMediaKind.image,
      );
      await cache.putOriginal(
        transferId: 'relay-3',
        originalPath: 'content://media/external/images/3',
        kind: RelayMediaKind.image,
        isContentUri: true,
      );

      await cache.clearThumbnail('relay-3');

      expect(cache.thumbnailPathFor('relay-3'), isNull);
      expect(
        cache.originalPathFor('relay-3'),
        'content://media/external/images/3',
      );
    });

    test('pruneStale drops stale index but keeps thumbnail files on disk', () async {
      SharedPreferences.setMockInitialValues({});
      final store = KeyValueStore(prefs: await SharedPreferences.getInstance());
      final cache = RelayPreviewCache(keyValueStore: store);
      final thumbFile = File(
        '${Directory.systemTemp.path}/relay-4_thumb.jpg',
      );
      await thumbFile.writeAsBytes(<int>[1]);

      await cache.putThumbnail(
        transferId: 'relay-4',
        thumbnailPath: thumbFile.path,
        kind: RelayMediaKind.image,
      );
      await cache.putOriginal(
        transferId: 'relay-4',
        originalPath: 'content://media/external/images/4',
        kind: RelayMediaKind.image,
        isContentUri: true,
      );

      await cache.pruneStale({'other-transfer'});

      expect(await thumbFile.exists(), isTrue);
      expect(cache.thumbnailPathFor('relay-4'), isNull);
      expect(cache.originalPathFor('relay-4'), isNull);
    });
  });
}
