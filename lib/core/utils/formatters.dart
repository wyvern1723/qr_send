String formatBytes(int bytes) {
  const suffixes = ['B', 'KB', 'MB', 'GB'];
  double value = bytes.toDouble();
  var suffixIndex = 0;
  while (value >= 1024 && suffixIndex < suffixes.length - 1) {
    value /= 1024;
    suffixIndex += 1;
  }
  return '${value.toStringAsFixed(value >= 100 || suffixIndex == 0 ? 0 : 1)} ${suffixes[suffixIndex]}';
}
