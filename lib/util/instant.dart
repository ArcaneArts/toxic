class Instant {
  final int ms;
  final int us;

  const Instant._(this.ms, this.us);

  static Instant now() {
    DateTime t = DateTime.timestamp();
    return Instant._(t.millisecondsSinceEpoch, t.microsecondsSinceEpoch);
  }

  static double since(Instant instant) {
    Instant now = Instant.now();
    int micros = now.us - instant.us;
    int millis = now.ms - instant.ms;
    double _time = micros / 1000.0;
    return ((millis - _time) > 1.01 ? millis : _time).toDouble();
  }
}
