// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library utf8_test;

import "package:expect/expect.dart";
import 'dart:convert';

String decode(List<int> bytes, int chunkSize) {
  StringBuffer buffer = new StringBuffer();
  var stringSink = new StringConversionSink.fromStringSink(buffer);
  var byteSink = new Utf8Decoder().startChunkedConversion(stringSink);
  int i = 0;
  while (i < bytes.length) {
    var nextChunk = <int>[];
    for (int j = 0; j < chunkSize; j++) {
      if (i < bytes.length) {
        nextChunk.add(bytes[i]);
        i++;
      }
    }
    byteSink.add(nextChunk);
  }
  byteSink.close();
  return buffer.toString();
}

String decodeAllowMalformed(List<int> bytes, int chunkSize) {
  StringBuffer buffer = new StringBuffer();
  var stringSink = new StringConversionSink.fromStringSink(buffer);
  var decoder = new Utf8Decoder(allowMalformed: true);
  var byteSink = decoder.startChunkedConversion(stringSink);
  int i = 0;
  while (i < bytes.length) {
    var nextChunk = <int>[];
    for (int j = 0; j < chunkSize; j++) {
      if (i < bytes.length) {
        nextChunk.add(bytes[i]);
        i++;
      }
    }
    byteSink.add(nextChunk);
  }
  byteSink.close();
  return buffer.toString();
}

final TESTS0 = [
  // Unfinished UTF-8 sequences.
  [0xc3],
  [0xE2, 0x82],
  [0xF0, 0xA4, 0xAD],
];

final TESTS1 = [
  // Overlong encoding of euro-sign.
  [0xF0, 0x82, 0x82, 0xAC],
  // Other overlong/unfinished sequences.
  [0xC0],
  [0xC1],
  [0xF5],
  [0xF6],
  [0xF7],
  [0xF8],
  [0xF9],
  [0xFA],
  [0xFB],
  [0xFC],
  [0xFD],
  [0xFE],
  [0xFF],
  [0xC0, 0x80],
  [0xC1, 0x80],
  // Outside valid range.
  [0xF4, 0xBF, 0xBF, 0xBF],
];

final TESTS2 = [
  // Test that 0xC0|1, 0x80 does not eat the next character.
  [
    [0xC0, 0x80, 0x61],
    "XXa",
  ],
  [
    [0xC1, 0x80, 0x61],
    "XXa",
  ],
  // 0xF5 .. 0xFF never appear in valid UTF-8 sequences.
  [
    [0xF5, 0x80],
    "XX",
  ],
  [
    [0xF6, 0x80],
    "XX",
  ],
  [
    [0xF7, 0x80],
    "XX",
  ],
  [
    [0xF8, 0x80],
    "XX",
  ],
  [
    [0xF9, 0x80],
    "XX",
  ],
  [
    [0xFA, 0x80],
    "XX",
  ],
  [
    [0xFB, 0x80],
    "XX",
  ],
  [
    [0xFC, 0x80],
    "XX",
  ],
  [
    [0xFD, 0x80],
    "XX",
  ],
  [
    [0xFE, 0x80],
    "XX",
  ],
  [
    [0xFF, 0x80],
    "XX",
  ],
  [
    [0xF5, 0x80, 0x61],
    "XXa",
  ],
  [
    [0xF6, 0x80, 0x61],
    "XXa",
  ],
  [
    [0xF7, 0x80, 0x61],
    "XXa",
  ],
  [
    [0xF8, 0x80, 0x61],
    "XXa",
  ],
  [
    [0xF9, 0x80, 0x61],
    "XXa",
  ],
  [
    [0xFA, 0x80, 0x61],
    "XXa",
  ],
  [
    [0xFB, 0x80, 0x61],
    "XXa",
  ],
  [
    [0xFC, 0x80, 0x61],
    "XXa",
  ],
  [
    [0xFD, 0x80, 0x61],
    "XXa",
  ],
  [
    [0xFE, 0x80, 0x61],
    "XXa",
  ],
  [
    [0xFF, 0x80, 0x61],
    "XXa",
  ],
  // Characters outside the valid range.
  [
    [0xF5, 0x80, 0x80, 0x61],
    "XXXa",
  ],
  [
    [0xF6, 0x80, 0x80, 0x61],
    "XXXa",
  ],
  [
    [0xF7, 0x80, 0x80, 0x61],
    "XXXa",
  ],
  [
    [0xF8, 0x80, 0x80, 0x61],
    "XXXa",
  ],
  [
    [0xF9, 0x80, 0x80, 0x61],
    "XXXa",
  ],
  [
    [0xFA, 0x80, 0x80, 0x61],
    "XXXa",
  ],
  [
    [0xFB, 0x80, 0x80, 0x61],
    "XXXa",
  ],
  [
    [0xFC, 0x80, 0x80, 0x61],
    "XXXa",
  ],
  [
    [0xFD, 0x80, 0x80, 0x61],
    "XXXa",
  ],
  [
    [0xFE, 0x80, 0x80, 0x61],
    "XXXa",
  ],
  [
    [0xFF, 0x80, 0x80, 0x61],
    "XXXa",
  ],
];

main() {
  var allTests = [...TESTS0, ...TESTS1].expand((test) {
    // Pairs of test and expected string output when malformed strings are
    // allowed. Replacement character: U+FFFD, one per unfinished sequence or
    // undecodable byte.
    String replacement = TESTS0.contains(test)
        ? "\u{FFFD}"
        : "\u{FFFD}" * test.length;
    return [
      [test, "${replacement}"],
      [
        [0x61, ...test],
        "a${replacement}",
      ],
      [
        [0x61, ...test, 0x61],
        "a${replacement}a",
      ],
      [
        [...test, 0x61],
        "${replacement}a",
      ],
      [
        [...test, ...test],
        "${replacement}${replacement}",
      ],
      [
        [...test, 0x61, ...test],
        "${replacement}a${replacement}",
      ],
      [
        [0xc3, 0xa5, ...test],
        "å${replacement}",
      ],
      [
        [0xc3, 0xa5, ...test, 0xc3, 0xa5],
        "å${replacement}å",
      ],
      [
        [...test, 0xc3, 0xa5],
        "${replacement}å",
      ],
      [
        [...test, 0xc3, 0xa5, ...test],
        "${replacement}å${replacement}",
      ],
    ];
  });

  var allTests2 = TESTS2.map((test) {
    // Pairs of test and expected string output when malformed strings are
    // allowed. Replacement character: U+FFFD
    String expected = (test[1] as String).replaceAll("X", "\u{FFFD}");
    return [test[0], expected];
  });

  for (var test
      in []
        ..addAll(allTests)
        ..addAll(allTests2)) {
    List<int> bytes = test[0];
    Expect.throwsFormatException(() => decode(bytes, 1));
    Expect.throwsFormatException(() => decode(bytes, 2));
    Expect.throwsFormatException(() => decode(bytes, 3));
    Expect.throwsFormatException(() => decode(bytes, 4));

    String expected = test[1];
    Expect.equals(expected, decodeAllowMalformed(bytes, 1));
    Expect.equals(expected, decodeAllowMalformed(bytes, 2));
    Expect.equals(expected, decodeAllowMalformed(bytes, 3));
    Expect.equals(expected, decodeAllowMalformed(bytes, 4));
  }
}
