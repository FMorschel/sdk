// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:developer';

import 'package:test/test.dart';

import 'package:observatory/service_io.dart';
import 'service_test_common.dart';
import 'test_helper.dart';

String leafFunction(void Function() f) {
  f();
  return "some constant";
}

void testFunction() {
  debugger();
  leafFunction(() {});
  debugger();
}

bool allRangesCompiled(coverage) {
  for (int i = 0; i < coverage['ranges'].length; i++) {
    if (!coverage['ranges'][i]['compiled']) {
      return false;
    }
  }
  return true;
}

var tests = <IsolateTest>[
  hasStoppedAtBreakpoint,
  (Isolate isolate) async {
    var stack = await isolate.getStack();

    // Make sure we are in the right place.
    expect(stack.type, equals('Stack'));
    expect(stack['frames'].length, greaterThanOrEqualTo(1));
    expect(stack['frames'][0].function.name, equals('testFunction'));

    var root = isolate.rootLibrary;
    await root.load();
    var func = root.functions.singleWhere((f) => f.name == 'leafFunction');
    await func.load();

    var expectedRange = {
      'scriptIndex': 0,
      'startPos': 386,
      'endPos': 460,
      'compiled': true,
      'coverage': {
        'hits': [],
        'misses': [386, 430]
      }
    };

    var params = {
      'reports': ['Coverage'],
      'scriptId': func.location!.script.id,
      'tokenPos': func.location!.tokenPos,
      'endTokenPos': func.location!.endTokenPos,
      'forceCompile': true
    };
    var report = await isolate.invokeRpcNoUpgrade('getSourceReport', params);
    expect(report['type'], equals('SourceReport'));
    expect(report['ranges'].length, 1);
    expect(report['ranges'][0], equals(expectedRange));
    expect(report['scripts'].length, 1);
    expect(report['scripts'][0]['uri'],
        endsWith('coverage_closure_call_test.dart'));
  },
  resumeIsolate,
  hasStoppedAtBreakpoint,
  (Isolate isolate) async {
    var stack = await isolate.getStack();

    // Make sure we are in the right place.
    expect(stack.type, equals('Stack'));
    expect(stack['frames'].length, greaterThanOrEqualTo(1));
    expect(stack['frames'][0].function.name, equals('testFunction'));

    var root = isolate.rootLibrary;
    await root.load();
    var func = root.functions.singleWhere((f) => f.name == 'leafFunction');
    await func.load();

    var expectedRange = {
      'scriptIndex': 0,
      'startPos': 386,
      'endPos': 460,
      'compiled': true,
      'coverage': {
        'hits': [386, 430],
        'misses': []
      }
    };

    var params = {
      'reports': ['Coverage'],
      'scriptId': func.location!.script.id,
      'tokenPos': func.location!.tokenPos,
      'endTokenPos': func.location!.endTokenPos,
      'forceCompile': true
    };
    var report = await isolate.invokeRpcNoUpgrade('getSourceReport', params);
    expect(report['type'], equals('SourceReport'));
    expect(report['ranges'].length, 1);
    expect(report['ranges'][0], equals(expectedRange));
    expect(report['scripts'].length, 1);
    expect(report['scripts'][0]['uri'],
        endsWith('coverage_closure_call_test.dart'));
  },
];

main(args) => runIsolateTests(args, tests, testeeConcurrent: testFunction);
