import 'dart:typed_data';

// SHA-256 for immutable retry identity, not authentication or malware detection.
// Kept local to avoid adding a package dependency; covered by standard vectors
// and the Node SHA-256 implementation in the offline tests.
String chatFileDigest(Uint8List input) {
  const k = [
    0x428a2f98,
    0x71374491,
    0xb5c0fbcf,
    0xe9b5dba5,
    0x3956c25b,
    0x59f111f1,
    0x923f82a4,
    0xab1c5ed5,
    0xd807aa98,
    0x12835b01,
    0x243185be,
    0x550c7dc3,
    0x72be5d74,
    0x80deb1fe,
    0x9bdc06a7,
    0xc19bf174,
    0xe49b69c1,
    0xefbe4786,
    0x0fc19dc6,
    0x240ca1cc,
    0x2de92c6f,
    0x4a7484aa,
    0x5cb0a9dc,
    0x76f988da,
    0x983e5152,
    0xa831c66d,
    0xb00327c8,
    0xbf597fc7,
    0xc6e00bf3,
    0xd5a79147,
    0x06ca6351,
    0x14292967,
    0x27b70a85,
    0x2e1b2138,
    0x4d2c6dfc,
    0x53380d13,
    0x650a7354,
    0x766a0abb,
    0x81c2c92e,
    0x92722c85,
    0xa2bfe8a1,
    0xa81a664b,
    0xc24b8b70,
    0xc76c51a3,
    0xd192e819,
    0xd6990624,
    0xf40e3585,
    0x106aa070,
    0x19a4c116,
    0x1e376c08,
    0x2748774c,
    0x34b0bcb5,
    0x391c0cb3,
    0x4ed8aa4a,
    0x5b9cca4f,
    0x682e6ff3,
    0x748f82ee,
    0x78a5636f,
    0x84c87814,
    0x8cc70208,
    0x90befffa,
    0xa4506ceb,
    0xbef9a3f7,
    0xc67178f2,
  ];
  final h = [
    0x6a09e667,
    0xbb67ae85,
    0x3c6ef372,
    0xa54ff53a,
    0x510e527f,
    0x9b05688c,
    0x1f83d9ab,
    0x5be0cd19,
  ];
  int rotate(int x, int n) => ((x >>> n) | (x << (32 - n))) & 0xffffffff;
  final data = Uint8List(((input.length + 9 + 63) ~/ 64) * 64)
    ..setAll(0, input);
  data[input.length] = 0x80;
  // dart2js does not implement Uint64 accessors. Use two uint32 words.
  final lengthView = ByteData.sublistView(data);
  lengthView.setUint32(data.length - 8, input.length ~/ 0x20000000, Endian.big);
  lengthView.setUint32(
    data.length - 4,
    (input.length * 8) & 0xffffffff,
    Endian.big,
  );
  final words = Uint32List(64), view = ByteData.sublistView(data);
  for (var offset = 0; offset < data.length; offset += 64) {
    for (var i = 0; i < 16; i++) {
      words[i] = view.getUint32(offset + i * 4, Endian.big);
    }
    for (var i = 16; i < 64; i++) {
      final x = words[i - 15], y = words[i - 2];
      words[i] =
          (words[i - 16] +
              (rotate(x, 7) ^ rotate(x, 18) ^ (x >>> 3)) +
              words[i - 7] +
              (rotate(y, 17) ^ rotate(y, 19) ^ (y >>> 10))) &
          0xffffffff;
    }
    var a = h[0],
        b = h[1],
        c = h[2],
        d = h[3],
        e = h[4],
        f = h[5],
        g = h[6],
        hh = h[7];
    for (var i = 0; i < 64; i++) {
      final t1 =
          (hh +
              (rotate(e, 6) ^ rotate(e, 11) ^ rotate(e, 25)) +
              ((e & f) ^ ((~e) & g)) +
              k[i] +
              words[i]) &
          0xffffffff;
      final t2 =
          ((rotate(a, 2) ^ rotate(a, 13) ^ rotate(a, 22)) +
              ((a & b) ^ (a & c) ^ (b & c))) &
          0xffffffff;
      hh = g;
      g = f;
      f = e;
      e = (d + t1) & 0xffffffff;
      d = c;
      c = b;
      b = a;
      a = (t1 + t2) & 0xffffffff;
    }
    final working = [a, b, c, d, e, f, g, hh];
    for (var i = 0; i < 8; i++) {
      h[i] = (h[i] + working[i]) & 0xffffffff;
    }
  }
  return h.map((word) => word.toRadixString(16).padLeft(8, '0')).join();
}
