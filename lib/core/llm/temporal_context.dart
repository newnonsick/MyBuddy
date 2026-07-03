import 'dart:convert';

import 'package:flutter_timezone/flutter_timezone.dart';

final class TemporalContext {
  const TemporalContext({
    required this.localNow,
    required this.timeZoneId,
    required this.utcOffset,
  });

  final DateTime localNow;
  final String timeZoneId;
  final Duration utcOffset;

  String toPromptBlock() {
    final payload = jsonEncode(<String, String>{
      'current_local_datetime': localNow.toIso8601String(),
      'timezone': timeZoneId,
      'utc_offset': _formatOffset(utcOffset),
    });
    return '<runtime_context>$payload</runtime_context>';
  }
}

abstract interface class TemporalContextSource {
  Future<TemporalContext> capture();
}

final class DeviceTemporalContextSource implements TemporalContextSource {
  const DeviceTemporalContextSource();

  @override
  Future<TemporalContext> capture() async {
    final now = DateTime.now().toLocal();
    final zone = await FlutterTimezone.getLocalTimezone();
    return TemporalContext(
      localNow: now,
      timeZoneId: zone.identifier,
      utcOffset: now.timeZoneOffset,
    );
  }
}

String _formatOffset(Duration offset) {
  final minutes = offset.inMinutes;
  final sign = minutes < 0 ? '-' : '+';
  final absolute = minutes.abs();
  final hours = (absolute ~/ 60).toString().padLeft(2, '0');
  final remainder = (absolute % 60).toString().padLeft(2, '0');
  return '$sign$hours:$remainder';
}
