import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:toxic/util/ssss.dart';

class _SSSSTestSupport {
  const _SSSSTestSupport._();

  static Uint8List bytes(List<int> values) => Uint8List.fromList(values);

  static List<List<int>> shareLists(Iterable<Uint8List> shares) =>
      shares.map((share) => share.toList()).toList();

  static List<Uint8List> pickShares(
          List<Uint8List> shares, List<int> indices) =>
      <Uint8List>[for (int index in indices) shares[index]];

  static Matcher throwsMessage(String message) => throwsA(
        predicate(
          (Object error) =>
              error is Exception && error.toString().contains(message),
          'Exception containing "$message"',
        ),
      );

  static Future<List<int>> decodeWithCompactDecoder(
      List<List<int>> rawShares) async {
    Directory directory =
        await Directory.systemTemp.createTemp('ssss_compact_decoder_');
    File script = File('${directory.path}/compact_decoder_check.dart');
    String rawSharesJson = jsonEncode(rawShares);
    String source = """
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

${SSSS.compactDecoder}

void main() {
  List<dynamic> rawParts = jsonDecode(r'''$rawSharesJson''') as List<dynamic>;
  List<Uint8List> parts = <Uint8List>[
    for (Object rawPart in rawParts)
      Uint8List.fromList(<int>[
        for (Object value in rawPart as List<dynamic>) value as int,
      ]),
  ];
  List<int> decoded = (_d(parts) as List<dynamic>).cast<int>();
  stdout.write(jsonEncode(decoded));
}
""";

    await script.writeAsString(source);

    try {
      ProcessResult result = await Process.run(
        Platform.resolvedExecutable,
        <String>[script.path],
        workingDirectory: directory.path,
      );
      if (result.exitCode != 0) {
        fail(
          'Compact decoder script failed (${result.exitCode}).\n'
          'stdout: ${result.stdout}\n'
          'stderr: ${result.stderr}',
        );
      }

      List<dynamic> decodedJson =
          jsonDecode((result.stdout as String).trim()) as List<dynamic>;
      return <int>[for (Object value in decodedJson) value as int];
    } finally {
      await directory.delete(recursive: true);
    }
  }
}

void main() {
  group('evaluate', () {
    test('returns zero when no coefficients are provided', () {
      int result = evaluate(Uint8List(0), 91);

      expect(result, equals(0));
    });

    test('returns the constant coefficient for a degree zero polynomial', () {
      int result = evaluate(_SSSSTestSupport.bytes(<int>[0x05]), 0xC7);

      expect(result, equals(0x05));
    });

    test('evaluates a linear polynomial using gf arithmetic', () {
      int result = evaluate(_SSSSTestSupport.bytes(<int>[0x07, 0x57]), 0x13);

      expect(result, equals(0xF9));
    });
  });

  group('SSSS.encodeShares', () {
    test('throws when the threshold is outside the supported range', () {
      expect(
        () => SSSS
            .encodeShares(
              secretBytes: _SSSSTestSupport.bytes(<int>[1]),
              threshold: 0,
            )
            .first,
        _SSSSTestSupport.throwsMessage('Threshold must be 1-255'),
      );
      expect(
        () => SSSS
            .encodeShares(
              secretBytes: _SSSSTestSupport.bytes(<int>[1]),
              threshold: 256,
            )
            .first,
        _SSSSTestSupport.throwsMessage('Threshold must be 1-255'),
      );
    });

    test('produces 255 uniquely indexed seeded shares with a stable vector',
        () {
      List<Uint8List> shares = SSSS
          .encodeShares(
            secretBytes: _SSSSTestSupport.bytes(<int>[1, 2, 3, 4]),
            threshold: 3,
            seed: 1337,
          )
          .toList();
      Set<int> indices = shares.map((share) => share[0]).toSet();

      expect(shares, hasLength(255));
      expect(indices, hasLength(255));
      expect(indices.contains(0), isFalse);
      expect(shares.last[0], equals(255));
      expect(shares.first.length, equals(5));
      expect(
        _SSSSTestSupport.shareLists(shares.take(5)),
        equals(<List<int>>[
          <int>[1, 3, 122, 171, 17],
          <int>[2, 68, 208, 60, 75],
          <int>[3, 70, 168, 148, 94],
          <int>[4, 148, 53, 182, 21],
          <int>[5, 150, 77, 30, 0],
        ]),
      );
    });

    test('is deterministic for the same seed and changes for a different seed',
        () {
      List<List<int>> sharesA = _SSSSTestSupport.shareLists(
        SSSS
            .encodeShares(
              secretBytes: _SSSSTestSupport.bytes(<int>[9, 8, 7, 6]),
              threshold: 4,
              seed: 42,
            )
            .take(8),
      );
      List<List<int>> sharesB = _SSSSTestSupport.shareLists(
        SSSS
            .encodeShares(
              secretBytes: _SSSSTestSupport.bytes(<int>[9, 8, 7, 6]),
              threshold: 4,
              seed: 42,
            )
            .take(8),
      );
      List<List<int>> sharesC = _SSSSTestSupport.shareLists(
        SSSS
            .encodeShares(
              secretBytes: _SSSSTestSupport.bytes(<int>[9, 8, 7, 6]),
              threshold: 4,
              seed: 43,
            )
            .take(8),
      );

      expect(sharesA, equals(sharesB));
      expect(sharesA, isNot(equals(sharesC)));
    });
  });

  group('SSSS.decodeSSS', () {
    test('round trips from any threshold-sized subset regardless of order', () {
      Uint8List secretBytes =
          _SSSSTestSupport.bytes(<int>[0, 17, 34, 51, 68, 85, 102, 119]);
      List<Uint8List> shares = SSSS
          .encodeShares(
            secretBytes: secretBytes,
            threshold: 3,
            seed: 1337,
          )
          .toList();
      List<Uint8List> subset =
          _SSSSTestSupport.pickShares(shares, <int>[254, 1, 127]);
      List<Uint8List> shuffled =
          _SSSSTestSupport.pickShares(shares, <int>[127, 254, 1]);
      Uint8List decoded = SSSS.decodeSSS(subset);
      Uint8List decodedShuffled = SSSS.decodeSSS(shuffled);

      expect(decoded, orderedEquals(secretBytes));
      expect(decodedShuffled, orderedEquals(secretBytes));
    });

    test('round trips when more than the threshold number of shares are used',
        () {
      Uint8List secretBytes =
          _SSSSTestSupport.bytes(<int>[255, 128, 64, 32, 16, 8, 4, 2, 1]);
      List<Uint8List> shares = SSSS
          .encodeShares(
            secretBytes: secretBytes,
            threshold: 4,
            seed: 2024,
          )
          .toList();
      List<Uint8List> subset =
          _SSSSTestSupport.pickShares(shares, <int>[0, 4, 8, 64, 127, 254]);
      Uint8List decoded = SSSS.decodeSSS(subset);

      expect(decoded, orderedEquals(secretBytes));
    });

    test('round trips an empty secret', () {
      List<Uint8List> shares = SSSS
          .encodeShares(
            secretBytes: Uint8List(0),
            threshold: 1,
            seed: 99,
          )
          .toList();
      Uint8List decoded = SSSS.decodeSSS(<Uint8List>[shares[200]]);

      expect(shares, hasLength(255));
      expect(shares.first.length, equals(1));
      expect(decoded, isEmpty);
    });

    test('round trips from any single share when threshold is one', () {
      Uint8List secretBytes =
          _SSSSTestSupport.bytes(<int>[3, 1, 4, 1, 5, 9, 2, 6]);
      List<Uint8List> shares = SSSS
          .encodeShares(
            secretBytes: secretBytes,
            threshold: 1,
            seed: 7,
          )
          .toList();

      for (int index in <int>[0, 63, 127, 200, 254]) {
        Uint8List decoded = SSSS.decodeSSS(<Uint8List>[shares[index]]);

        expect(decoded, orderedEquals(secretBytes));
      }
    });

    test('round trips at the maximum supported threshold', () {
      Uint8List secretBytes = _SSSSTestSupport.bytes(<int>[42]);
      List<Uint8List> shares = SSSS
          .encodeShares(
            secretBytes: secretBytes,
            threshold: 255,
            seed: 7,
          )
          .toList();
      Uint8List decoded = SSSS.decodeSSS(shares);

      expect(shares, hasLength(255));
      expect(shares.last[0], equals(255));
      expect(decoded, orderedEquals(secretBytes));
    });

    test('does not recreate the secret with fewer than threshold shares', () {
      Uint8List secretBytes =
          _SSSSTestSupport.bytes(<int>[1, 2, 3, 4, 5, 6, 7, 8]);
      List<Uint8List> shares = SSSS
          .encodeShares(
            secretBytes: secretBytes,
            threshold: 3,
            seed: 1337,
          )
          .toList();
      Uint8List decoded =
          SSSS.decodeSSS(_SSSSTestSupport.pickShares(shares, <int>[0, 3]));

      expect(decoded, isNot(orderedEquals(secretBytes)));
      expect(decoded.length, equals(secretBytes.length));
    });

    test('throws when no parts are provided', () {
      expect(
        () => SSSS.decodeSSS(<Uint8List>[]),
        _SSSSTestSupport.throwsMessage('No parts provided'),
      );
    });

    test('throws when a share is missing its index byte', () {
      expect(
        () => SSSS.decodeSSS(<Uint8List>[Uint8List(0)]),
        _SSSSTestSupport.throwsMessage('Invalid share length'),
      );
    });

    test('throws when share lengths are inconsistent', () {
      List<Uint8List> shares = SSSS
          .encodeShares(
            secretBytes: _SSSSTestSupport.bytes(<int>[10, 20, 30]),
            threshold: 2,
            seed: 5,
          )
          .take(2)
          .toList();
      Uint8List mutatedShare =
          _SSSSTestSupport.bytes(<int>[shares[1][0], 40, 50, 60, 70]);

      expect(
        () => SSSS.decodeSSS(<Uint8List>[shares[0], mutatedShare]),
        _SSSSTestSupport.throwsMessage('Inconsistent share lengths'),
      );
    });

    test('throws when a share index is zero', () {
      expect(
        () => SSSS.decodeSSS(
          <Uint8List>[
            _SSSSTestSupport.bytes(<int>[0, 1, 2])
          ],
        ),
        _SSSSTestSupport.throwsMessage('Invalid share index 0'),
      );
    });

    test('throws when duplicate share indexes are provided', () {
      List<Uint8List> shares = SSSS
          .encodeShares(
            secretBytes: _SSSSTestSupport.bytes(<int>[11, 22, 33]),
            threshold: 2,
            seed: 55,
          )
          .take(3)
          .toList();

      expect(
        () => SSSS.decodeSSS(<Uint8List>[shares[1], shares[1]]),
        _SSSSTestSupport.throwsMessage('Duplicate x values'),
      );
    });
  });

  group('SSSS.compactDecoder', () {
    test('can be written out and decode stored shares', () async {
      List<List<int>> storedShares = <List<int>>[
        <int>[1, 3, 122, 171, 17],
        <int>[3, 70, 168, 148, 94],
        <int>[5, 150, 77, 30, 0],
      ];
      List<int> decoded =
          await _SSSSTestSupport.decodeWithCompactDecoder(storedShares);

      expect(decoded, equals(<int>[1, 2, 3, 4]));
    });

    test('matches decodeSSS for a shuffled share subset', () async {
      Uint8List secretBytes =
          _SSSSTestSupport.bytes(<int>[9, 99, 199, 42, 0, 255, 17, 88]);
      List<Uint8List> shares = SSSS
          .encodeShares(
            secretBytes: secretBytes,
            threshold: 4,
            seed: 2026,
          )
          .toList();
      List<Uint8List> subset =
          _SSSSTestSupport.pickShares(shares, <int>[200, 7, 149, 31, 90]);
      List<int> decodedCompact =
          await _SSSSTestSupport.decodeWithCompactDecoder(
        _SSSSTestSupport.shareLists(subset),
      );
      Uint8List decoded = SSSS.decodeSSS(subset);

      expect(decodedCompact, orderedEquals(decoded));
      expect(decodedCompact, orderedEquals(secretBytes));
    });
  });
}
