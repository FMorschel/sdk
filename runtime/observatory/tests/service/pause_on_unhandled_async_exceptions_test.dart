// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'package:observatory/models.dart' as M;
import 'package:observatory/service_io.dart';
import 'service_test_common.dart';
import 'test_helper.dart';

// AUTOGENERATED START
//
// Update these constants by running:
//
// dart pkg/vm_service/test/update_line_numbers.dart runtime/observatory/tests/service/pause_on_unhandled_async_exceptions_test.dart
//
const LINE_A = 60;
// AUTOGENERATED END

class Foo {}

String doThrow() {
  throw "TheException";
  return "end of doThrow";
}

Future<void> asyncThrower() async {
  await 0; // force async gap
  doThrow();
}

testeeMain() async {
  try {
    // This is a regression case for https://dartbug.com/53334:
    // we should recognize `then(..., onError: ...)` as a catch
    // all exception handler.
    await asyncThrower().then((v) => v, onError: (e, st) {
      // Caught and ignored.
    });

    await asyncThrower().onError((error, stackTrace) {
      // Caught and ignored.
    });

    try {
      await asyncThrower();
    } on String catch (e) {
      // Caught and ignored.
    }

    try {
      await asyncThrower();
    } catch (e) {
      // Caught and ignored.
    }

    // This does not catch the exception.
    try {
      await asyncThrower(); // LINE_A.
    } on double catch (e) {}
  } on Foo catch (e) {}
}

var tests = <IsolateTest>[
  hasStoppedWithUnhandledException,
  (Isolate isolate) async {
    print("We stopped!");
    var stack = await isolate.getStack();
    expect(stack['asyncCausalFrames'], isNotNull);
    var asyncStack = stack['asyncCausalFrames'];
    expect(asyncStack.length, greaterThanOrEqualTo(4));
    await expectFrame(asyncStack[0], functionName: 'doThrow');
    await expectFrame(asyncStack[1], functionName: 'asyncThrower');
    await expectFrame(asyncStack[2], kind: M.FrameKind.asyncSuspensionMarker);
    await expectFrame(asyncStack[3],
        kind: M.FrameKind.asyncCausal,
        functionName: 'testeeMain',
        line: LINE_A);
  },
];

main(args) => runIsolateTests(args, tests,
    pause_on_unhandled_exceptions: true,
    testeeConcurrent: testeeMain,
    extraArgs: extraDebuggingArgs);
