// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:convert';

import 'package:source_maps/parser.dart';

void f() {
  g();
}

void g() {
  throw 'hi';
}

runtimeFalse() => int.parse('1') == 0;

// `expectedFrames` is (file, line, column, name) of the frames we check.
//
// Information we don't check are "null": we don't want to check line/column
// of standard library functions to avoid breaking the test with unrelated
// changes to the standard library.
void testMain(
  String testName,
  List<(String?, int?, int?, String?)?> expectedFrames,
) {
  // Use `f` and `g` in a few places to make sure wasm-opt won't inline them
  // in the test.
  final fTearOff = f;
  final gTearOff = g;

  if (runtimeFalse()) f();
  if (runtimeFalse()) g();

  // Get some simple stack trace.
  String? stackTraceString;
  try {
    f();
  } catch (e, st) {
    stackTraceString = st.toString();
  }

  // Print the stack trace to make it easy to update the test.
  print("-----");
  print(stackTraceString);
  print("-----");

  final actualFrames = parseStack(
    testName,
    getSourceMapping(testName),
    stackTraceString!,
  );
  print('Got stack trace:');
  for (final frame in actualFrames) {
    print('  $frame');
  }
  print('Matching against:');
  for (final frame in expectedFrames) {
    print('  $frame');
  }

  if (actualFrames.length < expectedFrames.length) {
    throw 'Less actual frames than expected';
  }

  for (int i = 0; i < expectedFrames.length; i++) {
    final expected = expectedFrames[i];
    final actual = actualFrames[i];
    if (expected == null) continue;
    if (actual == null) {
      throw 'Mismatch:\n  Expected: $expected\n  Actual: <no mapping>';
    }
    if ((expected.$1 != null && actual.$1 != expected.$1) ||
        (expected.$2 != null && actual.$2 != expected.$2) ||
        (expected.$3 != null && actual.$3 != expected.$3) ||
        (expected.$4 != null && actual.$4 != expected.$4)) {
      throw 'Mismatch:\n  Expected: $expected\n  Actual: $actual';
    }
  }
}

String getFilename(String testName, int moduleId) {
  final compilationDir = const String.fromEnvironment("TEST_COMPILATION_DIR");
  if (moduleId == 0) {
    return '$compilationDir/${testName}_test.wasm.map';
  } else {
    return '$compilationDir/${testName}_test_module$moduleId.wasm.map';
  }
}

Mapping getSourceMapping(String testName) {
  final allMappings = MappingBundle();
  // Read source map of the current program.
  final compilationDir = const String.fromEnvironment("TEST_COMPILATION_DIR");
  final mainFilename = getFilename(testName, 0);
  final mainSourceMapFile = readfile(mainFilename);
  final mainSourceMap = parse(utf8.decode(mainSourceMapFile)) as SingleMapping;
  mainSourceMap.targetUrl = mainFilename;
  allMappings.addMapping(mainSourceMap);

  int i = 1;
  while (true) {
    // All the modules will have consecutive names. Keep reading them until we
    // fail to find one.
    try {
      final filename = getFilename(testName, i);
      final fileContents = readfile(filename);
      final sourceMap = parse(utf8.decode(fileContents)) as SingleMapping;
      sourceMap.targetUrl = filename;
      allMappings.addMapping(sourceMap);
      i++;
    } catch (e) {
      break;
    }
  }
  return allMappings;
}

List<(String?, int?, int?, String?)?> parseStack(
  String testName,
  Mapping mapping,
  String stackTraceString,
) {
  final parsed = <(String?, int?, int?, String?)?>[];
  for (final line in stackTraceString.split('\n')) {
    if (line.contains('.mjs') || line.contains('.js')) {
      parsed.add(null);
      continue;
    }

    final hexOffsetMatch = stackTraceHexOffsetRegExp.firstMatch(line);
    if (hexOffsetMatch == null) {
      throw 'Unable to parse hex offset in frame "$line"';
    }
    final hexOffsetStr = hexOffsetMatch.group(1)!; // includes '0x'
    final offset = int.tryParse(hexOffsetStr);
    if (offset == null) {
      throw 'Unable to parse hex number in frame "$line"';
    }
    final moduleIdMatch = stackTraceModuleNameRegExp.firstMatch(line);
    if (moduleIdMatch == null) {
      throw 'Unable to parse module name in frame "$line"';
    }
    final moduleId = int.parse(moduleIdMatch.group(1)!);
    final uri = getFilename(testName, moduleId);
    final span = mapping.spanFor(0, offset, uri: uri);
    if (span == null) {
      print('Stack frame "$line" does not have a source mapping');
      parsed.add(null);
      continue;
    }
    final filename = span.sourceUrl!.pathSegments.last;
    final lineNumber = span.start.line;
    final columnNumber = span.start.column;
    final symbolName = span.text;
    parsed.add((filename, 1 + lineNumber, 1 + columnNumber, symbolName));
  }
  return parsed;
}

/// Read the file at the given [path].
///
/// This relies on the `readbuffer` function provided by d8.
@JS()
external JSArrayBuffer readbuffer(JSString path);

/// Read the file at the given [path].
Uint8List readfile(String path) => Uint8List.view(readbuffer(path.toJS).toDart);

final stackTraceHexOffsetRegExp = RegExp(r'wasm-function.*(0x[0-9a-fA-F]+)\)$');
final stackTraceModuleNameRegExp = RegExp(r'wasm/module([0-9]+)');
