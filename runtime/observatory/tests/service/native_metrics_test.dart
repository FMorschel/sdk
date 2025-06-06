// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'package:observatory/service_io.dart';
import 'test_helper.dart';

void script() {}

var tests = <IsolateTest>[
  (Isolate isolate) async {
    Map metrics = await isolate.refreshNativeMetrics();
    expect(metrics.length, greaterThan(1));
    expect(metrics.length, greaterThan(1));
    var foundOldHeapCapacity =
        metrics.values.any((m) => m.name == 'heap.old.capacity');
    expect(foundOldHeapCapacity, equals(true));
  },
  (Isolate isolate) async {
    var params = {'metricId': 'metrics/native/heap.old.used'};
    ServiceMetric counter =
        await isolate.invokeRpc('_getIsolateMetric', params) as ServiceMetric;
    expect(counter.type, equals('Counter'));
    expect(counter.name, equals('heap.old.used'));
  },
  (Isolate isolate) async {
    bool caughtException = false;
    try {
      await isolate.invokeRpc(
          '_getIsolateMetric', {'metricId': 'metrics/native/doesnotexist'});
      expect(false, isTrue, reason: 'Unreachable');
    } on ServerRpcException catch (e) {
      caughtException = true;
      expect(e.code, equals(ServerRpcException.kInvalidParams));
      expect(
          e.message,
          "_getIsolateMetric: invalid 'metricId' "
          "parameter: metrics/native/doesnotexist");
    }
    expect(caughtException, isTrue);
  },
];

main(args) => runIsolateTests(args, tests, testeeBefore: script);
