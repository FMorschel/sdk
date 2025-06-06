// Copyright (c) 2021, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analysis_server/src/protocol_server.dart' show SourceEdit;
import 'package:analysis_server/src/services/correction/fix/pubspec/fix_generator.dart';
import 'package:analysis_server_plugin/edit/fix/fix.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:analyzer/source/file_source.dart';
import 'package:analyzer/src/pubspec/pubspec_validator.dart'
    as pubspec_validator;
import 'package:analyzer/src/test_utilities/resource_provider_mixin.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

abstract class PubspecFixTest with ResourceProviderMixin {
  /// The content of the pubspec file that is being tested.
  late String content;

  /// The result of parsing the [content].
  late YamlNode node;

  /// The error to be fixed.
  late Diagnostic diagnostic;

  /// Return the kind of fixes being tested by this test class.
  FixKind get kind;

  Future<void> assertHasFix(String expected) async {
    var fixes = await _getFixes();
    expect(fixes, hasLength(1));
    var fix = fixes[0];
    expect(fix.kind, kind);
    var edits = fix.change.edits;
    expect(fixes, hasLength(1));
    var actual = SourceEdit.applySequence(content, edits[0].edits);
    expect(actual, expected);
  }

  Future<void> assertHasNoFix(String initialContent) async {
    var fixes = await _getFixes();
    expect(fixes, hasLength(0));
  }

  void validatePubspec(String content) {
    this.content = content;
    var pubspecFile = newFile('/home/test/pubspec.yaml', content);
    var node = loadYamlNode(content);
    this.node = node;
    var errors = pubspec_validator.validatePubspec(
      source: FileSource(pubspecFile),
      contents: node,
      provider: resourceProvider,
    );
    expect(errors.length, 1);
    diagnostic = errors[0];
  }

  Future<List<Fix>> _getFixes() async {
    var generator = PubspecFixGenerator(
      resourceProvider,
      diagnostic,
      content,
      node,
    );
    return await generator.computeFixes();
  }
}
