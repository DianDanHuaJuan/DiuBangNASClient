import 'package:flutter_test/flutter_test.dart';
import 'package:nasclient/features/relay/data/models/relay_transfer_dto.dart';
import 'package:nasclient/features/relay/domain/entities/relay_transfer_entity.dart';

void main() {
  group('RelayTransferDto', () {
    test('accepts empty tempPath when artifact is deleted', () {
      final transfer = RelayTransferDto.fromJson(
        _transferJson(
          tempPath: '',
          cleanupState: 'deleted',
          transferId: 'relay-purged',
        ),
      );

      expect(transfer.artifact.cleanupState, RelayArtifactCleanupState.deleted);
      expect(transfer.artifact.tempPath, '/purged/relay-purged');
    });

    test('parseTransferList skips invalid records and continues', () {
      final parsed = RelayTransferDto.parseTransferList(
        [
          _transferJson(transferId: 'relay-ok'),
          _transferJson(
            transferId: 'relay-bad',
            tempPath: '',
            cleanupState: 'sealed',
          ),
          _transferJson(transferId: 'relay-ok-2'),
        ],
        context: 'test',
      );

      expect(parsed, hasLength(2));
      expect(parsed.map((t) => t.transferId), ['relay-ok', 'relay-ok-2']);
    });
  });
}

Map<String, dynamic> _transferJson({
  required String transferId,
  String tempPath = 'D:\\relay\\part',
  String cleanupState = 'sealed',
  String status = 'completed',
}) {
  return <String, dynamic>{
    'transferId': transferId,
    'senderAccountId': 'acct-1',
    'senderLabel': 'Phone',
    'senderClientId': 'phone-01',
    'targetCount': 1,
    'fileName': 'demo.jpg',
    'fileSize': 128,
    'checksumAlgorithm': 'sha256',
    'chunkSize': 1048576,
    'storageMode': 'store_on_nas',
    'status': status,
    'createdAt': '2026-04-12T10:00:00.000Z',
    'updatedAt': '2026-04-12T10:01:00.000Z',
    'expiresAt': '2026-04-15T10:00:00.000Z',
    'targets': [
      {
        'transferId': transferId,
        'receiverClientId': 'tablet-01',
        'deliveryState': 'completed',
        'updatedAt': '2026-04-12T10:01:00.000Z',
      },
    ],
    'artifact': {
      'transferId': transferId,
      'tempPath': tempPath,
      'chunkCount': 1,
      'receivedBytes': 128,
      'isSealed': true,
      'cleanupState': cleanupState,
      'updatedAt': '2026-04-12T10:01:00.000Z',
    },
  };
}
