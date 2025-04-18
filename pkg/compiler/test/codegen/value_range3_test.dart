// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Test that global analysis in dart2js propagates positive integers.

import 'package:expect/async_helper.dart';
import 'package:expect/expect.dart';
import 'package:compiler/src/util/memory_compiler.dart';

const MEMORY_SOURCE_FILES = const {
  'main.dart': '''

var a = [42];

main() {
  var value = a[0];
  if (value < 42) {
    return List.filled(42, null)[value];
  }
}
''',
};

main() {
  runTest() async {
    var result = await runCompiler(memorySourceFiles: MEMORY_SOURCE_FILES);
    var compiler = result.compiler!;
    var element =
        compiler.backendClosedWorldForTesting!.elementEnvironment.mainFunction!;
    var code = compiler.backendStrategy.getGeneratedCodeForTesting(element)!;
    Expect.isFalse(code.contains('ioore'));
  }

  asyncTest(() async {
    print('--test from kernel------------------------------------------------');
    await runTest();
  });
}
