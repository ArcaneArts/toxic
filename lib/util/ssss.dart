import 'dart:math';
import 'dart:typed_data';

import 'package:toxic/toxic.dart';

class SecretShare {
  Uint8List? _secret;
  int? _threshold;
  int? _seed;
  Iterable<Uint8List>? _shares;

  SecretShare randomSeed() {
    _seed = null;
    return this;
  }

  SecretShare seedInt(int seed) {
    _seed = seed;
    return this;
  }

  SecretShare seedString(String seed) => seedInt(seed.hashCode);

  SecretShare secretBytes(Uint8List secretBytes) {
    if (secretBytes.isEmpty) {
      throw Exception('Secret cannot be empty');
    }
    _secret = secretBytes;
    return this;
  }

  SecretShare setShares(Iterable<Uint8List> shares) {
    if (shares.isEmpty) {
      throw Exception('Shares cannot be empty');
    }
    _shares = shares;
    return this;
  }

  SecretShare setSharesAsBase64(Iterable<String> shares) =>
      setShares(shares.map((s) => s.decodedBase64));

  SecretShare setSharesAsHex(Iterable<String> shares) =>
      setShares(shares.map((s) => s.decodedHex));

  SecretShare secretString(String secret) =>
      secretBytes(Uint8List.fromList(secret.codeUnits));

  SecretShare threshold(int t) {
    if (t < 1 || t > 255) {
      throw Exception('Threshold must be between 1 and 255');
    }
    _threshold = t;
    return this;
  }

  SecretShare buildShares() {
    if (_secret == null) {
      throw Exception('Secret not set');
    }
    if (_threshold == null) {
      throw Exception('Threshold not set');
    }

    _shares = SSSS.encodeShares(
      secretBytes: _secret!,
      threshold: _threshold!,
      seed: _seed,
    );

    return this;
  }

  SecretShare buildSecret() {
    if (_shares == null) {
      throw Exception('Shares not built');
    }
    _secret = SSSS.decodeSSS(_shares!.toList());
    return this;
  }

  Uint8List getSecret() {
    if (_shares == null) {
      buildSecret();
    }
    return SSSS.decodeSSS(_shares!.toList());
  }

  String getSecretAsString() => String.fromCharCodes(getSecret());

  Iterable<Uint8List> getShares() {
    if (_shares == null) {
      buildShares();
    }
    return _shares!;
  }

  Iterable<String> getSharesAsBase64() => getShares().map((s) => s.base64);

  Iterable<String> getSharesAsHex() => getShares().map((s) => s.hex);
}

class SSSS {
  const SSSS._();

  static String compactDecoder =
      "_d(List<Uint8List>p){var d=[<int>[],[],[],[]];o(a, b){int r=0;for(int i=0;i<8;i++){if((b&1)==1)r^=a;var h=(a&0x80)!=0;a=(a<<1)&0xFF;if(h)a^=0x1b;b>>=1;}return r;}g(a,e)=>e<1?1:e&1>0?o(g(o(a,a),e>>1),a):g(o(a,a),e>>1);for(int i=0;i<p.length;i++){d[1].add(p[i][0]);d[2].add(p[i].sublist(1));}for(int i=0;i<d[1].length;i++)d[3].add(d[1].asMap().keys.fold(1,(r,j)=>j==i?r:o(r,o(d[1][j],g(d[1][i]^d[1][j],254)))));for(int j=0;j<p[0].length-1;j++){int r=0;for(int i=0;i<d[1].length;i++){r=r^o(d[2][i][j],d[3][i]);}d[0].add(r);}return d[0];}";

  static Iterable<Uint8List> encodeShares(
      {required Uint8List secretBytes, int threshold = 2, int? seed}) sync* {
    if (threshold < 1 || threshold > 255) {
      throw Exception('Threshold must be 1-255');
    }

    Random random = seed == null ? Random.secure() : Random(seed);
    List<Uint8List> coefficients = [];
    BytesBuilder bb = BytesBuilder();

    for (int j = 0; j < secretBytes.length; j++) {
      Uint8List coef = Uint8List(threshold);
      coef[0] = secretBytes[j];
      for (int d = 1; d < threshold; d++) {
        coef[d] = random.nextInt(256);
      }
      bb.add(coef);
      coefficients.add(bb.takeBytes());
    }

    for (int shareIndex = 1; shareIndex <= 255; shareIndex++) {
      bb.addByte(shareIndex);
      for (int j = 0; j < secretBytes.length; j++) {
        bb.addByte(evaluate(coefficients[j], shareIndex));
      }

      yield bb.takeBytes();
    }
  }

  static Uint8List decodeSSS(List<Uint8List> parts) {
    if (parts.isEmpty) throw Exception('No parts provided');
    int shareLen = parts[0].length;
    if (shareLen < 1) throw Exception('Invalid share length');
    BytesBuilder bb = BytesBuilder();
    List<int> xs = [];
    List<List<int>> ys = [];
    for (int i = 0; i < parts.length; i++) {
      Uint8List bytes = parts[i];
      if (bytes.length != shareLen) {
        throw Exception('Inconsistent share lengths');
      }
      int x = bytes[0];
      if (x < 1 || x > 255) {
        throw Exception('Invalid share index $x');
      }
      xs.add(x);
      ys.add(bytes.sublist(1));
    }

    List<int> lis = [];
    for (int i = 0; i < xs.length; i++) {
      lis.add(_computeLi0(i, xs));
    }

    int numChunks = shareLen - 1;
    for (int j = 0; j < numChunks; j++) {
      int result = 0;
      for (int i = 0; i < xs.length; i++) {
        int y = ys[i][j];
        int contrib = _gfMult(y, lis[i]);
        result = _gfAdd(result, contrib);
      }
      bb.addByte(result);
    }

    return bb.takeBytes();
  }
}

int _gfAdd(int a, int b) => a ^ b;

const int _primitivePoly = 0x1b;

int _gfMult(int a, int b) {
  int product = 0;
  for (int i = 0; i < 8; i++) {
    if ((b & 1) == 1) {
      product ^= a;
    }
    bool hiBitSet = (a & 0x80) != 0;
    a = (a << 1) & 0xFF;
    if (hiBitSet) {
      a ^= _primitivePoly;
    }
    b >>= 1;
  }
  return product;
}

int _gfPow(int a, int e) {
  int res = 1;
  int base = a;
  while (e > 0) {
    if (e & 1 == 1) res = _gfMult(res, base);
    base = _gfMult(base, base);
    e >>= 1;
  }
  return res;
}

int _gfInverse(int a) {
  if (a == 0) throw Exception('Division by zero');
  return _gfPow(a, 254);
}

int evaluate(Uint8List coef, int x) {
  if (coef.isEmpty) return 0;
  int result = coef[coef.length - 1];
  for (int i = coef.length - 2; i >= 0; i--) {
    result = _gfMult(result, x);
    result = _gfAdd(result, coef[i]);
  }
  return result;
}

int _computeLi0(int i, List<int> xs) {
  int n = xs.length;
  int prod = 1;
  for (int jj = 0; jj < n; jj++) {
    if (jj == i) continue;
    int xj = xs[jj];
    int xi = xs[i];
    int numTerm = xj;
    int den = _gfAdd(xi, xj);
    if (den == 0) throw Exception('Duplicate x values');
    int invDen = _gfInverse(den);
    prod = _gfMult(prod, _gfMult(numTerm, invDen));
  }
  return prod;
}
