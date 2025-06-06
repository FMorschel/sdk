// Copyright (c) 2011, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library futures_test;

import 'dart:async';

import 'package:expect/async_helper.dart';
import 'package:expect/expect.dart';

Future testWaitEmpty() {
  final futures = <Future>[];
  return Future.wait(futures);
}

Future testCompleteAfterWait() {
  final futures = <Future>[];
  final c = new Completer<Object?>();
  futures.add(c.future);
  Future future = Future.wait(futures);
  c.complete(null);
  return future;
}

Future testCompleteBeforeWait() {
  final futures = <Future>[];
  final c = new Completer();
  futures.add(c.future);
  c.complete(null);
  return Future.wait(futures);
}

Future testWaitWithMultipleValues() {
  final futures = <Future>[];
  final c1 = new Completer();
  final c2 = new Completer();
  futures.add(c1.future);
  futures.add(c2.future);
  c1.complete(1);
  c2.complete(2);
  return Future.wait(futures).then((values) {
    Expect.listEquals([1, 2], values);
  });
}

Future testWaitWithSingleError() {
  final futures = <Future>[];
  final c1 = new Completer();
  final c2 = new Completer();
  futures.add(c1.future);
  futures.add(c2.future);
  c1.complete();
  c2.completeError('correct error');

  return Future.wait(futures)
      .then<void>((_) {
        throw 'incorrect error';
      })
      .catchError((error, stackTrace) {
        Expect.equals('correct error', error);
        Expect.isNotNull(stackTrace);
      });
}

Future testWaitWithMultipleErrors() {
  final futures = <Future>[];
  final c1 = new Completer();
  final c2 = new Completer();
  futures.add(c1.future);
  futures.add(c2.future);
  c1.completeError('correct error');
  c2.completeError('incorrect error 1');

  return Future.wait(futures)
      .then<void>((_) {
        throw 'incorrect error 2';
      })
      .catchError((error, stackTrace) {
        Expect.equals('correct error', error);
        Expect.isNotNull(stackTrace);
      });
}

// Regression test for https://github.com/dart-lang/sdk/issues/41656
Future testWaitWithErrorAndNonErrorEager() {
  return Future(() {
    var f1 = Future(() => throw "Error");
    var f2 = Future(() => 3);
    return Future.wait([f1, f2], eagerError: true);
  }).then((_) => 0, onError: (_) => -1);
}

Future testWaitWithMultipleErrorsEager() {
  final futures = <Future>[];
  final c1 = new Completer();
  final c2 = new Completer();
  futures.add(c1.future);
  futures.add(c2.future);
  c1.completeError('correct error');
  c2.completeError('incorrect error 1');

  return Future.wait(futures, eagerError: true)
      .then<void>((_) {
        throw 'incorrect error 2';
      })
      .catchError((error, stackTrace) {
        Expect.equals('correct error', error);
        Expect.isNotNull(stackTrace);
      });
}

StackTrace get currentStackTrace {
  try {
    throw 0;
  } catch (e, st) {
    return st;
  }
}

Future testWaitWithSingleErrorWithStackTrace() {
  final futures = <Future>[];
  final c1 = new Completer();
  final c2 = new Completer();
  futures.add(c1.future);
  futures.add(c2.future);
  c1.complete();
  c2.completeError('correct error', currentStackTrace);

  return Future.wait(futures)
      .then<void>((_) {
        throw 'incorrect error';
      })
      .catchError((error, stackTrace) {
        Expect.equals('correct error', error);
        Expect.isNotNull(stackTrace);
      });
}

Future testWaitWithMultipleErrorsWithStackTrace() {
  final futures = <Future>[];
  final c1 = new Completer();
  final c2 = new Completer();
  futures.add(c1.future);
  futures.add(c2.future);
  c1.completeError('correct error', currentStackTrace);
  c2.completeError('incorrect error 1');

  return Future.wait(futures)
      .then<void>((_) {
        throw 'incorrect error 2';
      })
      .catchError((error, stackTrace) {
        Expect.equals('correct error', error);
        Expect.isNotNull(stackTrace);
      });
}

Future testWaitWithMultipleErrorsWithStackTraceEager() {
  final futures = <Future>[];
  final c1 = new Completer();
  final c2 = new Completer();
  futures.add(c1.future);
  futures.add(c2.future);
  c1.completeError('correct error', currentStackTrace);
  c2.completeError('incorrect error 1');

  return Future.wait(futures, eagerError: true)
      .then<void>((_) {
        throw 'incorrect error 2';
      })
      .catchError((error, stackTrace) {
        Expect.equals('correct error', error);
        Expect.isNotNull(stackTrace);
      });
}

Future testEagerWait() {
  var st;
  try {
    throw 0;
  } catch (e, s) {
    st = s;
  }
  final c1 = new Completer();
  final c2 = new Completer();
  final futures = <Future>[c1.future, c2.future];
  final waited = Future.wait(futures, eagerError: true);
  final result = waited
      .then<void>(
        (v) {
          throw "should not be called";
        },
        onError: (e, s) {
          Expect.equals(e, 42);
          Expect.identical(st, s);
        },
      )
      .whenComplete(() {
        return new Future(() => true);
      });
  c1.completeError(42, st);
  return result;
}

Future testForEachEmpty() {
  return Future.forEach([], (_) {
    throw 'should not be called';
  });
}

Future testForEach() {
  final seen = <int>[];
  return Future.forEach([1, 2, 3, 4, 5], (dynamic n) {
    seen.add(n);
    return new Future.value();
  }).then((_) => Expect.listEquals([1, 2, 3, 4, 5], seen));
}

Future testForEachSync() {
  final seen = <int>[];
  return Future.forEach([
    1,
    2,
    3,
    4,
    5,
  ], seen.add).then((_) => Expect.listEquals([1, 2, 3, 4, 5], seen));
}

Future testForEachWithException() {
  final seen = <int>[];
  return Future.forEach([1, 2, 3, 4, 5], (dynamic n) {
        if (n == 4) throw 'correct exception';
        seen.add(n);
        return new Future.value();
      })
      .then<void>((_) {
        throw 'incorrect exception';
      })
      .catchError((error) {
        Expect.equals('correct exception', error);
      });
}

Future testDoWhile() {
  var count = 0;
  return Future.doWhile(() {
    count++;
    return new Future(() => count < 10);
  }).then((_) => Expect.equals(10, count));
}

Future testDoWhileSync() {
  var count = 0;
  return Future.doWhile(() {
    count++;
    return count < 10;
  }).then((_) => Expect.equals(10, count));
}

Future testDoWhileWithException() {
  var count = 0;
  return Future.doWhile(() {
        count++;
        if (count == 4) throw 'correct exception';
        return new Future(() => true);
      })
      .then<void>((_) {
        throw 'incorrect exception';
      })
      .catchError((error) {
        Expect.equals('correct exception', error);
      })
      .whenComplete(() {
        return new Future(() => false);
      });
}

main() {
  final futures = <Future>[];

  futures.add(testWaitEmpty());
  futures.add(testCompleteAfterWait());
  futures.add(testCompleteBeforeWait());
  futures.add(testWaitWithMultipleValues());
  futures.add(testWaitWithSingleError());
  futures.add(testWaitWithMultipleErrors());
  futures.add(testWaitWithErrorAndNonErrorEager());
  futures.add(testWaitWithMultipleErrorsEager());
  futures.add(testWaitWithSingleErrorWithStackTrace());
  futures.add(testWaitWithMultipleErrorsWithStackTrace());
  futures.add(testWaitWithMultipleErrorsWithStackTraceEager());
  futures.add(testEagerWait());
  futures.add(testForEachEmpty());
  futures.add(testForEach());
  futures.add(testForEachSync());
  futures.add(testForEachWithException());
  futures.add(testDoWhile());
  futures.add(testDoWhileSync());
  futures.add(testDoWhileWithException());

  asyncStart();
  Future.wait(futures).then((List list) {
    Expect.equals(19, list.length);
    asyncEnd();
  });
}
