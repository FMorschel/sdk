// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// It is a static compile time error if a method m1 overrides a method m2 and has a
// different number of required parameters.

class A {
  foo() {}
}

class B extends A {
  foo(a) {}
  // [error column 3, length 3]
  // [analyzer] COMPILE_TIME_ERROR.INVALID_OVERRIDE
  // [cfe] The method 'B.foo' has more required arguments than those of overridden method 'A.foo'.
}

main() {
  new B().foo(42);
}
