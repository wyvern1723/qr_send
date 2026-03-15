import '../models/missing_range.dart';

class MissingRangeCalculator {
  const MissingRangeCalculator();

  List<MissingRange> calculate({
    required int totalChunks,
    required Set<int> receivedChunks,
  }) {
    final ranges = <MissingRange>[];
    int? rangeStart;

    for (var index = 0; index < totalChunks; index++) {
      final isMissing = !receivedChunks.contains(index);
      if (isMissing && rangeStart == null) {
        rangeStart = index;
      } else if (!isMissing && rangeStart != null) {
        ranges.add(MissingRange(start: rangeStart, end: index - 1));
        rangeStart = null;
      }
    }

    if (rangeStart != null) {
      ranges.add(MissingRange(start: rangeStart, end: totalChunks - 1));
    }

    return ranges;
  }

  String describe({
    required int totalChunks,
    required Set<int> receivedChunks,
  }) {
    final ranges = calculate(
      totalChunks: totalChunks,
      receivedChunks: receivedChunks,
    );
    if (ranges.isEmpty) {
      return 'None';
    }
    return ranges.join(', ');
  }
}
