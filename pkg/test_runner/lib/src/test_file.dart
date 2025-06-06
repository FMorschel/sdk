// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
import 'dart:io';

import 'package:shell_arg_splitter/shell_arg_splitter.dart';

import 'feature.dart';
import 'path.dart';
import 'static_error.dart';
import 'utils.dart';

final _multitestRegExp = RegExp(r"//# \w+:");

final _vmOptionsRegExp = RegExp(r"^[ \t]*// VMOptions=(.*)", multiLine: true);
final _environmentRegExp =
    RegExp(r"^[ \t]*// Environment=(.*)", multiLine: true);
final _packagesRegExp = RegExp(r"^[ \t]*// Packages=(.*)", multiLine: true);
final _experimentRegExp = RegExp(r"^--enable-experiment=([a-z0-9,-]+)$");
final _localFileRegExp = RegExp(
    r"""^[ \t]*(?:import(?: augment)?|part)\s*"""
    r"""['"](?!package:|dart:)(.*?)['"]\s*"""
    r"""(?:(?:deferred\s+)?as\s+\w+\s*)?"""
    r"""(?:(?:show|hide)\s+\w+\s*(?:,\s*\w+\s*))*;""",
    multiLine: true);

List<T> _parseOption<T>(
    String filePath, String contents, String name, T Function(String) convert,
    {bool allowMultiple = false}) {
  var matches = RegExp('^[ \t]*// $name=(.*)', multiLine: true)
      .allMatches(contents)
      .toList();
  if (!allowMultiple && matches.length > 1) {
    throw FormatException('More than one "// $name=" line in test $filePath');
  }

  var options = <T>[];
  for (var match in matches) {
    for (var option in splitLine(match[1]!)) {
      options.add(convert(option));
    }
  }

  return options;
}

List<String> _parseStringOption(String filePath, String contents, String name,
        {bool allowMultiple = false}) =>
    _parseOption<String>(filePath, contents, name, (string) => string,
        allowMultiple: allowMultiple);

abstract class _TestFileBase {
  /// The test suite directory containing this test.
  final Path? _suiteDirectory;

  /// The full path to the test file.
  final Path path;

  /// The path to the original multitest file this test was generated from.
  ///
  /// If this test was not generated from a multitest, just returns [path].
  Path get originPath;

  /// The parsed error expectation markers in this test, if it is a static
  /// error test.
  ///
  /// If empty, the test is not a static error test.
  final List<StaticError> expectedErrors;

  /// The name of the multitest section this file corresponds to if it was
  /// generated from a multitest. Otherwise, returns an empty string.
  String get multitestKey;

  /// If the test contains static error expectations, it's a "static error
  /// test".
  ///
  /// These tests exist to validate that a front end reports the right static
  /// errors. Unless the expected errors are all warnings, a static error test
  /// is skipped on configurations that are not purely front end.
  bool get isStaticErrorTest => expectedErrors.isNotEmpty;

  /// If the test contains any web-specific (`[web]`) static error expectations,
  /// then it's a "web static error test".
  ///
  /// These tests exist to validate that a Dart web compiler reports the right
  /// expected errors.
  bool get isWebStaticErrorTest =>
      expectedErrors.any((error) => error.source == ErrorSource.web);

  /// If the tests has no static error expectations, or all of the expectations
  /// are warnings, then the test tests runtime semantics.
  ///
  /// Note that this is *not* the negation of [isStaticErrorTest]. A test that
  /// contains only warning expectations is both a static "error" test and a
  /// runtime test. The test runner will validate that the front ends produce
  /// the expected warnings *and* that a runtime also correctly executes the
  /// test.
  bool get isRuntimeTest => expectedErrors.every((error) => error.isWarning);

  /// A hash code used to spread tests across shards.
  int get shardHash {
    // The VM C++ unit tests have a special fake TestFile with no suite
    // directory or path. Don't crash in that case.
    if (_suiteDirectory == null) {
      return path.toString().hashCode;
    }

    return originPath.relativeTo(_suiteDirectory).toString().hashCode;
  }

  _TestFileBase(this._suiteDirectory, this.path, this.expectedErrors);

  /// The logical name of the test.
  ///
  /// This is its path relative to the test suite directory containing it,
  /// minus any file extension. If this test was split from a multitest,
  /// it contains the multitest key.
  String get name {
    var testNamePath = originPath.relativeTo(_suiteDirectory!);
    var directory = testNamePath.directoryPath;
    var filenameWithoutExt = testNamePath.filenameWithoutExtension;

    String join(String base, String part) {
      if (base.isEmpty) return part;
      if (part.isEmpty) return base;
      return "$base/$part";
    }

    var result = "$directory";
    result = join(result, filenameWithoutExt);
    result = join(result, multitestKey);
    return result;
  }
}

/// Represents a single ".dart" file used as a test and the parsed metadata it
/// contains.
///
/// Special options for individual tests are currently specified in various
/// ways: with comments directly in test files, by using certain imports, or
/// by creating additional files in the test directories.
///
/// Here is a list of options that are used by 'test.dart' today:
///
/// *   Flags can be passed to the VM process that runs the test by adding a
///     comment to the test file:
///
///         // VMOptions=--flag1 --flag2
///
/// *   Flags can be passed to dart2js, VM or dartdevc by adding a comment to
///     the test file:
///
///         // SharedOptions=--flag1 --flag2
///
/// *   Flags can be passed to dart2js by adding a comment to the test file:
///
///         // dart2jsOptions=--flag1 --flag2
///
/// *   Flags can be passed to dart2wasm by adding a comment to the test file:
///
///         // dart2wasmOptions=--flag1 --flag2
///
/// *   Flags can be passed to the dart script that contains the test also
///     using comments, as follows:
///
///         // DartOptions=--flag1 --flag2
///
/// *   Extra environment variables can be passed to the process that runs
///     the test by adding comment(s) to the test file:
///
///         // Environment=ENV_VAR1=foo bar
///         // Environment=ENV_VAR2=bazz
///
/// *   Most tests are not web tests, but can (and will be) wrapped within an
///     HTML file and another script file to test them also on browser
///     environments (e.g. language and corelib tests are run this way). We
///     deduce that if a file with the same name as the test, but ending in
///     ".html" instead of ".dart" exists, the test was intended to be a web
///     test and no wrapping is necessary.
///
/// *   This test requires libfoobar.so, libfoobar.dylib or foobar.dll to be in
///     the system linker path of the VM.
///
///         // SharedObjects=foobar
///
/// *   'test.dart' assumes tests fail if the process returns a non-zero exit
///     code (in the case of web tests, we check for PASS/FAIL indications in
///     the test output).
class TestFile extends _TestFileBase {
  /// Read the test file from the given [filePath].
  factory TestFile.read(Path suiteDirectory, String filePath) {
    if (filePath.endsWith('.dill')) {
      return TestFile._(suiteDirectory, Path(filePath), [],
          requirements: [],
          vmOptions: [[]],
          sharedOptions: [],
          dart2jsOptions: [],
          dart2wasmOptions: [],
          ddcOptions: [],
          dartOptions: [],
          packages: null,
          isMultitest: false,
          sharedObjects: [],
          otherResources: [],
          environment: {},
          experiments: []);
    }

    final contents = File(filePath).readAsStringSync();

    // Required features.
    var requirements =
        _parseOption<Feature>(filePath, contents, 'Requirements', (name) {
      for (var feature in Feature.all) {
        if (feature.name == name) return feature;
      }

      throw FormatException('Unknown feature "$name" in test $filePath');
    });

    final isVmIntermediateLanguageTest = filePath.endsWith('_il_test.dart');

    // VM options.
    var vmOptions = <List<String>>[];
    var matches = _vmOptionsRegExp.allMatches(contents);
    for (var match in matches) {
      vmOptions.add(splitLine(match[1]!));
    }
    if (vmOptions.isEmpty) vmOptions.add(<String>[]);

    // Other options.
    var dartOptions = _parseStringOption(filePath, contents, 'DartOptions');
    var sharedOptions = _parseStringOption(filePath, contents, 'SharedOptions');
    var dart2jsOptions =
        _parseStringOption(filePath, contents, 'dart2jsOptions');
    var dart2wasmOptions =
        _parseStringOption(filePath, contents, 'dart2wasmOptions');
    var ddcOptions = _parseStringOption(filePath, contents, 'ddcOptions');
    var otherResources = _parseStringOption(
        filePath, contents, 'OtherResources',
        allowMultiple: true);
    var sharedObjects = _parseStringOption(filePath, contents, 'SharedObjects',
        allowMultiple: true);

    // Extract the experiments from the shared options.
    // TODO(rnystrom): Either tests should stop specifying experiment flags
    // entirely and use "// Requirements=", or we should come up with a better
    // syntax. Parsing from "// SharedOptions=" for now since that's where they
    // are currently specified.
    var experiments = <String>[];
    for (var i = 0; i < sharedOptions.length; i++) {
      var sharedOption = sharedOptions[i];
      if (sharedOption.contains("--enable-experiment")) {
        var match = _experimentRegExp.firstMatch(sharedOption);
        if (match == null) {
          throw Exception(
              "SharedOptions marker cannot mix experiment flags with other "
              "flags. Was:\n$sharedOption");
        }

        experiments.addAll(match[1]!.split(","));
        sharedOptions.removeAt(i);
        i--;
      }
    }

    // Environment.
    var environment = <String, String>{};
    matches = _environmentRegExp.allMatches(contents);
    for (var match in matches) {
      var envDef = match[1]!;
      var name = envDef;
      var value = '';
      var pos = envDef.indexOf('=');
      if (pos >= 0) {
        name = envDef.substring(0, pos);
        value = envDef.substring(pos + 1);
      }
      environment[name] = value;
    }

    // Packages.
    String? packages;

    matches = _packagesRegExp.allMatches(contents);
    for (var match in matches) {
      if (packages != null) {
        throw FormatException(
            'More than one "// Package..." line in test $filePath');
      }
      packages = match[1]!;
      if (packages != 'none') {
        // Packages=none means that no packages option should be given. Any
        // other value overrides packages.
        packages =
            Uri.file(filePath).resolveUri(Uri.file(packages)).toFilePath();
      }
    }

    var isMultitest = _multitestRegExp.hasMatch(contents);
    if (isMultitest) {
      DebugLogger.warning(
          "${Path(filePath).toNativePath()} is a legacy multi-test file.");
    }

    var errorExpectations = <StaticError>[];
    try {
      errorExpectations.addAll(_parseExpectations(filePath));
    } on FormatException catch (error) {
      throw FormatException(
          "Invalid error expectation syntax in $filePath:\n$error");
    }

    return TestFile._(suiteDirectory, Path(filePath), errorExpectations,
        packages: packages,
        environment: environment,
        isMultitest: isMultitest,
        requirements: requirements,
        sharedOptions: sharedOptions,
        dartOptions: dartOptions,
        dart2jsOptions: dart2jsOptions,
        dart2wasmOptions: dart2wasmOptions,
        ddcOptions: ddcOptions,
        vmOptions: vmOptions,
        sharedObjects: sharedObjects,
        otherResources: otherResources,
        experiments: experiments,
        isVmIntermediateLanguageTest: isVmIntermediateLanguageTest);
  }

  /// Parse expectations from the file with [path].
  ///
  /// Recurses to follow local (not `dart:` or `package:`) imports.
  static List<StaticError> _parseExpectations(String path,
      {Set<String>? alreadyParsed}) {
    alreadyParsed ??= {};
    var file = File(path);
    var pathUri = Uri.parse(path);
    // Missing files set no expectations.
    if (!file.existsSync()) return [];

    // Catch import loops.
    if (!alreadyParsed.add(pathUri.toString())) return [];

    // Parse one file.
    var contents = File(path).readAsStringSync();
    var result = StaticError.parseExpectations(path: path, source: contents);

    // Parse imports and recurse.
    var matches = _localFileRegExp.allMatches(contents);
    for (var match in matches) {
      var localPath = Uri.tryParse(match[1]!);
      // Broken import paths set no expectations.
      if (localPath == null) continue;
      var uriString = pathUri.resolve(localPath.path).toString();
      result
          .addAll(_parseExpectations(uriString, alreadyParsed: alreadyParsed));
    }
    return result;
  }

  /// A special fake test file for representing a VM unit test written in C++.
  TestFile.vmUnitTest(String name,
      {required this.hasCompileError,
      required this.hasRuntimeError,
      required this.hasCrash})
      : packages = null,
        environment = {},
        isMultitest = false,
        hasSyntaxError = false,
        hasStaticWarning = false,
        requirements = [],
        sharedOptions = [],
        dartOptions = [],
        dart2jsOptions = [],
        dart2wasmOptions = [],
        ddcOptions = [],
        vmOptions = [],
        sharedObjects = [],
        otherResources = [],
        experiments = [],
        isVmIntermediateLanguageTest = false,
        super(null, Path("/fake/vm/cc/$name"), []);

  TestFile._(Path super.suiteDirectory, super.path, super.expectedErrors,
      {this.packages,
      required this.environment,
      required this.isMultitest,
      required this.requirements,
      required this.sharedOptions,
      required this.dartOptions,
      required this.dart2jsOptions,
      required this.dart2wasmOptions,
      required this.ddcOptions,
      required this.vmOptions,
      required this.sharedObjects,
      required this.otherResources,
      required this.experiments,
      this.isVmIntermediateLanguageTest = false})
      : hasSyntaxError = false,
        hasCompileError = false,
        hasRuntimeError = false,
        hasStaticWarning = false,
        hasCrash = false {
    assert(!isMultitest || dartOptions.isEmpty);
  }

  @override
  Path get originPath => path;

  @override
  String get multitestKey => "";

  final String? packages;

  final Map<String, String> environment;

  final bool isMultitest;
  final bool hasSyntaxError;
  final bool hasCompileError;
  final bool hasRuntimeError;
  final bool hasStaticWarning;
  final bool hasCrash;
  final bool isVmIntermediateLanguageTest;

  /// The features that a test configuration must support in order to run this
  /// test.
  ///
  /// If the current configuration does not support one or more of these
  /// requirements, the test is implicitly skipped.
  final List<Feature> requirements;

  final List<String> sharedOptions;
  final List<String> dartOptions;
  final List<String> dart2jsOptions;
  final List<String> dart2wasmOptions;
  final List<String> ddcOptions;
  final List<List<String>> vmOptions;
  final List<String> sharedObjects;
  final List<String> otherResources;

  /// The experiments this test enables.
  ///
  /// Parsed from a shared options line like:
  ///
  ///     // SharedOptions=--enable-experiment=flubber,gloop
  final List<String> experiments;

  /// Derive a multitest test section file from this multitest file with the
  /// given [multitestKey] and expectations.
  TestFile split(Path path, String multitestKey, String contents,
          {bool hasCompileError = false,
          bool hasRuntimeError = false,
          bool hasStaticWarning = false,
          bool hasSyntaxError = false}) =>
      _MultitestFile(
          this,
          path,
          multitestKey,
          StaticError.parseExpectations(
              path: path.toString(), source: contents),
          hasCompileError: hasCompileError,
          hasRuntimeError: hasRuntimeError,
          hasStaticWarning: hasStaticWarning,
          hasSyntaxError: hasSyntaxError);

  @override
  String toString() => """TestFile(
  packages: $packages
  environment: $environment
  isMultitest: $isMultitest
  hasSyntaxError: $hasSyntaxError
  hasCompileError: $hasCompileError
  hasRuntimeError: $hasRuntimeError
  hasStaticWarning: $hasStaticWarning
  hasCrash: $hasCrash
  requirements: $requirements
  sharedOptions: $sharedOptions
  dartOptions: $dartOptions
  dart2jsOptions: $dart2jsOptions
  dart2wasmOptions: $dart2wasmOptions
  ddcOptions: $ddcOptions
  vmOptions: $vmOptions
  sharedObjects: $sharedObjects
  otherResources: $otherResources
  experiments: $experiments
)""";
}

/// A [TestFile] for a single section file derived from a multitest.
///
/// This inherits most properties from the original test file, but overrides
/// the error flags based on the multitest section's expectation.
class _MultitestFile extends _TestFileBase implements TestFile {
  /// The authored test file that was split to generate this multitest.
  final TestFile _origin;

  @override
  final String multitestKey;

  @override
  final bool hasCompileError;
  @override
  final bool hasRuntimeError;
  @override
  final bool hasStaticWarning;
  @override
  final bool hasSyntaxError;
  @override
  bool get hasCrash => _origin.hasCrash;
  @override
  bool get isVmIntermediateLanguageTest => _origin.isVmIntermediateLanguageTest;

  _MultitestFile(this._origin, Path path, this.multitestKey,
      List<StaticError> expectedErrors,
      {required this.hasCompileError,
      required this.hasRuntimeError,
      required this.hasStaticWarning,
      required this.hasSyntaxError})
      : super(_origin._suiteDirectory, path, expectedErrors);

  @override
  Path get originPath => _origin.path;

  @override
  String? get packages => _origin.packages;

  @override
  List<Feature> get requirements => _origin.requirements;
  @override
  List<String> get dart2jsOptions => _origin.dart2jsOptions;
  @override
  List<String> get dart2wasmOptions => _origin.dart2wasmOptions;
  @override
  List<String> get dartOptions => _origin.dartOptions;
  @override
  List<String> get ddcOptions => _origin.ddcOptions;
  @override
  Map<String, String> get environment => _origin.environment;

  @override
  bool get isMultitest => _origin.isMultitest;

  @override
  List<String> get otherResources => _origin.otherResources;
  @override
  List<String> get sharedObjects => _origin.sharedObjects;
  @override
  List<String> get experiments => _origin.experiments;
  @override
  List<String> get sharedOptions => _origin.sharedOptions;
  @override
  List<List<String>> get vmOptions => _origin.vmOptions;

  @override
  TestFile split(Path path, String multitestKey, String contents,
          {bool hasCompileError = false,
          bool hasRuntimeError = false,
          bool hasStaticWarning = false,
          bool hasSyntaxError = false}) =>
      throw UnsupportedError(
          "Can't derive a test from one already derived from a multitest.");
}
