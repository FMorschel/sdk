// Copyright (c) 2025, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analysis_server/src/services/correction/fix.dart';
import 'package:analysis_server/src/services/correction/util.dart';
import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/element/element2.dart';
import 'package:analyzer/src/dart/ast/ast.dart';
import 'package:analyzer/src/dart/element/element.dart';
import 'package:analyzer/src/dart/resolver/scope.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';
import 'package:analyzer_plugin/utilities/range_factory.dart';
import 'package:collection/collection.dart';

class MergeCombinators extends MultiCorrectionProducer {
  MergeCombinators({required super.context});

  @override
  Future<List<ResolvedCorrectionProducer>> get producers async {
    var node = this.node;
    NamespaceDirective? directive;
    if (node case Combinator(:NamespaceDirective parent)) {
      directive = parent;
    } else if (node is NamespaceDirective) {
      directive = node;
    } else {
      return const [];
    }

    var combinators = directive.combinators;
    if (combinators.length < 2) {
      return const [];
    }

    if (combinators.whereType<ShowCombinator>().isEmpty) {
      return [
        _MergeCombinators(
          DartFixKind.MERGE_COMBINATORS_HIDE_HIDE,
          directive,
          mergeWithShow: false,
          context: context,
        ),
        _MergeCombinators(
          DartFixKind.MERGE_COMBINATORS_SHOW_HIDE,
          directive,
          mergeWithShow: true,
          context: context,
        ),
      ];
    }

    return [
      _MergeCombinators(
        DartFixKind.MERGE_COMBINATORS_SHOW_SHOW,
        directive,
        mergeWithShow: true,
        context: context,
      ),
      _MergeCombinators(
        DartFixKind.MERGE_COMBINATORS_HIDE_SHOW,
        directive,
        mergeWithShow: false,
        context: context,
      ),
    ];
  }
}

class _MergeCombinators extends ResolvedCorrectionProducer {
  static final namespaceBuilder = NamespaceBuilder();

  @override
  final FixKind fixKind;

  final bool mergeWithShow;
  final NamespaceDirective directive;

  _MergeCombinators(
    this.fixKind,
    this.directive, {
    required this.mergeWithShow,
    required super.context,
  });

  @override
  CorrectionApplicability get applicability =>
      CorrectionApplicability.singleLocation;

  @override
  Future<void> compute(ChangeBuilder builder) async {
    LibraryElement2? element;
    Map<String, Element2> namespace;
    Namespace? originalNamespace;
    switch (directive) {
      case ExportDirective(:LibraryExportElementImpl libraryExport):
        element = libraryExport.exportedLibrary2;
        if (element is! LibraryElementImpl) {
          return;
        }
        originalNamespace = _originalNamespace(element);
        namespace = _currentNamespace(libraryExport).definedNames2;
      case ImportDirective(:var libraryImport?):
        namespace = getImportNamespace(libraryImport);
        element = libraryImport.importedLibrary2;
      default:
        return;
    }
    if (element is! LibraryElementImpl) {
      return;
    }

    if (mergeWithShow) {
      var referencedNames = namespace.keys.toList();
      await _buildNewCombinator(builder, Keyword.SHOW, referencedNames);
      return;
    }

    originalNamespace ??= _originalNamespace(element);

    var explicitlyHiddenNames =
        directive.combinators.whereType<HideCombinator>().expand((combinator) {
          return combinator.hiddenNames
              .map((identifier) => identifier.element?.name3)
              .nonNulls;
        }).toSet();

    var hiddenNames =
        {
          ...explicitlyHiddenNames,
          ...originalNamespace.hiddenNames(
            explicitlyHiddenNames..addAll(namespace.keys),
          ),
        }.toList();
    await _buildNewCombinator(builder, Keyword.HIDE, hiddenNames);
  }

  Future<void> _buildNewCombinator(
    ChangeBuilder builder,
    Keyword keyword,
    List<String> names,
  ) async {
    if (getCodeStyleOptions(unitResult.file).sortCombinators) {
      names.sort();
    }
    await builder.addDartFileEdit(file, (builder) {
      var combinator = '';
      if (names.isNotEmpty) {
        combinator = ' ${keyword.lexeme} ${names.join(', ')}';
      }
      var combinators = directive.combinators;
      builder.addSimpleReplacement(
        range.startOffsetEndOffset(combinators.offset - 1, combinators.end),
        combinator,
      );
    });
  }

  Namespace _currentNamespace(LibraryExportElementImpl libraryExport) {
    return namespaceBuilder.createExportNamespaceForDirective2(libraryExport);
  }

  Namespace _originalNamespace(LibraryElementImpl element) {
    return namespaceBuilder.createExportNamespaceForLibrary(element);
  }
}

extension on Namespace {
  Iterable<String> hiddenNames(Set<String> currentNames) {
    return definedNames2.entries.keys.whereNot(currentNames.contains);
  }
}

extension on NodeList<Combinator> {
  int get end => endToken!.end;
  int get offset => beginToken!.offset;
}
