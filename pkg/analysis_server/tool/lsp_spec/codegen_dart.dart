// Copyright (c) 2018, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:collection';

import 'package:analysis_server/src/services/correction/sort_members.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/src/analysis_options/code_style_options.dart';
import 'package:analyzer/src/dart/analysis/analysis_options.dart';
import 'package:analyzer_plugin/protocol/protocol_common.dart';
import 'package:analyzer_utilities/tools.dart';
import 'package:collection/collection.dart';
import 'package:dart_style/dart_style.dart';

import 'generate_all.dart';
import 'meta_model.dart';

final formatter = DartFormatter(
  // The language_server_protocol package is currently still using a lower
  // SDK constraint so pre-commit hooks require it matches short style.
  languageVersion: DartFormatter.latestShortStyleLanguageVersion,
);

final _canParseFunctions = SplayTreeMap<String, String>();
Map<String, Interface> _interfaces = {};
Map<String, LspEnum> _namespaces = {};
Map<String, List<String>> _subtypes = {};
Map<String, TypeAlias> _typeAliases = {};
final _unionFunctions = SplayTreeMap<String, String>();

/// Whether our enum class allows any value (eg. should always return true
/// from canParse() for the correct type). This is to allow us to have some
/// type safety for these values but without restricting which values are allowed.
/// This is to support things like custom error codes and also future changes
/// in the spec (it's important the server doesn't crash on deserializing
/// newer values).
bool enumClassAllowsAnyValue(String name) {
  // The types listed here are the ones that have a guaranteed restricted type
  // in the LSP spec, for example:
  //
  //   export type CompletionTriggerKind = 1 | 2 | 3;
  //
  // The other enum types use string/number/etc. in the referencing classes.
  return name != 'CompletionTriggerKind' &&
      name != 'FailureHandlingKind' &&
      name != 'InsertTextFormat' &&
      name != 'MarkupKind' &&
      name != 'ResourceOperationKind' &&
      name != 'TraceValue';
}

/// Generates the ultimate Dart code for [types], sorted and formatted.
String generateDartForTypes(List<LspEntity> types) {
  var content = _sortContent(_buildContent(types));

  var stopwatch = Stopwatch()..start();
  var formattedCode = _formatCode(content);
  stopwatch.stop();
  if (stopwatch.elapsed.inSeconds > 3) {
    print('WARN: Formatting took ${stopwatch.elapsed} (${types.length} types)');
  }
  return '${formattedCode.trim()}\n'; // Ensure a single trailing newline.
}

void recordTypes(List<LspEntity> types) {
  types.whereType<TypeAlias>().forEach(
    (alias) => _typeAliases[alias.name] = alias,
  );
  types.whereType<Interface>().forEach((interface) {
    _interfaces[interface.name] = interface;
    // Keep track of our base classes so they can look up their super classes
    // later in their fromJson() to deserialize into the most specific type.
    for (var base in interface.baseTypes) {
      var subTypes = _subtypes[base.dartType] ??= <String>[];
      subTypes.add(interface.name);
    }
  });
  types.whereType<LspEnum>().forEach(
    (namespace) => _namespaces[namespace.name] = namespace,
  );
  _sortSubtypes();
}

/// Resolves [type] to its base type if it is a reference to another type.
///
/// If [resolveEnums] is `true`, will resolve them to the type of their values.
///
/// If [onlyRenames] is true, references to [TypeAlias]es will only be resolved
/// if they are renames.
TypeBase resolveTypeAlias(
  TypeBase type, {
  bool resolveEnums = false,
  bool onlyRenames = false,
}) {
  if (type is TypeReference) {
    if (resolveEnums) {
      // Enums are no longer recorded with TypeAliases (as they were in the
      // Markdown/TS spec) so must be resolved explicitly to their base types.
      var enum_ = _namespaces[type.name];
      if (enum_ != null) {
        return enum_.typeOfValues;
      }
    }

    var alias = _typeAliases[type.name];
    if (alias != null && (!onlyRenames || alias.renameReferences)) {
      // Resolve aliases recursively.
      var resolved = alias.baseType;
      for (int i = 0; i < 10; i++) {
        var newResolved = resolveTypeAlias(
          resolved,
          resolveEnums: resolveEnums,
          onlyRenames: onlyRenames,
        );
        if (newResolved == resolved) {
          return resolved;
        }
        resolved = newResolved;
      }
      throw 'Failed to resolve type after 10 iterations: ${alias.name}';
    }
  }
  return type;
}

/// Builds the Dart code for [types].
String _buildContent(List<LspEntity> types) {
  _canParseFunctions.clear();
  _unionFunctions.clear();
  var buffer = IndentableStringBuffer();
  for (var type in types) {
    _writeType(buffer, type);
  }
  for (var function in _canParseFunctions.values) {
    buffer.writeln(function);
  }
  for (var function in _unionFunctions.values) {
    buffer.writeln(function);
  }
  return buffer.toString();
}

String _determineVariableName(
  Interface interface,
  Iterable<String> suggestions,
) {
  var fieldNames = _getAllFields(interface).map((f) => f.name).toList();
  var suggestion = suggestions.firstWhereOrNull((s) => !fieldNames.contains(s));
  if (suggestion != null) {
    return suggestion;
  }
  var first = suggestions.firstOrNull ?? 'var';
  for (var i = 1; true; i++) {
    var suggestion = '$first$i';
    if (!fieldNames.contains(suggestion)) {
      return suggestion;
    }
  }
}

String _formatCode(String code) {
  try {
    code = formatter.format(code);
  } catch (e) {
    print('Failed to format code, returning unformatted code.');
  }
  return code;
}

/// Recursively gets all members from superclasses and returns them sorted
/// alphabetically.
List<Field> _getAllFields(Interface? interface) =>
    _getSortedUnique(_getAllFieldsMap(interface).values.toList());

/// Recursively gets all members from superclasses keyed by field name.
Map<String, Field> _getAllFieldsMap(Interface? interface) {
  // Handle missing interfaces (such as special cased interfaces that won't
  // be included in this model).
  if (interface == null) {
    return {};
  }

  // It's possible our interface redefines something in a base type (for example
  // where the base has `String` but this type overrides it with a literal such
  // as `ResourceOperation`) so use a map to keep the most-specific by name.
  return {
    for (final baseType in interface.baseTypes)
      ..._getAllFieldsMap(_interfaces[baseType.name]),
    for (final field in interface.members.whereType<Field>()) field.name: field,
  };
}

/// Returns a copy of the list sorted by name with duplicates (by name+type) removed.
List<N> _getSortedUnique<N extends LspEntity>(List<N> items) {
  var uniqueByName = <String, N>{};
  for (var item in items) {
    // It's fine to have the same name used for different types (eg. namespace +
    // type alias) but some types are just duplicated entirely in the spec in
    // different positions which should not be emitted twice.
    var nameTypeKey = '${item.name}|${item.runtimeType}';
    if (uniqueByName.containsKey(nameTypeKey)) {
      // At the time of writing, there were two duplicated types:
      // - TextDocumentSyncKind (same definition in both places)
      // - TextDocumentSyncOptions (first definition is just a subset)
      // If this list grows, consider handling this better - or try to have the
      // spec updated to be unambiguous.
      print('WARN: More than one definition for $nameTypeKey.');
    }

    // Keep the last one as in some cases the first definition is less specific.
    uniqueByName[nameTypeKey] = item;
  }
  var sortedList = uniqueByName.values.toList();
  sortedList.sort((item1, item2) => item1.name.compareTo(item2.name));
  return sortedList;
}

String _getTypeCheckFailureMessage(TypeBase type) {
  type = resolveTypeAlias(type);

  if (type is LiteralType) {
    return "must be the literal '\$literal'";
  } else if (type is LiteralUnionType) {
    return "must be one of the \${literals.map((e) => \"'\$e'\").join(', ')}";
  } else {
    return 'must be of type ${type.dartTypeWithTypeArgs}';
  }
}

bool _isOverride(Interface interface, Field field) {
  for (var parentType in interface.baseTypes) {
    var parent = _interfaces[parentType.name];
    if (parent != null) {
      if (parent.members.any((m) => m.name == field.name)) {
        return true;
      }
      if (_isOverride(parent, field)) {
        return true;
      }
    }
  }
  return false;
}

bool _isSimpleType(TypeBase type) {
  const literals = ['num', 'String', 'bool', 'int'];
  return type is TypeReference && literals.contains(type.dartType);
}

bool _isSpecType(TypeBase type) {
  type = resolveTypeAlias(type);
  return type is TypeReference &&
      type != TypeReference.lspObject &&
      type != TypeReference.lspAny &&
      (_interfaces.containsKey(type.name) ||
          (_namespaces.containsKey(type.name)));
}

bool _isUriType(TypeBase type) {
  type = resolveTypeAlias(type);
  return type is TypeReference && type.dartType == 'Uri';
}

/// Maps reserved words and identifiers that cause issues in field names.
String _makeValidIdentifier(String identifier) {
  // Some identifiers used in LSP are reserved words in Dart, so map them to
  // other values.
  const map = {
    'Object': 'Obj',
    'String': 'Str',
    'class': 'class_',
    'enum': 'enum_',
    'null': 'null_',
  };
  return map[identifier] ?? identifier;
}

/// Returns the name of the possibly enclosed types,
/// to be used as a unique name for that type.
String _memberNameForType(TypeBase type) {
  if (type is LiteralType) {
    return 'Literal';
  }
  if (type is LiteralUnionType) {
    return 'LiteralUnion';
  }
  if (type is TypeReference) {
    type = resolveTypeAlias(type);
  }

  var dartType =
      type is NullableType
          ? '${type.dartType}?'
          : type is UnionType
          ? type.types.map(_memberNameForType).join()
          : type is ArrayType
          ? 'List${_memberNameForType(type.elementType)}'
          : type is MapType
          ? 'Map${_memberNameForType(type.indexType)}${_memberNameForType(type.valueType)}'
          : type.dartType;
  return capitalize(dartType.replaceAll('?', 'Nullable'));
}

String _rewriteCommentReference(String comment) {
  var commentReferencePattern = RegExp(r'\[([\w ]+)\]\(#(\w+)\)');
  return comment.replaceAllMapped(commentReferencePattern, (m) {
    var description = m.group(1);
    var reference = m.group(2);
    if (description == reference) {
      return '[$reference]';
    } else {
      return '$description ([$reference])';
    }
  });
}

/// Sorts [content] as a Dart library.
String _sortContent(String content) {
  var parseResult = parseString(content: content);
  var codeOptions = CodeStyleOptionsImpl(useFormatter: true);
  codeOptions.options = AnalysisOptionsImpl();
  var sorter = MemberSorter(
    content,
    parseResult.unit,
    codeOptions,
    parseResult.lineInfo,
  );
  var edits = sorter.sort();
  return SourceEdit.applySequence(content, edits);
}

/// Sorts subtypes into a consistent order.
///
/// Subtypes will be sorted such that types with the most required fields appear
/// first to ensure `fromJson` constructors delegate to the most specific type.
void _sortSubtypes() {
  int requiredFieldCount(String interfaceName) =>
      _interfaces[interfaceName]!.members
          .whereType<Field>()
          .where((field) => !field.allowsUndefined && !field.allowsNull)
          .length;
  int optionalFieldCount(String interfaceName) =>
      _interfaces[interfaceName]!.members
          .whereType<Field>()
          .where((field) => field.allowsUndefined || field.allowsNull)
          .length;
  for (var entry in _subtypes.entries) {
    var subtypes = entry.value;
    subtypes.sort((subtype1, subtype2) {
      var requiredFields1 = requiredFieldCount(subtype1);
      var requiredFields2 = requiredFieldCount(subtype2);
      var optionalFields1 = optionalFieldCount(subtype1);
      var optionalFields2 = optionalFieldCount(subtype2);
      return requiredFields1 != requiredFields2
          ? requiredFields2.compareTo(requiredFields1)
          : optionalFields1 != optionalFields2
          ? optionalFields2.compareTo(optionalFields1)
          : subtype1.compareTo(subtype2);
    });
  }
}

/// Returns a String representing the underlying Dart type for the provided
/// spec [type].
///
/// This is `Map<String, Object?>` for complex types but can be a simple type
/// for enums.
String _specJsonType(TypeBase type) {
  if (type is TypeReference && _namespaces.containsKey(type.name)) {
    var valueType = _namespaces[type.name]!.typeOfValues;
    return valueType.dartTypeWithTypeArgs;
  }
  return 'Map<String, Object?>';
}

Iterable<String> _wrapLines(List<String> lines, int maxLength) sync* {
  lines = lines.map((l) => l.trimRight()).toList();
  for (var line in lines) {
    while (true) {
      if (line.length <= maxLength) {
        yield line;
        break;
      } else {
        // First try to wrap at the last space before the max length, and fall
        // back to wrapping at the first space if there were none before the
        // max length.
        var lastSpace = line.lastIndexOf(' ', maxLength);
        if (lastSpace == -1) {
          lastSpace = line.indexOf(' ');
        }

        // If we still don't have one, the whole line has no spaces to split on.
        if (lastSpace == -1) {
          yield line;
          break;
        }

        yield line.substring(0, lastSpace);
        line = line.substring(lastSpace + 1);
      }
    }
  }
}

void _writeCanParseMethod(IndentableStringBuffer buffer, Interface interface) {
  buffer
    ..writeIndentedln(
      'static bool canParse(Object? obj, LspJsonReporter reporter) {',
    )
    ..indent()
    ..writeIndentedln('if (obj is Map<String, Object?>) {')
    ..indent();
  // In order to consider this valid for parsing, all fields that must not be
  // undefined must be present and also type check for the correct type.
  // Any fields that are optional but present, must still type check.
  var fields =
      _getAllFields(
        interface,
      ).whereNot((f) => isNullableAnyType(f.type)).toList();
  for (var i = 0; i < fields.length; i++) {
    var field = fields[i];
    var type = field.type;
    var functionName = '_canParse${_memberNameForType(type)}';
    var invocation =
        "$functionName(obj, reporter, '${field.name}', "
        'allowsUndefined: ${field.allowsUndefined}, allowsNull: ${field.allowsNull}'
        '${type is LiteralType ? ', literal: ${type.valueAsLiteral}' : ''}'
        '${type is LiteralUnionType ? ', literals: {${type.literalTypes.map((t) => t.valueAsLiteral).join(', ')}}' : ''}'
        ')';

    if (i == fields.length - 1) {
      buffer.writeIndentedln('return $invocation;');
    } else {
      buffer
        ..writeIndentedln('if (!$invocation) {')
        ..indent()
        ..writeIndentedln('return false;')
        ..outdent()
        ..writeIndentedln('}');
    }
    if (!_canParseFunctions.containsKey(functionName)) {
      var temp = IndentableStringBuffer();
      _writeCanParseType(temp, interface, type, functionName);
      _canParseFunctions[functionName] = temp.toString();
    }
  }
  if (fields.isEmpty) {
    buffer.writeIndentedln('return true;');
  }
  buffer
    ..outdent()
    ..writeIndentedln('} else {')
    ..indent()
    ..writeIndentedln(
      "reporter.reportError('must be of type ${interface.name}');",
    )
    ..writeIndentedln('return false;')
    ..outdent()
    ..writeIndentedln('}')
    ..outdent()
    ..writeIndentedln('}');
}

void _writeCanParseType(
  IndentableStringBuffer buffer,
  Interface? interface,
  TypeBase type,
  String functionName,
) {
  buffer.writeln(
    'bool $functionName(Map<String, Object?> map, LspJsonReporter reporter, '
    'String fieldName, {required bool allowsUndefined, required bool allowsNull'
    '${type is LiteralType ? ', required String literal' : ''}'
    '${type is LiteralUnionType ? ', required Iterable<String> literals' : ''}'
    '}) {',
  );

  buffer
    ..writeIndentedln('reporter.push(fieldName);')
    ..writeIndentedln('try {')
    ..indent();
  buffer
    ..writeIndentedln('if (!allowsUndefined && !map.containsKey(fieldName)) {')
    ..indent()
    ..writeIndentedln("reporter.reportError('must not be undefined');")
    ..writeIndentedln('return false;')
    ..outdent()
    ..writeIndentedln('}');

  buffer.writeIndentedln('final value = map[fieldName];');
  buffer.writeIndentedln('final nullCheck = allowsNull || allowsUndefined;');
  buffer
    ..writeIndentedln('if (!nullCheck && value == null) {')
    ..indent()
    ..writeIndentedln("reporter.reportError('must not be null');")
    ..writeIndentedln('return false;')
    ..outdent()
    ..writeIndentedln('}');

  buffer.writeIndented('if ((!nullCheck || value != null) && ');
  _writeTypeCheckCondition(
    buffer,
    interface,
    'value',
    type,
    'reporter',
    negation: true,
    parenForCollection: true,
  );

  var failureMessage = _getTypeCheckFailureMessage(type);
  var quote = failureMessage.contains("'") ? '"' : "'";

  buffer
    ..write(') {')
    ..indent();
  if (!_isSpecType(type)) {
    // Only report an error for non-spec types, as spec types will have reported
    // their own error in the nested canParse() call.
    buffer.writeIndentedln(
      'reporter.reportError($quote$failureMessage$quote);',
    );
  }
  buffer
    ..writeIndentedln('return false;')
    ..outdent()
    ..writeIndentedln('}')
    ..outdent()
    ..writeIndentedln('} finally {')
    ..indent()
    ..writeIndentedln('reporter.pop();')
    ..outdent()
    ..writeIndentedln('}')
    ..writeIndentedln('return true;');

  buffer.writeln('}');
}

void _writeConst(IndentableStringBuffer buffer, Constant cons) {
  _writeDocCommentsAndAnnotations(buffer, cons);
  buffer.writeIndentedln('static const ${cons.name} = ${cons.valueAsLiteral};');
}

void _writeConstructor(IndentableStringBuffer buffer, Interface interface) {
  var allFields = _getAllFields(interface);
  if (allFields.isEmpty) {
    return;
  }
  buffer
    ..writeIndented('${interface.name}({')
    ..write(
      allFields.map((field) {
        var isLiteral = field.type is LiteralType;
        var isRequired =
            !isLiteral &&
            !field.allowsNull &&
            !field.allowsUndefined &&
            !isNullableAnyType(field.type);
        var requiredKeyword = isRequired ? 'required' : '';
        var valueCode =
            isLiteral ? ' = ${(field.type as LiteralType).valueAsLiteral}' : '';
        return '$requiredKeyword this.${field.name}$valueCode, ';
      }).join(),
    )
    ..write('})');
  var fieldsWithValidation =
      allFields.where((f) => f.type is LiteralType).toList();
  if (fieldsWithValidation.isNotEmpty) {
    buffer
      ..writeIndentedln(' {')
      ..indent();
    for (var field in fieldsWithValidation) {
      var type = field.type;
      if (type is LiteralType) {
        buffer
          ..writeIndentedln('if (${field.name} != ${type.valueAsLiteral}) {')
          ..indent()
          ..writeIndentedln(
            "throw '${field.name} may only be the literal ${type.valueAsLiteral.replaceAll("'", "\\'")}';",
          )
          ..outdent()
          ..writeIndentedln('}');
      }
    }
    buffer
      ..outdent()
      ..writeIndentedln('}');
  } else {
    buffer.writeln(';');
  }
}

void _writeDocCommentsAndAnnotations(
  IndentableStringBuffer buffer,
  LspEntity node,
) {
  var comment = node.comment?.trim();
  if (comment != null && comment.isNotEmpty) {
    comment = _rewriteCommentReference(comment);
    var originalLines = comment.split('\n');
    // Wrap at 80 - 4 ('/// ') - indent characters.
    var wrappedLines = _wrapLines(
      originalLines,
      (80 - 4 - buffer.totalIndent).clamp(0, 80),
    );
    for (var l in wrappedLines) {
      buffer.writeIndentedln('/// $l'.trim());
    }
  }
  // Marking LSP-deprecated fields as deprecated in Dart results in a lot
  // of warnings because we still often populate these fields for clients that
  // may still be using them. This code is useful for enabling temporarily
  // and reviewing which deprecated fields we should still support but isn't
  // generally useful to keep enabled.
  // if (node.isDeprecated) {
  //   buffer.writeIndentedln('@core.deprecated');
  // }
}

void _writeEnumClass(IndentableStringBuffer buffer, LspEnum namespace) {
  _writeDocCommentsAndAnnotations(buffer, namespace);
  var consts = namespace.members.cast<Constant>().toList();
  var namespaceName = namespace.name;
  var typeOfValues = namespace.typeOfValues;
  var allowsAnyValue = enumClassAllowsAnyValue(namespaceName);
  var constructorName = allowsAnyValue ? '' : '._';
  var dartType = typeOfValues.dartTypeWithTypeArgs;

  buffer
    ..writeln('class $namespaceName implements ToJsonable {')
    ..indent()
    ..writeIndentedln('const $namespaceName$constructorName(this._value);')
    ..writeIndentedln('const $namespaceName.fromJson(this._value);')
    ..writeln()
    ..writeIndentedln('final $dartType _value;')
    ..writeln()
    ..writeIndented(
      'static bool canParse(Object? obj, LspJsonReporter reporter) ',
    );
  if (allowsAnyValue) {
    buffer.writeIndentedln('=> ');
    _writeTypeCheckCondition(buffer, null, 'obj', typeOfValues, 'reporter');
    buffer.writeln(';');
  } else {
    buffer
      ..writeIndentedln('{')
      ..indent()
      ..writeIndentedln('switch (obj) {')
      ..indent();
    for (var cons in consts) {
      buffer.writeIndentedln('case ${cons.valueAsLiteral}:');
    }
    buffer
      ..indent()
      ..writeIndentedln('return true;')
      ..outdent()
      ..outdent()
      ..writeIndentedln('}')
      ..writeIndentedln('return false;')
      ..outdent()
      ..writeIndentedln('}');
  }
  namespace.members.whereType<Constant>().forEach((cons) {
    // We don't use any deprecated enum values, so omit them entirely.
    if (cons.isDeprecated) {
      return;
    }
    _writeDocCommentsAndAnnotations(buffer, cons);
    var memberName = _makeValidIdentifier(cons.name);
    var value = cons.valueAsLiteral;
    buffer.writeIndentedln(
      'static const $memberName = $namespaceName$constructorName($value);',
    );
  });
  buffer
    ..writeln()
    ..writeIndentedln('@override $dartType toJson() => _value;')
    ..writeln()
    ..writeIndentedln('@override String toString() => _value.toString();')
    ..writeln()
    ..writeIndentedln('@override int get hashCode => _value.hashCode;')
    ..writeln()
    ..writeIndentedln(
      '@override bool operator ==(Object other) => other is $namespaceName && other._value == _value;',
    )
    ..outdent()
    ..writeln('}')
    ..writeln();
}

void _writeEquals(IndentableStringBuffer buffer, Interface interface) {
  buffer
    ..writeIndentedln('@override')
    ..writeIndentedln('bool operator ==(Object other) {')
    ..indent()
    // We want an exact type match, but also need `is` to have the analyzer
    // promote the type to allow access to the fields on `other`.
    ..writeIndentedln(
      'return other is ${interface.name} && other.runtimeType == ${interface.name}',
    )
    ..indent()
    ..writeIndented('');
  for (var field in _getAllFields(interface)) {
    buffer.write(' && ');
    var type = resolveTypeAlias(field.type);
    var thisName = field.name;
    var otherName = 'other.${field.name}';
    if (type is ArrayType || type is MapType) {
      buffer.write(
        'const DeepCollectionEquality().equals($thisName, $otherName)',
      );
    } else {
      buffer.write('$thisName == $otherName');
    }
  }
  buffer
    ..writeln(';')
    ..outdent()
    ..outdent()
    ..writeIndentedln('}');
}

void _writeField(
  IndentableStringBuffer buffer,
  Interface interface,
  Field field,
) {
  _writeDocCommentsAndAnnotations(buffer, field);
  var needsNullable =
      (field.allowsNull || field.allowsUndefined) &&
      !isNullableAnyType(field.type);
  if (_isOverride(interface, field)) {
    buffer.writeIndentedln('@override');
  }
  buffer
    ..writeIndented('final ')
    ..write(field.type.dartTypeWithTypeArgs)
    ..write(needsNullable ? '?' : '')
    ..writeln(' ${field.name};');
}

void _writeFromJsonCode(
  IndentableStringBuffer buffer,
  TypeBase type,
  String valueCode, {
  required bool allowsNull,
  bool requiresCast = true,
}) {
  type = resolveTypeAlias(type);
  var nullOperator = allowsNull ? '?' : '';
  var cast =
      requiresCast &&
              // LSPAny
              !isNullableAnyType(type) &&
              // LSPObject marked as optional
              !(isObjectType(type) && allowsNull)
          ? ' as ${type.dartTypeWithTypeArgs}$nullOperator'
          : '';

  if (_isSimpleType(type)) {
    buffer.write('$valueCode$cast');
  } else if (_isUriType(type)) {
    if (allowsNull) {
      buffer.write('$valueCode != null ? ');
    }
    buffer
      ..write('Uri.parse(')
      ..write(requiresCast ? '$valueCode as String' : valueCode)
      ..write(')');
    if (allowsNull) {
      buffer.write(': null');
    }
  } else if (_isSpecType(type)) {
    // Our own types have fromJson() constructors we can call.
    if (allowsNull) {
      buffer.write('$valueCode != null ? ');
    }
    buffer
      ..write('${type.dartType}.fromJson${type.typeArgsString}')
      ..write('($valueCode as ${_specJsonType(type)})');
    if (allowsNull) {
      buffer.write(': null');
    }
  } else if (type is ArrayType) {
    // Lists need to be map()'d so we can recursively call writeFromJsonCode
    // as they may need fromJson on each element.
    var listCast = requiresCast ? ' as List<Object?>$nullOperator' : '';
    var leftParen = requiresCast ? '(' : '';
    var rightParen = requiresCast ? ')' : '';
    buffer.write(
      '$leftParen$valueCode$listCast$rightParen$nullOperator.map((item) => ',
    );
    _writeFromJsonCode(buffer, type.elementType, 'item', allowsNull: false);
    buffer.write(').toList()');
  } else if (type is MapType) {
    // Maps need to be map()'d so we can recursively call writeFromJsonCode as
    // they may need fromJson on each key or value.
    var mapCast = requiresCast ? ' as Map<Object, Object?>$nullOperator' : '';
    buffer
      ..write('($valueCode$mapCast)$nullOperator.map(')
      ..write('(key, value) => MapEntry(');
    _writeFromJsonCode(buffer, type.indexType, 'key', allowsNull: false);
    buffer.write(', ');
    _writeFromJsonCode(buffer, type.valueType, 'value', allowsNull: false);
    buffer.write('))');
  } else if (type is LiteralUnionType) {
    _writeFromJsonCodeForLiteralUnion(
      buffer,
      type,
      valueCode,
      allowsNull: allowsNull,
    );
  } else if (type is UnionType) {
    var functionName = type.types.map(_memberNameForType).join();

    functionName = '_either$functionName';

    if (allowsNull) {
      buffer.write('$valueCode == null ? null : ');
    }
    buffer.write('$functionName($valueCode)');
    if (!_unionFunctions.containsKey(functionName)) {
      var temp = IndentableStringBuffer();
      _writeFromJsonCodeForUnion(temp, type, functionName);
      _unionFunctions[functionName] = temp.toString();
    }
  } else {
    buffer.write('$valueCode$cast');
  }
}

void _writeFromJsonCodeForLiteralUnion(
  IndentableStringBuffer buffer,
  LiteralUnionType union,
  String valueCode, {
  required bool allowsNull,
}) {
  var allowedValues = [
    if (allowsNull) null,
    ...union.literalTypes.map((t) => t.valueAsLiteral),
  ];
  var valueType = union.literalTypes.first.dartTypeWithTypeArgs;
  var cast = ' as $valueType${allowsNull ? '?' : ''}';
  buffer.write(
    "const {${allowedValues.join(', ')}}.contains($valueCode) ? $valueCode$cast : "
    "throw \"\$$valueCode was not one of (${allowedValues.join(', ')})\"",
  );
}

void _writeFromJsonCodeForUnion(
  IndentableStringBuffer buffer,
  UnionType union,
  String functionName,
) {
  buffer
    ..writeln('${union.dartTypeWithTypeArgs} $functionName(Object? value) {')
    ..indent()
    ..writeIndented('return ');

  // Write a check against each type, eg.:
  // x is y ? Either.tx(x) : (...)
  var hasIncompleteCondition = false;

  for (var i = 0; i < union.types.length; i++) {
    var type = union.types[i];
    var isAny = isNullableAnyType(type);

    // "any" matches all type checks, so only emit it if required.
    if (!isAny) {
      _writeTypeCheckCondition(
        buffer,
        null,
        'value',
        type,
        'nullLspJsonReporter',
      );
      buffer.write(' ? ');
    }

    // The code to construct a value with this "side" of the union.
    buffer.write('${union.dartType}.t${i + 1}(');
    // Call recursively as unions may be nested.
    _writeFromJsonCode(
      buffer,
      type,
      'value',
      // null + type checks are already handled above this loop
      allowsNull: false,
      requiresCast: false,
    );
    buffer.write(')');

    // If we output the type condition at the top, prepare for the next condition.
    if (!isAny) {
      buffer.write(' : ');
      hasIncompleteCondition = true;
    } else {
      hasIncompleteCondition = false;
    }
  }
  // Fill the final parens with a throw because if we fell through all of the
  // cases then the value we had didn't match any of the types in the union.
  if (hasIncompleteCondition) {
    buffer.write(
      "throw '\$value was not one of (${union.types.map((t) => t.dartTypeWithTypeArgs).join(', ')})'",
    );
  }
  buffer
    ..writeln(';')
    ..outdent()
    ..writeln('}');
}

void _writeFromJsonConstructor(
  IndentableStringBuffer buffer,
  Interface interface,
) {
  var allFields = _getAllFields(interface);
  buffer
    ..writeIndentedln(
      'static ${interface.name} '
      'fromJson(Map<String, Object?> json) {',
    )
    ..indent();
  // First check whether any of our subclasses can deserialize this.
  for (var subclassName in _subtypes[interface.name] ?? const <String>[]) {
    var subclass = _interfaces[subclassName]!;
    buffer
      ..writeIndentedln(
        'if (${subclass.name}.canParse(json, nullLspJsonReporter)) {',
      )
      ..indent()
      ..writeIndentedln('return ${subclass.name}.fromJson(json);')
      ..outdent()
      ..writeIndentedln('}');
  }
  if (interface.abstract) {
    buffer.writeIndentedln(
      'throw ArgumentError('
      "'Supplied map is not valid for any subclass of ${interface.name}'"
      ');',
    );
  } else {
    for (var field in allFields) {
      // Add a local variable to allow type promotion (and avoid multiple lookups).
      var localName = _makeValidIdentifier(field.name);
      var localNameJson = '${localName}Json';
      buffer.writeIndentedln("final $localNameJson = json['${field.name}'];");
      buffer.writeIndented('final $localName = ');
      _writeFromJsonCode(
        buffer,
        field.type,
        localNameJson,
        allowsNull: field.allowsNull || field.allowsUndefined,
      );
      buffer.writeln(';');
    }
    buffer
      ..writeIndented('return ${interface.name}(')
      ..write(allFields.map((field) => '${field.name}: ${field.name}, ').join())
      ..writeln(');');
  }
  buffer
    ..outdent()
    ..writeIndented('}');
}

void _writeGetter(IndentableStringBuffer buffer, AbstractGetter getter) {
  _writeDocCommentsAndAnnotations(buffer, getter);
  buffer
    ..writeIndented(getter.type.dartTypeWithTypeArgs)
    ..writeln(' get ${getter.name};');
}

void _writeHashCode(IndentableStringBuffer buffer, Interface interface) {
  buffer
    ..writeIndentedln('@override')
    ..writeIndented('int get hashCode => ');

  var fields = _getAllFields(interface);

  String endWith;
  if (fields.isEmpty) {
    buffer.write('42');
    endWith = ';';
  } else if (fields.length == 1) {
    endWith = ';';
  } else if (fields.length > 20) {
    buffer.write('Object.hashAll([');
    endWith = ',]);';
  } else {
    buffer.write('Object.hash(');
    endWith = ',);';
  }

  buffer.writeAll(
    fields.map((field) {
      var type = resolveTypeAlias(field.type);
      if (type is ArrayType || type is MapType) {
        return 'lspHashCode(${field.name})';
      } else {
        if (fields.length == 1) {
          return '${field.name}.hashCode';
        }
        return field.name;
      }
    }),
    ',',
  );
  buffer
    ..writeln(endWith)
    ..writeln();
}

void _writeInterface(IndentableStringBuffer buffer, Interface interface) {
  var isPrivate = interface.name.startsWith('_');
  _writeDocCommentsAndAnnotations(buffer, interface);

  buffer
    ..writeIndented(interface.abstract ? 'abstract ' : '')
    ..write('class ${interface.name} ');
  var allBaseTypes =
      interface.baseTypes.map((t) => t.dartTypeWithTypeArgs).toList();
  allBaseTypes.add('ToJsonable');
  if (allBaseTypes.isNotEmpty) {
    buffer.writeIndented('implements ${allBaseTypes.join(', ')} ');
  }
  buffer
    ..writeln('{')
    ..indent();
  if (!isPrivate) {
    _writeJsonHandler(buffer, interface);
    buffer.writeln();
  }
  _writeConstructor(buffer, interface);
  buffer.writeln();
  _writeFromJsonConstructor(buffer, interface);
  buffer.writeln();
  // Handle Consts and Fields separately, since we need to include superclass
  // Fields.
  var consts = interface.members.whereType<Constant>().toList();
  var getters = interface.members.whereType<AbstractGetter>().toList();
  var fields = _getAllFields(interface);
  _writeMembers(buffer, interface, getters);
  buffer.writeln();
  _writeMembers(buffer, interface, consts);
  buffer.writeln();
  _writeMembers(buffer, interface, fields);
  buffer.writeln();
  _writeToJsonMethod(buffer, interface);
  buffer.writeln();
  _writeCanParseMethod(buffer, interface);
  buffer.writeln();
  _writeEquals(buffer, interface);
  buffer.writeln();
  _writeHashCode(buffer, interface);
  buffer.writeln();
  _writeToString(buffer, interface);
  buffer
    ..outdent()
    ..writeIndentedln('}')
    ..writeln();
}

void _writeJsonHandler(IndentableStringBuffer buffer, Interface interface) {
  buffer
    ..writeIndented('static const jsonHandler = ')
    ..write('LspJsonHandler(')
    ..write('${interface.name}.canParse, ${interface.name}.fromJson,')
    ..writeln(');')
    ..writeln();
}

void _writeJsonMapAssignment(
  IndentableStringBuffer buffer,
  Field field,
  String mapName,
) {
  // If we are allowed to be undefined, we'll only add the value if set.
  var shouldBeOmittedIfNoValue = field.allowsUndefined;
  if (shouldBeOmittedIfNoValue) {
    buffer
      ..writeIndentedln('if (${field.name} != null) {')
      ..indent();
  }
  // Use the correct null operator depending on whether the value could be null.
  var nullOp = field.allowsNull || field.allowsUndefined ? '?' : '';
  buffer.writeIndented('''$mapName['${field.name}'] = ''');
  _writeToJsonCode(buffer, field.type, field.name, nullOp);
  buffer.writeln(';');
  if (shouldBeOmittedIfNoValue) {
    buffer
      ..outdent()
      ..writeIndentedln('}');
  }
}

void _writeMember(
  IndentableStringBuffer buffer,
  Interface interface,
  Member member,
) {
  if (member is Field) {
    _writeField(buffer, interface, member);
  } else if (member is Constant) {
    _writeConst(buffer, member);
  } else if (member is AbstractGetter) {
    _writeGetter(buffer, member);
  } else {
    throw 'Unknown type';
  }
}

void _writeMembers(
  IndentableStringBuffer buffer,
  Interface interface,
  List<Member> members,
) {
  _getSortedUnique(members).forEach((m) => _writeMember(buffer, interface, m));
}

void _writeToJsonCode(
  IndentableStringBuffer buffer,
  TypeBase type,
  String valueCode,
  String nullOp,
) {
  if (_isSpecType(type)) {
    buffer.write('$valueCode$nullOp.toJson()');
  } else if (type is ArrayType && _isSpecType(type.elementType)) {
    buffer.write('$valueCode$nullOp.map((item) => ');
    _writeToJsonCode(buffer, type.elementType, 'item', '');
    buffer.write(').toList()');
  } else if (type is MapType &&
      (_isUriType(type.indexType) || _isUriType(type.valueType))) {
    buffer.write('$valueCode$nullOp.map((key, value) => MapEntry(');
    _writeToJsonCode(buffer, type.indexType, 'key', '');
    buffer.write(', ');
    _writeToJsonCode(buffer, type.valueType, 'value', '');
    buffer.write('))');
  } else if (_isUriType(type)) {
    buffer.write('$valueCode$nullOp.toString()');
  } else {
    buffer.write(valueCode);
  }
}

void _writeToJsonFieldsForResponseMessage(
  IndentableStringBuffer buffer,
  Interface interface,
  String mapName,
) {
  var allFields = _getAllFields(interface);
  var standardFields = allFields.where(
    (f) => f.name != 'error' && f.name != 'result',
  );

  for (var field in standardFields) {
    _writeJsonMapAssignment(buffer, field, mapName);
  }

  // Write special code for result/error so that only one is populated.
  buffer
    ..writeIndentedln('if (error != null && result != null) {')
    ..indent()
    ..writeIndentedln('''throw 'result and error cannot both be set';''')
    ..outdent()
    ..writeIndentedln('} else if (error != null) {')
    ..indent()
    ..writeIndentedln('''$mapName['error'] = error;''')
    ..outdent()
    ..writeIndentedln('} else {')
    ..indent()
    ..writeIndentedln('''$mapName['result'] = result;''')
    ..outdent()
    ..writeIndentedln('}');
}

void _writeToJsonMethod(IndentableStringBuffer buffer, Interface interface) {
  var fields = _getAllFields(interface);

  buffer
    ..writeIndentedln('@override')
    ..writeIndented('Map<String, Object?> toJson() ');
  if (fields.isEmpty) {
    buffer
      ..writeln('=> {};')
      ..writeln();
    return;
  }

  var mapName = _determineVariableName(interface, [
    'result',
    'map',
    'json',
    'toReturn',
    'results',
    'value',
    'values',
  ]);
  buffer
    ..writeln('{')
    ..indent()
    ..writeIndentedln('var $mapName = <String, Object?>{};');
  // ResponseMessage must confirm to JSON-RPC which says only one of
  // result/error can be included. Since this isn't encoded in the types we
  // need to special-case it's toJson generation.
  if (interface.name == 'ResponseMessage') {
    _writeToJsonFieldsForResponseMessage(buffer, interface, mapName);
  } else {
    for (var field in fields) {
      _writeJsonMapAssignment(buffer, field, mapName);
    }
  }
  buffer
    ..writeIndentedln('return $mapName;')
    ..outdent()
    ..writeIndentedln('}');
}

void _writeToString(IndentableStringBuffer buffer, Interface interface) {
  buffer
    ..writeIndentedln('@override')
    ..writeIndentedln('String toString() => jsonEncoder.convert(toJson());');
}

void _writeType(IndentableStringBuffer buffer, LspEntity type) {
  if (type is Interface) {
    _writeInterface(buffer, type);
  } else if (type is LspEnum) {
    _writeEnumClass(buffer, type);
  } else if (type is TypeAlias) {
    _writeTypeAlias(buffer, type);
  } else {
    throw 'Unknown type';
  }
}

void _writeTypeAlias(IndentableStringBuffer buffer, TypeAlias alias) {
  if (!alias.generateTypeDef) return;
  var baseType = alias.baseType;
  var typeName = baseType.dartTypeWithTypeArgs;
  _writeDocCommentsAndAnnotations(buffer, alias);
  buffer.writeIndentedln('typedef ${alias.name} = $typeName;');
}

void _writeTypeCheckCondition(
  IndentableStringBuffer buffer,
  Interface? interface,
  String valueCode,
  TypeBase type,
  String reporter, {
  bool negation = false,
  bool parenForCollection = false,
}) {
  type = resolveTypeAlias(type);

  var dartType = type.dartType;
  var fullDartType = type.dartTypeWithTypeArgs;

  var operator = negation ? '!' : '';
  var and = negation ? '||' : '&&';
  var or = negation ? '&&' : '||';
  var every = negation ? 'any' : 'every';
  var equals = negation ? '!=' : '==';
  var notEqual = negation ? '==' : '!=';
  var true_ = negation ? 'false' : 'true';

  if (isNullableAnyType(type)) {
    buffer.write(true_);
  } else if (isObjectType(type)) {
    buffer.write('$valueCode $notEqual null');
  } else if (_isSimpleType(type)) {
    buffer.write('$valueCode is$operator $fullDartType');
  } else if (_isUriType(type)) {
    buffer.write(
      '($valueCode is$operator String $and '
      'Uri.tryParse($valueCode) $notEqual null)',
    );
  } else if (type is LiteralType) {
    buffer.write('$valueCode $equals literal');
  } else if (type is LiteralUnionType) {
    buffer.write('${operator}literals.contains(value)');
  } else if (_isSpecType(type)) {
    buffer.write('$operator$dartType.canParse($valueCode, $reporter)');
  } else if (type is ArrayType) {
    if (parenForCollection) {
      buffer.write('(');
    }
    buffer.write('$valueCode is$operator List<Object?>');
    if (fullDartType != 'Object?') {
      buffer.write(' $and $valueCode.$every((item) => ');
      _writeTypeCheckCondition(
        buffer,
        interface,
        'item',
        type.elementType,
        reporter,
        negation: negation,
      );
      buffer.write(')');
    }
    if (parenForCollection) {
      buffer.write(')');
    }
  } else if (type is MapType) {
    if (parenForCollection) {
      buffer.write('(');
    }
    buffer.write('$valueCode is$operator Map');
    if (fullDartType != 'Object?') {
      buffer
        ..write(' $and (')
        ..write('$valueCode.keys.$every((item) => ');
      _writeTypeCheckCondition(
        buffer,
        interface,
        'item',
        type.indexType,
        reporter,
        negation: negation,
      );
      buffer.write('$and $valueCode.values.$every((item) => ');
      _writeTypeCheckCondition(
        buffer,
        interface,
        'item',
        type.valueType,
        reporter,
        negation: negation,
      );
      buffer.write(')))');
    }
    if (parenForCollection) {
      buffer.write(')');
    }
  } else if (type is UnionType) {
    if (parenForCollection) {
      buffer.write('(');
    }

    // To type check a union, we just recursively check against each of its types.
    for (var i = 0; i < type.types.length; i++) {
      if (i != 0) {
        buffer.write(' $or ');
      }
      _writeTypeCheckCondition(
        buffer,
        interface,
        valueCode,
        type.types[i],
        reporter,
        negation: negation,
      );
    }
    if (parenForCollection) {
      buffer.write(')');
    }
  } else {
    throw 'Unable to type check $valueCode against $fullDartType';
  }
}

class IndentableStringBuffer extends StringBuffer {
  int _indentLevel = 0;
  final int _indentSpaces = 2;

  int get totalIndent => _indentLevel * _indentSpaces;

  String get _indentString => ' ' * totalIndent;

  void indent() => _indentLevel++;

  void outdent() => _indentLevel--;

  void writeIndented(Object obj) {
    write(_indentString);
    write(obj);
  }

  void writeIndentedln(Object obj) {
    write(_indentString);
    writeln(obj);
  }
}
