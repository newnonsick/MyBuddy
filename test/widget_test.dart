import 'package:flutter_test/flutter_test.dart';
import 'package:mybuddy/core/utils/format_bytes.dart';

void main() {
  group('formatBytes', () {
    test('formats bytes and kilobytes', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(512), '512 B');
      expect(formatBytes(1024), '1.0 KB');
    });

    test('formats megabytes with two decimals', () {
      expect(formatBytes(1024 * 1024), '1.00 MB');
      expect(formatBytes(2 * 1024 * 1024), '2.00 MB');
    });
  });

  group('formatSpeed', () {
    test('formats normal speeds', () {
      expect(formatSpeed(1536), '1.5 KB/s');
    });

    test('handles invalid values', () {
      expect(formatSpeed(double.nan), '0 B/s');
      expect(formatSpeed(double.infinity), '0 B/s');
    });
  });
}
