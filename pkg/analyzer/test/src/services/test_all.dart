// Copyright (c) 2017, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'top_level_declarations_test.dart' as top_level_declarations;

main() {
  defineReflectiveSuite(() {
    top_level_declarations.main();
  }, name: 'services');
}
