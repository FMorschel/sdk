// Copyright (c) 2011, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library collection_test;

import "package:expect/expect.dart";
import 'dart:collection' show Queue;

class CollectionTest {
  CollectionTest(Iterable<int> iterable) {
    testFold(iterable);
  }

  void testFold(Iterable<int> iterable) {
    Expect.equals(28, iterable.fold<int>(0, (prev, element) => prev + element));
    Expect.equals(
      3024,
      iterable.fold<int>(1, (prev, element) => prev * element),
    );
  }
}

main() {
  final TEST_ELEMENTS = const [4, 2, 6, 7, 9];
  // Const list.
  new CollectionTest(TEST_ELEMENTS);

  // Fixed size list.
  var fixedList = new List<int>.of(TEST_ELEMENTS, growable: false);
  new CollectionTest(fixedList);

  // Growable list.
  new CollectionTest(new List.from(TEST_ELEMENTS));

  // Set.
  new CollectionTest(new Set.from(TEST_ELEMENTS));

  // Queue.
  new CollectionTest(new Queue.from(TEST_ELEMENTS));
}
