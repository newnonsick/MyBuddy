String formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  double value = bytes.toDouble();
  var unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex++;
  }
  final decimals = (unitIndex == 0) ? 0 : (unitIndex == 1 ? 1 : 2);
  return '${value.toStringAsFixed(decimals)} ${units[unitIndex]}';
}

String formatSpeed(double bytesPerSecond) {
  if (bytesPerSecond.isNaN || bytesPerSecond.isInfinite) return '0 B/s';
  return '${formatBytes(bytesPerSecond.round())}/s';
}
