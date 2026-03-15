class MissingRange {
  const MissingRange({required this.start, required this.end});

  final int start;
  final int end;

  bool get isSingle => start == end;

  @override
  String toString() {
    final displayStart = start + 1;
    final displayEnd = end + 1;
    return isSingle ? '$displayStart' : '$displayStart-$displayEnd';
  }
}
