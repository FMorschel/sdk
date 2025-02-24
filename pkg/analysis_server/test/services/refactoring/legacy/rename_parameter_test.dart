// Copyright (c) 2014, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:linter/src/lint_names.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'abstract_rename.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(RenamePositionalParameterTest);
  });
}

@reflectiveTest
class RenamePositionalParameterTest extends RenameRefactoringTest {
  Future<void> test_subclass_override() async {
    await indexTestUnit('''
class C {
  void m(int? a) {}
}
class D extends C {
  @override
  void m(int? a) {} // marker
}
''');
    createRenameRefactoringAtString('a) {} // marker');
    expect(refactoring.refactoringName, 'Rename Parameter');
    expect(refactoring.elementKindName, 'parameter');
    expect(refactoring.oldName, 'a');
    refactoring.newName = 'b';
    return assertSuccessfulRefactoring('''
class C {
  void m(int? a) {}
}
class D extends C {
  @override
  void m(int? b) {} // marker
}
''');
  }

  @soloTest
  Future<void> test_subclass_override_lint() async {
    createAnalysisOptionsFile(
      lints: [LintNames.avoid_renaming_method_parameters],
    );
    await indexTestUnit('''
class C {
  void m(int? a) {}
}
class D extends C {
  @override
  void m(int? a) {} // marker
}
''');
    createRenameRefactoringAtString('a) {} // marker');
    expect(refactoring.refactoringName, 'Rename Parameter');
    expect(refactoring.elementKindName, 'parameter');
    expect(refactoring.oldName, 'a');
    refactoring.newName = 'b';
    return assertSuccessfulRefactoring('''
class C {
  void m(int? b) {}
}
class D extends C {
  @override
  void m(int? b) {} // marker
}
''');
  }

  Future<void> test_superclass_override() async {
    await indexTestUnit('''
class C {
  void m(int? a) {} // marker
}
class D extends C {
  @override
  void m(int? a) {}
}
''');
    createRenameRefactoringAtString('a) {} // marker');
    expect(refactoring.refactoringName, 'Rename Parameter');
    expect(refactoring.elementKindName, 'parameter');
    expect(refactoring.oldName, 'a');
    refactoring.newName = 'b';
    return assertSuccessfulRefactoring('''
class C {
  void m(int? b) {} // marker
}
class D extends C {
  @override
  void m(int? a) {}
}
''');
  }

  @soloTest
  Future<void> test_superclass_override_lint() async {
    createAnalysisOptionsFile(
      lints: [LintNames.avoid_renaming_method_parameters],
    );
    await indexTestUnit('''
class C {
  void m(int? a) {} // marker
}
class D extends C {
  @override
  void m(int? a) {}
}
''');
    createRenameRefactoringAtString('a) {} // marker');
    expect(refactoring.refactoringName, 'Rename Parameter');
    expect(refactoring.elementKindName, 'parameter');
    expect(refactoring.oldName, 'a');
    refactoring.newName = 'b';
    return assertSuccessfulRefactoring('''
class C {
  void m(int? b) {} // marker
}
class D extends C {
  @override
  void m(int? b) {}
}
''');
  }
}
