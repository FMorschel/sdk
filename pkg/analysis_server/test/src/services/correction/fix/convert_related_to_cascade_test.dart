// Copyright (c) 2024, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analysis_server/src/services/correction/fix.dart';
import 'package:analyzer/error/error.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';
import 'package:linter/src/lint_names.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'fix_processor.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(ConvertRelatedToCascadeTest);
  });
}

@reflectiveTest
class ConvertRelatedToCascadeTest extends FixProcessorLintTest {
  @override
  FixKind get kind => DartFixKind.CONVERT_RELATED_TO_CASCADE;

  @override
  String get lintCode => LintNames.cascade_invocations;

  bool Function(AnalysisError) get _firstError {
    var hasError = false;
    return (error) {
      if (!hasError && error.errorCode.name == LintNames.cascade_invocations) {
        hasError = true;
        return true;
      }
      return false;
    };
  }

  bool Function(AnalysisError) errorFilterLine(int line) {
    return (error) {
      var lineInfo = LineInfo.fromContent(error.source.contents.data);
      return lineInfo.getLocation(error.offset).lineNumber == line;
    };
  }

  Future<void> test_declaration_method_method() async {
    await resolveTestCode('''
class A {
  void m() {}
}
void f() {
  final a = A();
  a.m();
  a.m();
}
''');
    await assertHasFix('''
class A {
  void m() {}
}
void f() {
  final a = A()
  ..m()
  ..m();
}
''', errorFilter: _firstError);
  }

  Future<void> test_method_method_property() async {
    await resolveTestCode('''
class A {
  void m() {}
  int? x;
}
void f(A a) {
  a.m();
  a.m();
  a.x = 1;
}
''');
    await assertHasFix('''
class A {
  void m() {}
  int? x;
}
void f(A a) {
  a..m()
  ..m()
  ..x = 1;
}
''', errorFilter: _firstError);
  }

  Future<void> test_multipleDeclaration_first_method() async {
    await resolveTestCode('''
class A {
  void m() {}
}
void f() {
  final a = A(), a2 = A();
  a.m();
}
''');
    await assertNoFix();
  }

  Future<void> test_multipleDeclaration_last_method() async {
    await resolveTestCode('''
class A {
  void m() {}
}
void f() {
  final a = A(), a2 = A();
  a2.m();
}
''');
    await assertNoFix();
  }

  Future<void> test_property_cascadeMethod_cascadeMethod() async {
    await resolveTestCode('''
class A {
  void m() {}
  int? x;
}

void f(A a) {
  a.x = 1;
  a..m();
  a..m();
}
''');
    await assertHasFix('''
class A {
  void m() {}
  int? x;
}

void f(A a) {
  a..x = 1
  ..m()
  ..m();
}
''', errorFilter: _firstError);
  }

  Future<void> test_property_property_method_method() async {
    await resolveTestCode('''
class A {
  void m() {}
  int? x;
}

void f(A a) {
  a..x = 1
  ..x = 2;
  a.m();
  a.m();
}
''');
    await assertHasFix('''
class A {
  void m() {}
  int? x;
}

void f(A a) {
  a..x = 1
  ..x = 2
  ..m()
  ..m();
}
''', errorFilter: errorFilterLine(9));
    await assertHasFix('''
class A {
  void m() {}
  int? x;
}

void f(A a) {
  a..x = 1
  ..x = 2
  ..m()
  ..m();
}
''', errorFilter: errorFilterLine(10));
  }

  Future<void> test_property_property_property() async {
    await resolveTestCode('''
class A {
  void m() {}
  int? x;
}
void f(A a) {
  a.x = 1;
  a.x = 2;
  a.x = 3;
}
''');
    await assertHasFix('''
class A {
  void m() {}
  int? x;
}
void f(A a) {
  a..x = 1
  ..x = 2
  ..x = 3;
}
''', errorFilter: _firstError);
  }
}
