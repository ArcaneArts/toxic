import 'dart:math';

final Random _random = Random();

randomBool() => _random.nextBool();

randomDouble() => _random.nextDouble();

extension XRandom on Random {
  String nextString(int length,
      {String charset =
          "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"}) {
    if (charset.isEmpty) {
      throw Exception("Charset cannot be empty");
    }

    return String.fromCharCodes(Iterable.generate(
        length, (_) => charset.codeUnitAt(nextInt(charset.length))));
  }
}
