// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'package:observatory/service_io.dart';
import 'service_test_common.dart';
import 'test_helper.dart';

doThrow() {
  throw "TheException";
}

var tests = <IsolateTest>[
  hasStoppedWithUnhandledException,
  (Isolate isolate) async {
    print("We stopped!");
    var stack = await isolate.getStack();
    expect(stack['frames'][0].function.name, equals('doThrow'));
  }
];

main(args) => runIsolateTestsSynchronous(args, tests,
    pause_on_unhandled_exceptions: true, testeeConcurrent: doThrow);
