import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasclient/core/device/local_media_picker.dart';

void main() {
  group('nasGalleryPickerSelectionHitRect', () {
    test('places 35x35 hot zone at top-end with 6dp inset', () {
      const cellSize = Size(120, 120);
      final rect = nasGalleryPickerSelectionHitRect(cellSize);

      expect(rect.left, 120 - 35 - 6);
      expect(rect.top, 6);
      expect(rect.width, 35);
      expect(rect.height, 35);
      expect(rect.right, 120 - 6);
      expect(rect.bottom, 6 + 35);
    });

    test('center tap is outside selection hot zone', () {
      const cellSize = Size(120, 120);
      final rect = nasGalleryPickerSelectionHitRect(cellSize);

      expect(rect.contains(const Offset(60, 60)), isFalse);
    });

    test('top-end tap is inside selection hot zone', () {
      const cellSize = Size(120, 120);
      final rect = nasGalleryPickerSelectionHitRect(cellSize);

      expect(rect.contains(const Offset(110, 10)), isTrue);
    });
  });

  group('guessMimeTypeFromFileName', () {
    test('recognizes common image and video extensions', () {
      expect(guessMimeTypeFromFileName('a.jpg'), 'image/jpeg');
      expect(guessMimeTypeFromFileName('b.mp4'), 'video/mp4');
      expect(guessMimeTypeFromFileName('c.bin'), isNull);
    });
  });

  group('mediaScanShouldContinue', () {
    test('returns true when shouldCancel is null', () {
      expect(mediaScanShouldContinue(), isTrue);
    });

    test('returns false when shouldCancel reports cancelled', () {
      expect(
        mediaScanShouldContinue(shouldCancel: () => true),
        isFalse,
      );
    });

    test('returns true when shouldCancel reports not cancelled', () {
      expect(
        mediaScanShouldContinue(shouldCancel: () => false),
        isTrue,
      );
    });
  });
}
