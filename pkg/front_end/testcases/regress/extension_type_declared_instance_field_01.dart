// Copyright (c) 2024, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

extension type Foo(int _x) {
  int y;
  Foo.secondConstructor() : _x = 42, y = 42;
}
