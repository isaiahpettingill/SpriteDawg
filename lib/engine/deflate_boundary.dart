import 'dart:typed_data';
import 'document.dart';

/// Validate the *entire* zlib envelope before dart:io inflates it. The SDK's
/// decoder ignores trailing bytes; a small DEFLATE scanner closes that gap and
/// bounds the decoded size without allocating the uncompressed document.
void validateZlib(Uint8List data, int expected) {
  require(data.length >= 6, 'Truncated zlib envelope');
  require(
    data[0] & 15 == 8 &&
        data[0] >> 4 <= 7 &&
        ((data[0] << 8) | data[1]) % 31 == 0 &&
        data[1] & 32 == 0,
    'Unsupported zlib header',
  );
  final bits = _Bits(Uint8List.sublistView(data, 2, data.length - 4));
  var output = 0, finalBlock = false;
  const lengthBase = [
    3,
    4,
    5,
    6,
    7,
    8,
    9,
    10,
    11,
    13,
    15,
    17,
    19,
    23,
    27,
    31,
    35,
    43,
    51,
    59,
    67,
    83,
    99,
    115,
    131,
    163,
    195,
    227,
    258,
  ];
  const lengthExtra = [
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    1,
    1,
    1,
    1,
    2,
    2,
    2,
    2,
    3,
    3,
    3,
    3,
    4,
    4,
    4,
    4,
    5,
    5,
    5,
    5,
    0,
  ];
  const distBase = [
    1,
    2,
    3,
    4,
    5,
    7,
    9,
    13,
    17,
    25,
    33,
    49,
    65,
    97,
    129,
    193,
    257,
    385,
    513,
    769,
    1025,
    1537,
    2049,
    3073,
    4097,
    6145,
    8193,
    12289,
    16385,
    24577,
  ];
  const distExtra = [
    0,
    0,
    0,
    0,
    1,
    1,
    2,
    2,
    3,
    3,
    4,
    4,
    5,
    5,
    6,
    6,
    7,
    7,
    8,
    8,
    9,
    9,
    10,
    10,
    11,
    11,
    12,
    12,
    13,
    13,
  ];
  while (!finalBlock) {
    finalBlock = bits.read(1) == 1;
    final type = bits.read(2);
    if (type == 0) {
      bits.align();
      final n = bits.read(16), inverse = bits.read(16);
      require((n ^ inverse) == 65535, 'Invalid stored block');
      bits.skip(n * 8);
      output += n;
    } else {
      require(type != 3, 'Invalid DEFLATE block');
      late _Tree literals, distances;
      if (type == 1) {
        literals = _Tree(
          List.generate(
            288,
            (i) => i < 144
                ? 8
                : i < 256
                ? 9
                : i < 280
                ? 7
                : 8,
          ),
        );
        distances = _Tree(List.filled(32, 5));
      } else {
        final nl = bits.read(5) + 257,
            nd = bits.read(5) + 1,
            nc = bits.read(4) + 4;
        require(
          nl <= 286,
          'Invalid literal count',
        ); // RFC1951 order, spelled separately to keep review straightforward.
        const codeOrder = [
          16,
          17,
          18,
          0,
          8,
          7,
          9,
          6,
          10,
          5,
          11,
          4,
          12,
          3,
          13,
          2,
          14,
          1,
          15,
        ];
        final lengths = List.filled(19, 0);
        for (var i = 0; i < nc; i++) {
          lengths[codeOrder[i]] = bits.read(3);
        }
        final tree = _Tree(lengths), all = <int>[];
        while (all.length < nl + nd) {
          final symbol = tree.decode(bits);
          if (symbol <= 15) {
            all.add(symbol);
          } else {
            int n, value;
            if (symbol == 16) {
              require(all.isNotEmpty, 'Invalid code repeat');
              n = bits.read(2) + 3;
              value = all.last;
            } else if (symbol == 17) {
              n = bits.read(3) + 3;
              value = 0;
            } else {
              require(symbol == 18, 'Invalid code length');
              n = bits.read(7) + 11;
              value = 0;
            }
            require(all.length + n <= nl + nd, 'Code repeat overflow');
            all.addAll(List.filled(n, value));
          }
        }
        require(all[256] > 0, 'Missing end-of-block code');
        literals = _Tree(all.sublist(0, nl));
        distances = _Tree(all.sublist(nl));
      }
      while (true) {
        final symbol = literals.decode(bits);
        if (symbol < 256) {
          output++;
        } else if (symbol == 256) {
          break;
        } else {
          require(symbol <= 285, 'Invalid length symbol');
          final i = symbol - 257,
              length = lengthBase[i] + bits.read(lengthExtra[i]),
              distance = distances.decode(bits);
          require(distance < 30, 'Invalid distance symbol');
          final back = distBase[distance] + bits.read(distExtra[distance]);
          require(back <= output, 'Distance before output');
          output += length;
        }
        require(output <= expected, 'Inflated cel exceeds declared size');
      }
    }
    require(output <= expected, 'Inflated cel exceeds declared size');
  }
  require(output == expected, 'Incorrect zlib cel length');
  bits.align();
  require(
    bits.position == bits.bytes.length * 8,
    'Trailing bytes after zlib stream',
  );
}

class _Bits {
  final Uint8List bytes;
  int position = 0;
  _Bits(this.bytes);
  int read(int count) {
    require(position + count <= bytes.length * 8, 'Truncated DEFLATE stream');
    var result = 0;
    for (var i = 0; i < count; i++) {
      result |= ((bytes[position >> 3] >> (position & 7)) & 1) << i;
      position++;
    }
    return result;
  }

  void align() => position = (position + 7) & ~7;
  void skip(int count) {
    require(position + count <= bytes.length * 8, 'Truncated stored block');
    position += count;
  }
}

class _Tree {
  final Map<int, int> symbols = {};
  _Tree(List<int> lengths) {
    final counts = List.filled(16, 0);
    for (final n in lengths) {
      require(n >= 0 && n <= 15, 'Invalid Huffman length');
      if (n > 0) counts[n]++;
    }
    var code = 0;
    final next = List.filled(16, 0);
    for (var bits = 1; bits <= 15; bits++) {
      code = (code + counts[bits - 1]) << 1;
      require(code + counts[bits] <= 1 << bits, 'Oversubscribed Huffman tree');
      next[bits] = code;
    }
    for (var i = 0; i < lengths.length; i++) {
      final n = lengths[i];
      if (n > 0) symbols[(1 << n) | next[n]++] = i;
    }
  }
  int decode(_Bits bits) {
    var code = 0;
    for (var length = 1; length <= 15; length++) {
      code = (code << 1) | bits.read(1);
      final value = symbols[(1 << length) | code];
      if (value != null) return value;
    }
    throw const FormatException('Invalid Huffman symbol');
  }
}
