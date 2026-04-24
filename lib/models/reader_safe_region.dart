class ReaderSafeRegion {
  final double x;
  final double y;
  final double width;
  final double height;

  const ReaderSafeRegion({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  factory ReaderSafeRegion.fromJson(Map<String, dynamic> json) {
    double readNum(String key, double fallback) {
      final value = json[key];
      if (value is num) {
        return value.toDouble();
      }
      return fallback;
    }

    return ReaderSafeRegion(
      x: readNum('x', 0),
      y: readNum('y', 0),
      width: readNum('width', 0),
      height: readNum('height', 0),
    );
  }
}
