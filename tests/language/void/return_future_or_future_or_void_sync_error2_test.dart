// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Formatting can break multitests, so don't format them.
// dart format off

import 'dart:async';

void main() {
  test();
}

// Can only `return;` if the return type is `void`, `Future` or `Null`.
FutureOr<FutureOr<void>> test() {
  return; //# none: compile-time error
}
