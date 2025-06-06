// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
// Disable background compilation so that the Issue 24908 can be reproduced.
// VMOptions=--no-background-compilation

library json_test;

import "package:expect/expect.dart";
import "dart:convert";

void testJson(jsonText, expected) {
  compare(expected, actual, path) {
    if (expected is List) {
      Expect.isTrue(actual is List);
      Expect.equals(expected.length, actual.length, "$path: List length");
      for (int i = 0; i < expected.length; i++) {
        compare(expected[i], actual[i], "$path[$i] in $jsonText");
      }
    } else if (expected is Map) {
      Expect.isTrue(actual is Map);
      Expect.equals(
        expected.length,
        actual.length,
        "$path: Map size in $jsonText",
      );
      expected.forEach((key, value) {
        Expect.isTrue(actual.containsKey(key));
        compare(value, actual[key], "$path[$key] in $jsonText");
      });
    } else if (expected is num) {
      Expect.equals(
        expected is int,
        actual is int,
        "$path: not same number type in $jsonText",
      );
      Expect.isTrue(
        expected.compareTo(actual) == 0,
        "$path: Expected: $expected, was: $actual in $jsonText",
      );
    } else {
      // String, bool, null.
      Expect.equals(expected, actual, "$path in $jsonText");
    }
  }

  for (var reviver in [null, (k, v) => v]) {
    for (var split in [0, 1, 2, 3, 4, 5]) {
      var name = (reviver == null) ? "" : "reviver:";
      var sink = new ChunkedConversionSink.withCallback((values) {
        var value = values[0];
        compare(expected, value, "$name$value");
      });
      var decoderSink = json.decoder.startChunkedConversion(sink);
      switch (split) {
        case 0:
          // Split after first char.
          decoderSink.add(jsonText.substring(0, 1));
          decoderSink.add(jsonText.substring(1));
          decoderSink.close();
          break;
        case 1:
          // Split before last char.
          int length = jsonText.length;
          decoderSink.add(jsonText.substring(0, length - 1));
          decoderSink.add(jsonText.substring(length - 1));
          decoderSink.close();
          break;
        case 2:
          // Split in middle.
          int half = jsonText.length ~/ 2;
          decoderSink.add(jsonText.substring(0, half));
          decoderSink.add(jsonText.substring(half));
          decoderSink.close();
          break;
        case 3:
          // Split in three chunks.
          int length = jsonText.length;
          int third = length ~/ 3;
          decoderSink.add(jsonText.substring(0, third));
          decoderSink.add(jsonText.substring(third, 2 * third));
          decoderSink.add(jsonText.substring(2 * third));
          decoderSink.close();
          break;
        case 4:
          // Use .decode
          sink.add([json.decode(jsonText)]);
          break;
        case 5:
          // Use jsonDecode
          sink.add([jsonDecode(jsonText)]);
          break;
      }
    }
  }
}

String escape(String s) {
  var sb = new StringBuffer();
  for (int i = 0; i < s.length; i++) {
    int code = s.codeUnitAt(i);
    if (code == '\\'.codeUnitAt(0))
      sb.write(r'\\');
    else if (code == '\"'.codeUnitAt(0))
      sb.write(r'\"');
    else if (code >= 32 && code < 127)
      sb.writeCharCode(code);
    else {
      String hex = '000${code.toRadixString(16)}';
      sb.write(
        r'\u'
        '${hex.substring(hex.length - 4)}',
      );
    }
  }
  return '$sb';
}

void testThrows(jsonText) {
  var message = "json = '${escape(jsonText)}'";
  Expect.throwsFormatException(
    () => json.decode(jsonText),
    "json.decode, $message",
  );
  Expect.throwsFormatException(
    () => jsonDecode(jsonText),
    "jsonDecode, $message",
  );
  Expect.throwsFormatException(
    () => json.decoder.convert(jsonText),
    "json.decoder.convert, $message",
  );
  Expect.throwsFormatException(
    () => utf8.decoder.fuse(json.decoder).convert(utf8.encode(jsonText)),
    "utf8.decoder.fuse(json.decoder) o utf.encode, $message",
  );
}

testNumbers() {
  // Positive tests for number formats.
  var integerList = ["0", "9", "9999"];
  var signList = ["", "-"];
  var fractionList = ["", ".0", ".1", ".99999"];
  var exponentList = [""];
  for (var exphead in ["e", "E", "e-", "E-", "e+", "E+"]) {
    for (var expval in ["0", "1", "200"]) {
      exponentList.add("$exphead$expval");
    }
  }

  for (var integer in integerList) {
    for (var sign in signList) {
      for (var fraction in fractionList) {
        for (var exp in exponentList) {
          for (var ws in ["", " ", "\t"]) {
            var literal = "$ws$sign$integer$fraction$exp$ws";
            var expectedValue = num.parse(literal);
            testJson(literal, expectedValue);
          }
        }
      }
    }
  }

  // Regression test.
  // Detect and handle overflow on integer literals by making them doubles
  // (work like `num.parse`).
  testJson("9223372036854774784", 9223372036854774784);
  testJson("-9223372036854775808", -9223372036854775808);
  testJson("9223372036854775808", 9223372036854775808.0);
  testJson("-9223372036854775809", -9223372036854775809.0);
  testJson("9223372036854775808.0", 9223372036854775808.0);
  testJson("9223372036854775810", 9223372036854775810.0);
  testJson("18446744073709551616.0", 18446744073709551616.0);
  testJson("1e309", double.infinity);
  testJson("-1e309", double.negativeInfinity);
  testJson("1e-325", 0.0);
  testJson("-1e-325", -0.0);
  // No overflow on exponent.
  testJson("1e18446744073709551616", double.infinity);
  testJson("-1e18446744073709551616", double.negativeInfinity);
  testJson("1e-18446744073709551616", 0.0);
  testJson("-1e-18446744073709551616", -0.0);

  // (Wrapping numbers in list because the chunked parsing handles top-level
  // numbers by buffering and then parsing using platform parser).
  testJson("[9223372036854774784]", [9223372036854774784]);
  testJson("[-9223372036854775808]", [-9223372036854775808]);
  testJson("[9223372036854775808]", [9223372036854775808.0]);
  testJson("[-9223372036854775809]", [-9223372036854775809.0]);
  testJson("[9223372036854775808.0]", [9223372036854775808.0]);
  testJson("[9223372036854775810]", [9223372036854775810.0]);
  testJson("[18446744073709551616.0]", [18446744073709551616.0]);
  testJson("[1e309]", [double.infinity]);
  testJson("[-1e309]", [double.negativeInfinity]);
  testJson("[1e-325]", [0.0]);
  testJson("[-1e-325]", [-0.0]);
  // No overflow on exponent.
  testJson("[1e18446744073709551616]", [double.infinity]);
  testJson("[-1e18446744073709551616]", [double.negativeInfinity]);
  testJson("[1e-18446744073709551616]", [0.0]);
  testJson("[-1e-18446744073709551616]", [-0.0]);

  // Negative tests (syntax error).
  // testError thoroughly tests the given parts with a lot of valid
  // values for the other parts.
  testError({signs, integers, fractions, exponents}) {
    def(value, defaultValue) {
      if (value == null) return defaultValue;
      if (value is List) return value;
      return [value];
    }

    signs = def(signs, signList);
    integers = def(integers, integerList);
    fractions = def(fractions, fractionList);
    exponents = def(exponents, exponentList);
    for (var integer in integers) {
      for (var sign in signs) {
        for (var fraction in fractions) {
          for (var exponent in exponents) {
            var literal = "$sign$integer$fraction$exponent";
            testThrows(literal);
          }
        }
      }
    }
  }

  // Doubles overflow to Infinity.
  testJson("1e+400", double.infinity);
  // (Integers do not, but we don't have those on dart2js).

  // Integer part cannot be omitted:
  testError(integers: "");

  // Test for "Initial zero only allowed for zero integer part" moved to
  // json_strict_test.dart because IE's jsonDecode accepts additional initial
  // zeros.

  // Only minus allowed as sign.
  testError(signs: "+");
  // Requires digits after decimal point.
  testError(fractions: ".");
  // Requires exponent digits, and only digits.
  testError(exponents: ["e", "e+", "e-", "e.0"]);

  // No whitespace inside numbers.
  // Additional case "- 2.2e+2" in json_strict_test.dart.
  testThrows("-2 .2e+2");
  testThrows("-2. 2e+2");
  testThrows("-2.2 e+2");
  testThrows("-2.2e +2");
  testThrows("-2.2e+ 2");
  testThrows("01");
  testThrows("0.");
  testThrows(".0");
  testThrows("0.e1");

  testThrows("[2.,2]");
  testThrows("{2.:2}");

  testThrows("NaN");
  testThrows("Infinity");
  testThrows("-Infinity");
  Expect.throws(() => json.encode(double.nan));
  Expect.throws(() => json.encode(double.infinity));
  Expect.throws(() => json.encode(double.negativeInfinity));
  Expect.throws(() => jsonEncode(double.nan));
  Expect.throws(() => jsonEncode(double.infinity));
  Expect.throws(() => jsonEncode(double.negativeInfinity));
}

testStrings() {
  // String parser accepts and understands escapes.
  var input =
      r'"\u0000\uffff\n\r\f\t\b\/\\\"'
      '\x20\ufffd\uffff"';
  var expected = "\u0000\uffff\n\r\f\t\b\/\\\"\x20\ufffd\uffff";
  testJson(input, expected);
  // Empty string.
  testJson(r'""', "");
  // Escape first.
  var escapes = {
    "f": "\f",
    "b": "\b",
    "n": "\n",
    "r": "\r",
    "t": "\t",
    r"\": r"\",
    '"': '"',
    "/": "/",
  };
  escapes.forEach((esc, lit) {
    testJson('"\\$esc........"', "$lit........");
    // Escape last.
    testJson('"........\\$esc"', "........$lit");
    // Escape middle.
    testJson('"....\\$esc...."', "....$lit....");
  });

  // Does not accept single quotes.
  testThrows(r"''");
  // Throws on unterminated strings.
  testThrows(r'"......\"');
  // Throws on unterminated escapes.
  testThrows(r'"\'); // ' is not escaped.
  testThrows(r'"\a"');
  testThrows(r'"\u"');
  testThrows(r'"\u1"');
  testThrows(r'"\u12"');
  testThrows(r'"\u123"');
  testThrows(r'"\ux"');
  testThrows(r'"\u1x"');
  testThrows(r'"\u12x"');
  testThrows(r'"\u123x"');
  // Throws on bad escapes.
  testThrows(r'"\a"');
  testThrows(r'"\x00"');
  testThrows(r'"\c2"');
  testThrows(r'"\000"');
  testThrows(r'"\u{0}"');
  testThrows(r'"\%"');
  testThrows('"\\\x00"'); // Not raw string!
  // Throws on control characters.
  for (int i = 0; i < 32; i++) {
    var string = new String.fromCharCodes([0x22, i, 0x22]); // '"\x00"' etc.
    testThrows(string);
  }
}

testObjects() {
  testJson(r'{}', {});
  testJson(r'{"x":42}', {"x": 42});
  testJson(r'{"x":{"x":{"x":42}}}', {
    "x": {
      "x": {"x": 42},
    },
  });
  testJson(r'{"x":10,"x":42}', {"x": 42});
  testJson(r'{"":42}', {"": 42});

  // Keys must be strings.
  testThrows(r'{x:10}');
  testThrows(r'{true:10}');
  testThrows(r'{false:10}');
  testThrows(r'{null:10}');
  testThrows(r'{42:10}');
  testThrows(r'{42e1:10}');
  testThrows(r'{-42:10}');
  testThrows(r'{["text"]:10}');
  testThrows(r'{:10}');
}

testArrays() {
  testJson(r'[]', []);
  testJson(r'[1.1e1,"string",true,false,null,{}]', [
    1.1e1,
    "string",
    true,
    false,
    null,
    {},
  ]);
  testJson(r'[[[[[[]]]],[[[]]],[[]]]]', [
    [
      [
        [
          [[]],
        ],
      ],
      [
        [[]],
      ],
      [[]],
    ],
  ]);
  testJson(r'[{},[{}],{"x":[]}]', [
    {},
    [{}],
    {"x": []},
  ]);

  testThrows(r'[1,,2]');
  testThrows(r'[1,2,]');
  testThrows(r'[,2]');
}

testWords() {
  testJson(r'true', true);
  testJson(r'false', false);
  testJson(r'null', null);
  testJson(r'[true]', [true]);
  testJson(r'{"true":true}', {"true": true});

  testThrows(r'truefalse');
  testThrows(r'trues');
  testThrows(r'nulll');
  testThrows(r'full');
  testThrows(r'nul');
  testThrows(r'tru');
  testThrows(r'fals');
  testThrows(r'\null');
  testThrows(r't\rue');
  testThrows(r't\rue');
}

testWhitespace() {
  // Valid white-space characters.
  var v = '\t\r\n\ ';
  // Invalid white-space and non-recognized characters.
  var invalids = ['\x00', '\f', '\x08', '\\', '\xa0', '\u2028', '\u2029'];

  // Valid whitespace accepted "everywhere".
  testJson('$v[${v}-2.2e2$v,$v{$v"key"$v:${v}true$v}$v,$v"ab"$v]$v', [
    -2.2e2,
    {"key": true},
    "ab",
  ]);

  // IE9 accepts invalid characters at the end, so some of these tests have been
  // moved to json_strict_test.dart.
  for (var i in invalids) {
    testThrows('${i}"s"');
    testThrows('42${i}');
    testThrows('$i[]');
    testThrows('[$i]');
    testThrows('[$i"s"]');
    testThrows('["s"$i]');
    testThrows('$i{"k":"v"}');
    testThrows('{$i"k":"v"}');
    testThrows('{"k"$i:"v"}');
    testThrows('{"k":$i"v"}');
    testThrows('{"k":"v"$i}');
  }
}

main() {
  testNumbers();
  testStrings();
  testWords();
  testObjects();
  testArrays();
  testWhitespace();
}
