// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:test/test.dart';

import 'package:observatory/service_io.dart';
import 'service_test_common.dart';
import 'test_helper.dart';

void test() {
  debugger();
  stdout.write('stdout');

  debugger();
  print('print');

  debugger();
  stderr.write('stderr');
}

var tests = <IsolateTest>[
  hasStoppedAtBreakpoint,
  (Isolate isolate) async {
    Completer completer = new Completer();
    var stdoutSub;
    stdoutSub = await isolate.vm.listenEventStream(VM.kStdoutStream,
        (ServiceEvent event) {
      expect(event.isolate != null, isTrue);
      expect(event.kind, equals('WriteEvent'));
      expect(event.bytesAsString, equals('stdout'));
      stdoutSub.cancel().then((_) {
        completer.complete();
      });
    });
    await isolate.resume();
    await completer.future;
  },
  hasStoppedAtBreakpoint,
  (Isolate isolate) async {
    Completer completer = new Completer();
    var stdoutSub;
    stdoutSub = await isolate.vm.listenEventStream(VM.kStdoutStream,
        (ServiceEvent event) {
      expect(event.isolate != null, isTrue);
      expect(event.kind, equals('WriteEvent'));
      expect(event.bytesAsString, equals('print\n'));
      stdoutSub.cancel().then((_) {
        completer.complete();
      });
    });
    await isolate.resume();
    await completer.future;
  },
  hasStoppedAtBreakpoint,
  (Isolate isolate) async {
    Completer completer = new Completer();
    var stderrSub;
    stderrSub = await isolate.vm.listenEventStream(VM.kStderrStream,
        (ServiceEvent event) {
      expect(event.isolate != null, isTrue);
      expect(event.kind, equals('WriteEvent'));
      expect(event.bytesAsString, equals('stderr'));
      stderrSub.cancel().then((_) {
        completer.complete();
      });
    });
    await isolate.resume();
    await completer.future;
  },
];

main(args) => runIsolateTests(args, tests, testeeConcurrent: test);
