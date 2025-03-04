// Copyright (c) 2025, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test_reflective_loader/test_reflective_loader.dart';

import '../rule_test_support.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(AvoidSwitchOnRuntimeTypeTest);
  });
}

@reflectiveTest
class AvoidSwitchOnRuntimeTypeTest extends LintRuleTest {
  @override
  String get lintRule => LintNames.avoid_switch_on_runtimetype;

  Future<void> test_switchExpression() async {
    await assertDiagnostics(
      '''
void f(num i) {
  (switch (i.runtimeType) {
    const (int) => null,
    const (double) => null,
    _ => null,
  });
}
''',
      [lint(19, 96)],
    );
  }

  Future<void> test_switchExpression_other() async {
    await assertNoDiagnostics('''
void f(num i) {
  (switch (i) {
    int _ => null,
    double _ => null,
  });
}
''');
  }

  Future<void> test_switchExpression_override() async {
    await assertDiagnostics(
      '''
void f(MyClass i) {
  (switch (i.runtimeType) {
    const (MyClass) => null,
    _ => null,
  });
}

class MyClass {
  @override
  Type get runtimeType => int;
}
''',
      [lint(19, 72)],
    );
  }

  Future<void> test_switchStatement() async {
    await assertDiagnostics(
      '''
void f(num i) {
  switch (i.runtimeType) {
    case const (int):
      break;
    case const (double):
      break;
    default:
      break;
  }
}
''',
      [lint(18, 127)],
    );
  }

  Future<void> test_switchStatement_other() async {
    await assertNoDiagnostics('''
void f(num i) {
  switch (i) {
    case int _:
      break;
    case double _:
      break;
  }
}
''');
  }

  Future<void> test_switchStatement_override() async {
    await assertDiagnostics(
      '''
void f(MyClass i) {
  switch (i.runtimeType) {
    case const (MyClass):
      break;
    default:
      break;
  }
}

class MyClass {
  @override
  Type get runtimeType => int;
}
''',
      [lint(18, 93)],
    );
  }
}
