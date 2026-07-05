import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nasclient/core/storage/key_value_store.dart';
import 'package:nasclient/features/relay/data/local/relay_preview_cache.dart';
import 'package:nasclient/features/relay/domain/relay_media_kind.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('Relay acceptance scenarios', () {
    late KeyValueStore store;
    late RelayPreviewCache cache;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      store = KeyValueStore(prefs: await SharedPreferences.getInstance());
      cache = RelayPreviewCache(keyValueStore: store);
    });

    test('sender keeps thumb and original after restart', () async {
      final thumb = await _writeTemp('sender_thumb.jpg', <int>[1, 2]);
      final original = await _writeTemp('sender_original.jpg', <int>[3, 4]);

      await cache.putThumbnail(
        transferId: 'sender-1',
        thumbnailPath: thumb.path,
        kind: RelayMediaKind.image,
      );
      await cache.putOriginal(
        transferId: 'sender-1',
        originalPath: original.path,
        kind: RelayMediaKind.image,
      );

      final reloaded = RelayPreviewCache(keyValueStore: store);
      await reloaded.load();

      expect(reloaded.thumbnailPathFor('sender-1'), thumb.path);
      expect(reloaded.originalPathFor('sender-1'), original.path);

      await thumb.delete();
      await original.delete();
    });

    test('receiver download only updates originalPath', () async {
      final thumb = await _writeTemp('recv_thumb.jpg', <int>[1]);

      await cache.putThumbnail(
        transferId: 'recv-1',
        thumbnailPath: thumb.path,
        kind: RelayMediaKind.image,
      );
      await cache.putOriginal(
        transferId: 'recv-1',
        originalPath: 'content://media/external/images/recv-1',
        kind: RelayMediaKind.image,
        isContentUri: true,
      );

      expect(cache.thumbnailPathFor('recv-1'), thumb.path);
      expect(
        cache.originalPathFor('recv-1'),
        'content://media/external/images/recv-1',
      );
      expect(cache.hasDownloadedOriginal('recv-1'), isTrue);

      await thumb.delete();
    });

    test('fifo eviction clears thumbnail only', () async {
      final thumb = await _writeTemp('fifo_thumb.jpg', <int>[1]);
      const originalUri = 'content://media/external/images/fifo';

      await cache.putThumbnail(
        transferId: 'fifo-1',
        thumbnailPath: thumb.path,
        kind: RelayMediaKind.image,
      );
      await cache.putOriginal(
        transferId: 'fifo-1',
        originalPath: originalUri,
        kind: RelayMediaKind.image,
        isContentUri: true,
      );

      await cache.clearThumbnail('fifo-1');

      expect(cache.thumbnailPathFor('fifo-1'), isNull);
      expect(cache.originalPathFor('fifo-1'), originalUri);
    });

    test('pruneStale never deletes content uri originals from index only', () async {
      const originalUri = 'content://media/external/images/prune';
      await cache.putOriginal(
        transferId: 'prune-1',
        originalPath: originalUri,
        kind: RelayMediaKind.image,
        isContentUri: true,
      );

      await cache.pruneStale(<String>{});

      expect(cache.originalPathFor('prune-1'), isNull);
    });
  });
}

Future<File> _writeTemp(String name, List<int> bytes) async {
  final file = File('${Directory.systemTemp.path}/$name');
  await file.writeAsBytes(bytes);
  return file;
}
