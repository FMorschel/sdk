// Copyright (c) 2018, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analysis_server/src/services/correction/assist.dart';
import 'package:analysis_server/src/services/correction/fix.dart';
import 'package:analyzer_plugin/utilities/assist/assist.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import '../assist/assist_processor.dart';
import 'fix_processor.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(MergeShowUsingShowTest);
  });
}

FixKind a = DartFixKind.MERGE_COMBINATORS_SHOW_SHOW;

var type = FixProcessorTest;

/*
I was taking a look at creating the fix for this. And I noticed `LibraryImport` and `LibraryExport` have no relation besides being an `ElementDirective`. More to this, I was thinking if we could also add a `Namespace` to `LibraryExport` so this fix is easier to generate for `export` directives too.

Thoughts @scheglov42 ?

This new diagnostic will trigger the following code for having multiple combinators:

```dart
export 'dart:async' [!show Future, Stream show Future!];
```
*/

@reflectiveTest
class MergeShowUsingShowTest extends AssistProcessorTest {
  // @override
  // FixKind get kind => DartFixKind.MERGE_COMBINATORS_SHOW_SHOW;

  @override
  AssistKind get kind => DartAssistKind.TMP;

  Future<void> test_merge_hide_hide() async {
    await resolveTestCode('''
import 'dart:async' hide Future, Stream hide Stream;
''');
    await assertHasAssistAt('hide', '''
import 'dart:async' hide Future, Stream;
''');
  }

  @soloTest
  Future<void> test_merge_hide_show() async {
    await resolveTestCode('''
import 'dart:async' hide Future, Stream show FutureOr;
''');
    await assertHasAssistAt('hide', '''
import 'dart:async' hide Future, Completer, Timer, unawaited, Stream, StreamIterator, StreamSubscription, StreamTransformer;
''');
  }

  Future<void> test_merge_show_hide() async {
    await resolveTestCode('''
import 'dart:async' show Future, Stream hide Stream;
''');
    await assertHasAssistAt('show', '''
import 'dart:async' show Future;
''');
  }

  Future<void> test_merge_show_show() async {
    await resolveTestCode('''
import 'dart:async' show Future, Stream show Stream;
''');
    await assertHasAssistAt('show', '''
import 'dart:async' show Stream;
''');
  }

  Future<void> test_single_hide() async {
    await resolveTestCode('''
import 'dart:async' hide Future, Stream;
''');
    await assertNoAssist();
  }

  Future<void> test_single_show() async {
    await resolveTestCode('''
import 'dart:async' show Future, Stream;
''');
    await assertNoAssist();
  }
}
