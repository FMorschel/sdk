// Copyright (c) 2018, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analysis_server/src/services/correction/fix.dart';
import 'package:analyzer/error/error.dart';
import 'package:analyzer/src/error/codes.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';
import 'package:linter/src/lint_names.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'fix_processor.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(MergeHideUsingHideTest);
    defineReflectiveTests(MergeHideUsingShowTest);
    defineReflectiveTests(MergeShowUsingHideTest);
    defineReflectiveTests(MergeShowUsingShowTest);
  });
}

@reflectiveTest
class MergeHideUsingHideTest extends _MergeCombinatorTest {
  @override
  ErrorCode get errorCode => WarningCode.MULTIPLE_COMBINATORS;

  @override
  FixKind get kind => DartFixKind.MERGE_COMBINATORS_HIDE_HIDE;

  Future<void> test_hide() async {
    await resolveTestCode('''
import 'other.dart' hide Future, Stream;
''');
    await assertNoFix();
  }

  Future<void> test_hide_hide() async {
    await resolveTestCode('''
import 'other.dart' hide Stream, Future hide Future;
''');
    await assertHasFix('''
import 'other.dart' hide Stream, Future;
''', errorFilter: errorCodeFilter);
  }

  Future<void> test_hide_hide_lint() async {
    createAnalysisOptionsFile(lints: [LintNames.combinators_ordering]);
    await resolveTestCode('''
import 'other.dart' hide Stream, Future hide Future;
''');
    await assertHasFix('''
import 'other.dart' hide Future, Stream;
''', errorFilter: errorCodeFilter);
  }

  Future<void> test_hide_show() async {
    await resolveTestCode('''
import 'other.dart' hide Future, Stream show FutureOr;
''');
    await assertNoFix(errorFilter: errorCodeFilter);
  }

  Future<void> test_show() async {
    await resolveTestCode('''
import 'other.dart' show Future, Stream;
''');
    await assertNoFix();
  }

  Future<void> test_show_hide() async {
    await resolveTestCode('''
import 'other.dart' show FutureOr, Stream, Future hide Stream;
''');
    await assertNoFix(errorFilter: errorCodeFilter);
  }

  Future<void> test_show_show() async {
    await resolveTestCode('''
import 'other.dart' show Stream, FutureOr, Future show Stream, FutureOr;
''');
    await assertNoFix(errorFilter: errorCodeFilter);
  }
}

@reflectiveTest
class MergeHideUsingShowTest extends _MergeCombinatorTest {
  @override
  ErrorCode get errorCode => WarningCode.MULTIPLE_COMBINATORS;

  @override
  FixKind get kind => DartFixKind.MERGE_COMBINATORS_SHOW_HIDE;

  Future<void> test_hide() async {
    await resolveTestCode('''
import 'other.dart' hide Future, Stream;
''');
    await assertNoFix();
  }

  Future<void> test_hide_hide() async {
    await resolveTestCode('''
import 'other.dart' hide Future, Stream hide Stream;
''');
    await assertHasFix('''
import 'other.dart' show Completer, FutureOr, Timer;
''', errorFilter: errorCodeFilter);
  }

  Future<void> test_hide_hide_lint() async {
    createAnalysisOptionsFile(lints: [LintNames.combinators_ordering]);
    await resolveTestCode('''
import 'other.dart' hide Future, Stream hide Stream;
''');
    await assertHasFix('''
import 'other.dart' show Completer, FutureOr, Timer;
''', errorFilter: errorCodeFilter);
  }

  Future<void> test_hide_show() async {
    await resolveTestCode('''
import 'other.dart' hide Future, Stream show FutureOr;
''');
    await assertNoFix(errorFilter: errorCodeFilter);
  }

  Future<void> test_show() async {
    await resolveTestCode('''
import 'other.dart' show Future, Stream;
''');
    await assertNoFix();
  }

  Future<void> test_show_hide() async {
    await resolveTestCode('''
import 'other.dart' show FutureOr, Stream, Future hide Stream;
''');
    await assertNoFix(errorFilter: errorCodeFilter);
  }

  Future<void> test_show_show() async {
    await resolveTestCode('''
import 'other.dart' show Stream, FutureOr, Future show Stream, FutureOr;
''');
    await assertNoFix(errorFilter: errorCodeFilter);
  }
}

@reflectiveTest
class MergeShowUsingHideTest extends _MergeCombinatorTest {
  @override
  ErrorCode get errorCode => WarningCode.MULTIPLE_COMBINATORS;

  @override
  FixKind get kind => DartFixKind.MERGE_COMBINATORS_HIDE_SHOW;

  Future<void> test_hide() async {
    await resolveTestCode('''
import 'other.dart' hide Future, Stream;
''');
    await assertNoFix();
  }

  Future<void> test_hide_hide() async {
    await resolveTestCode('''
import 'other.dart' hide Future, Stream hide Stream;
''');
    await assertNoFix(errorFilter: errorCodeFilter);
  }

  Future<void> test_hide_show() async {
    await resolveTestCode('''
import 'other.dart' hide Future, Stream show FutureOr;
''');
    await assertHasFix('''
import 'other.dart' hide Future, Stream, Completer, Timer;
''', errorFilter: errorCodeFilter);
  }

  Future<void> test_hide_show_lint() async {
    createAnalysisOptionsFile(lints: [LintNames.combinators_ordering]);
    await resolveTestCode('''
import 'other.dart' hide Future, Stream show FutureOr;
''');
    await assertHasFix('''
import 'other.dart' hide Completer, Future, Stream, Timer;
''', errorFilter: errorCodeFilter);
  }

  Future<void> test_show() async {
    await resolveTestCode('''
import 'other.dart' show Future, Stream;
''');
    await assertNoFix();
  }

  Future<void> test_show_hide() async {
    await resolveTestCode('''
import 'other.dart' show FutureOr, Stream, Future hide Stream;
''');
    await assertHasFix('''
import 'other.dart' hide Stream, Completer, Timer;
''', errorFilter: errorCodeFilter);
  }

  Future<void> test_show_hide_lint() async {
    createAnalysisOptionsFile(lints: [LintNames.combinators_ordering]);
    await resolveTestCode('''
import 'other.dart' show FutureOr, Stream, Future hide Stream;
''');
    await assertHasFix('''
import 'other.dart' hide Completer, Stream, Timer;
''', errorFilter: errorCodeFilter);
  }

  Future<void> test_show_show() async {
    await resolveTestCode('''
import 'other.dart' show Stream, FutureOr, Future show Stream, FutureOr;
''');
    await assertHasFix('''
import 'other.dart' hide Completer, Future, Timer;
''', errorFilter: errorCodeFilter);
  }
}

@reflectiveTest
class MergeShowUsingShowTest extends _MergeCombinatorTest {
  @override
  ErrorCode get errorCode => WarningCode.MULTIPLE_COMBINATORS;

  @override
  FixKind get kind => DartFixKind.MERGE_COMBINATORS_SHOW_SHOW;

  Future<void> test_hide() async {
    await resolveTestCode('''
import 'other.dart' hide Future, Stream;
''');
    await assertNoFix();
  }

  Future<void> test_hide_hide() async {
    await resolveTestCode('''
import 'other.dart' hide Future, Stream hide Stream;
''');
    await assertNoFix(errorFilter: errorCodeFilter);
  }

  Future<void> test_hide_show() async {
    await resolveTestCode('''
import 'other.dart' hide Future, Stream show FutureOr, Completer;
''');
    await assertHasFix('''
import 'other.dart' show FutureOr, Completer;
''', errorFilter: errorCodeFilter);
  }

  Future<void> test_hide_show_lint() async {
    createAnalysisOptionsFile(lints: [LintNames.combinators_ordering]);
    await resolveTestCode('''
import 'other.dart' hide Future, Stream show FutureOr, Completer;
''');
    await assertHasFix('''
import 'other.dart' show Completer, FutureOr;
''', errorFilter: errorCodeFilter);
  }

  Future<void> test_show() async {
    await resolveTestCode('''
import 'other.dart' show Future, Stream;
''');
    await assertNoFix();
  }

  Future<void> test_show_hide() async {
    await resolveTestCode('''
import 'other.dart' show FutureOr, Stream, Future hide Stream;
''');
    await assertHasFix('''
import 'other.dart' show FutureOr, Future;
''', errorFilter: errorCodeFilter);
  }

  Future<void> test_show_hide_lint() async {
    createAnalysisOptionsFile(lints: [LintNames.combinators_ordering]);
    await resolveTestCode('''
import 'other.dart' show FutureOr, Stream, Future hide Stream;
''');
    await assertHasFix('''
import 'other.dart' show Future, FutureOr;
''', errorFilter: errorCodeFilter);
  }

  Future<void> test_show_show() async {
    await resolveTestCode('''
import 'other.dart' show Stream, FutureOr, Future show Stream, FutureOr;
''');
    await assertHasFix('''
import 'other.dart' show Stream, FutureOr;
''', errorFilter: errorCodeFilter);
  }

  Future<void> test_show_show_lint() async {
    createAnalysisOptionsFile(lints: [LintNames.combinators_ordering]);
    await resolveTestCode('''
import 'other.dart' show Stream, FutureOr, Future show Stream, FutureOr;
''');
    await assertHasFix('''
import 'other.dart' show FutureOr, Stream;
''', errorFilter: errorCodeFilter);
  }
}

abstract class _MergeCombinatorTest extends FixProcessorErrorCodeTest {
  @override
  void setUp() {
    super.setUp();
    newFile(join(testPackageLibPath, 'other.dart'), '''
class Completer {}
class Stream {}
class Future {}
class FutureOr {}
class Timer {}
''');
  }
}
