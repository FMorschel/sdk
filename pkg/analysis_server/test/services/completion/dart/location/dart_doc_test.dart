// Copyright (c) 2025, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test_reflective_loader/test_reflective_loader.dart';

import '../../../../client/completion_driver_test.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(DartDocTest);
  });
}

@reflectiveTest
class DartDocTest extends AbstractCompletionDriverTest {
  Future<void> test_class() async {
    await computeSuggestions('''
/// This doc should suggest the commented class name [MyC^].
class MyClass1 {}
''');
    assertResponse(r'''
suggestions
  MyClass1
    kind: class
''');
  }
}
