// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:typed_data';

import 'package:kernel/binary/ast_from_binary.dart';

import 'utils.dart';

void main() {
  void setCompileMode(Component c, NonNullableByDefaultCompiledMode mode) {
    c.setMainMethodAndMode(null, true, mode);
  }

  void verifyMode(Component c, NonNullableByDefaultCompiledMode mode) {
    if (c.mode != mode) {
      throw "Serialized and re-read component had change in mode: "
          "Expected $mode got ${c.mode}.";
    }
  }

  const List<NonNullableByDefaultCompiledMode> modes = const [
    NonNullableByDefaultCompiledMode.Weak,
    NonNullableByDefaultCompiledMode.Strong,
  ];

  int combination = 0;
  for (NonNullableByDefaultCompiledMode c1Mode in modes) {
    for (NonNullableByDefaultCompiledMode c2Mode in modes) {
      combination++;
      print("Checking combination #$combination ("
          "c1Mode: $c1Mode; "
          "c2Mode: $c2Mode; "
          ")");

      // Try individually.
      Uint8List c1Serialized;
      {
        Uri uri = Uri.parse("foo://bar.dart");
        Library lib1 = new Library(uri, fileUri: uri)
          ..nonNullableByDefaultCompiledMode = c1Mode;
        Component c1 = new Component(libraries: [lib1]);
        setCompileMode(c1, c1Mode);
        c1Serialized = serializeComponent(c1);
        Component c1RoundTrip = loadComponentFromBytes(c1Serialized);
        verifyMode(c1RoundTrip, c1Mode);
      }

      Uint8List c2Serialized;
      {
        Uri uri = Uri.parse("foo://baz.dart");
        Library lib2 = new Library(uri, fileUri: uri)
          ..nonNullableByDefaultCompiledMode = c2Mode;
        Component c2 = new Component(libraries: [lib2]);
        setCompileMode(c2, c2Mode);
        c2Serialized = serializeComponent(c2);
        Component c2RoundTrip = loadComponentFromBytes(c2Serialized);
        verifyMode(c2RoundTrip, c2Mode);
      }

      // Try with combined binary.
      try {
        Uint8List combined =
            Uint8List.fromList([...c1Serialized, ...c2Serialized]);
        Component combinedRoundTrip = loadComponentFromBytes(combined);
        verifyMode(combinedRoundTrip, verifyOK(c1Mode, c2Mode));
        print(" -> OK with $c1Mode and $c2Mode");
      } on CompilationModeError catch (e) {
        print(" -> Got $e with $c1Mode and $c2Mode");
        verifyError(c1Mode, c2Mode);
      }
      // Try other order.
      try {
        Uint8List combined =
            Uint8List.fromList([...c2Serialized, ...c1Serialized]);
        Component combinedRoundTrip = loadComponentFromBytes(combined);
        verifyMode(combinedRoundTrip, verifyOK(c1Mode, c2Mode));
        print(" -> OK with $c1Mode and $c2Mode");
      } on CompilationModeError catch (e) {
        print(" -> Got $e with $c1Mode and $c2Mode");
        verifyError(c1Mode, c2Mode);
      }

      // Try with individual binary, but loaded into same component.
      try {
        Component combinedRoundTrip = loadComponentFromBytes(c1Serialized);
        combinedRoundTrip =
            loadComponentFromBytes(c2Serialized, combinedRoundTrip);
        verifyMode(combinedRoundTrip, verifyOK(c1Mode, c2Mode));
        print(" -> OK with $c1Mode and $c2Mode");
      } on CompilationModeError catch (e) {
        print(" -> Got $e with $c1Mode and $c2Mode");
        verifyError(c1Mode, c2Mode);
      }
      // Try other order.
      try {
        Component combinedRoundTrip = loadComponentFromBytes(c2Serialized);
        combinedRoundTrip =
            loadComponentFromBytes(c1Serialized, combinedRoundTrip);
        verifyMode(combinedRoundTrip, verifyOK(c1Mode, c2Mode));
        print(" -> OK with $c1Mode and $c2Mode");
      } on CompilationModeError catch (e) {
        print(" -> Got $e with $c1Mode and $c2Mode");
        verifyError(c1Mode, c2Mode);
      }

      // Try with individual binary, but loaded into same component where
      // component initially does not have a mode.
      try {
        Component combinedRoundTrip = new Component();
        combinedRoundTrip =
            loadComponentFromBytes(c1Serialized, combinedRoundTrip);
        combinedRoundTrip =
            loadComponentFromBytes(c2Serialized, combinedRoundTrip);
        verifyMode(combinedRoundTrip, verifyOK(c1Mode, c2Mode));
        print(" -> OK with $c1Mode and $c2Mode");
      } on CompilationModeError catch (e) {
        print(" -> Got $e with $c1Mode and $c2Mode");
        verifyError(c1Mode, c2Mode);
      }
    }
  }

  print("Done: Everything looks good.");
}

bool isOK(NonNullableByDefaultCompiledMode c1Mode,
    NonNullableByDefaultCompiledMode c2Mode) {
  return c1Mode == c2Mode;
}

NonNullableByDefaultCompiledMode verifyOK(
    NonNullableByDefaultCompiledMode c1Mode,
    NonNullableByDefaultCompiledMode c2Mode) {
  if (isOK(c1Mode, c2Mode)) {
    return c1Mode;
  }
  throw "Not OK combination: $c1Mode and $c2Mode";
}

void verifyError(NonNullableByDefaultCompiledMode c1Mode,
    NonNullableByDefaultCompiledMode c2Mode) {
  if (isOK(c1Mode, c2Mode)) {
    throw "Unexpected error for $c1Mode and $c2Mode";
  }
}
