// Copyright (c) 2020, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:collection';

import 'package:analysis_server/src/services/correction/assist.dart';
import 'package:analysis_server/src/services/correction/fix.dart';
import 'package:analysis_server/src/services/correction/util.dart';
import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element2.dart';
import 'package:analyzer/src/dart/ast/ast.dart';
import 'package:analyzer/src/dart/ast/extensions.dart';
import 'package:analyzer/src/dart/element/element.dart';
import 'package:analyzer/src/dart/resolver/scope.dart';
import 'package:analyzer_plugin/utilities/assist/assist.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';
import 'package:analyzer_plugin/utilities/range_factory.dart';
import 'package:collection/collection.dart';

class ImportAddShow extends ResolvedCorrectionProducer {
  ImportAddShow({required super.context});

  @override
  CorrectionApplicability get applicability =>
      CorrectionApplicability.singleLocation;

  @override
  AssistKind get assistKind => DartAssistKind.IMPORT_ADD_SHOW;

  @override
  Future<void> compute(ChangeBuilder builder) async {
    // prepare ImportDirective
    var importDirective = node.thisOrAncestorOfType<ImportDirective>();
    if (importDirective == null) {
      return;
    }
    // there should be no existing combinators
    if (importDirective.combinators.isNotEmpty) {
      return;
    }
    // prepare whole import namespace
    var importElement = importDirective.libraryImport;
    if (importElement == null) {
      return;
    }
    var namespace = getImportNamespace(importElement);
    // prepare names of referenced elements (from this import)
    var visitor = _ReferenceFinder(namespace);
    unit.accept(visitor);
    var referencedNames = visitor.referencedNames;
    // ignore if unused
    if (referencedNames.isEmpty) {
      return;
    }
    await builder.addDartFileEdit(file, (builder) {
      var showCombinator = ' show ${referencedNames.join(', ')}';
      builder.addSimpleInsertion(importDirective.end - 1, showCombinator);
    });
  }
}

class MergeCombinators extends MultiCorrectionProducer {
  MergeCombinators({required super.context});

  @override
  Future<List<ResolvedCorrectionProducer>> get producers async {
    var node = this.node;
    if (node is! Combinator) {
      return const [];
    }

    var parent = node.parent;
    if (parent is! NamespaceDirective) {
      return const [];
    }

    ImportAddShow? importAddShow;
    if (parent is ImportDirective && parent.combinators.isEmpty) {
      importAddShow = ImportAddShow(context: context);
    }

    var combinators = parent.combinators;
    if (combinators.length < 2) {
      if (importAddShow != null) {
        return [importAddShow];
      }
      return const [];
    }

    if (combinators.whereType<ShowCombinator>().isEmpty) {
      return [
        if (importAddShow case var assist?) assist,
        _MergeCombinators(
          DartFixKind.MERGE_COMBINATORS_HIDE_HIDE,
          parent,
          mergeWithShow: false,
          context: context,
        ),
        _MergeCombinators(
          DartFixKind.MERGE_COMBINATORS_SHOW_HIDE,
          parent,
          mergeWithShow: true,
          context: context,
        ),
      ];
    }

    return [
      if (importAddShow case var assist?) assist,
      // _MergeCombinators(
      //   DartFixKind.MERGE_COMBINATORS_SHOW_SHOW,
      //   parent,
      //   mergeWithShow: true,
      //   context: context,
      // ),
      _MergeCombinators(
        DartFixKind.MERGE_COMBINATORS_HIDE_SHOW,
        parent,
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
  AssistKind? get assistKind => DartAssistKind.TMP;

  @override
  Future<void> compute(ChangeBuilder builder) async {
    LibraryElement2? element;
    LibraryImport? library;
    switch (directive) {
      case ExportDirective(:var libraryExport):
        break;
      case ImportDirective(:var libraryImport):
        library = libraryImport;
        element = libraryImport?.importedLibrary2;
    }
    if (library == null || element is! LibraryElementImpl) {
      return;
    }

    if (mergeWithShow) {
      var namespace = getImportNamespace(library);
      // prepare names of referenced elements (from this import)
      var visitor = _ReferenceFinder(namespace);
      unit.accept(visitor);
      var referencedNames = visitor.referencedNames;
      await builder.addDartFileEdit(file, (builder) {
        var showCombinator = '';
        if (referencedNames.isNotEmpty) {
          showCombinator = ' show ${referencedNames.join(', ')}';
        }
        var combinators = directive.combinators;
        builder.addSimpleReplacement(
          range.startOffsetEndOffset(combinators.offset - 1, combinators.end),
          showCombinator,
        );
      });
      return;
    }

    var originalNamespace = namespaceBuilder.createExportNamespaceForLibrary(
      element,
    );
    var hiddenNames = originalNamespace.hiddenNames(library.namespace);
    await builder.addDartFileEdit(file, (builder) {
      var showCombinator = '';
      if (hiddenNames.isNotEmpty) {
        showCombinator = ' hide ${hiddenNames.join(', ')}';
      }
      var combinators = directive.combinators;
      builder.addSimpleReplacement(
        range.startOffsetEndOffset(combinators.offset - 1, combinators.end),
        showCombinator,
      );
    });
  }
}

class _ReferenceFinder extends RecursiveAstVisitor<void> {
  final Map<String, Element2> namespace;

  Set<String> referencedNames = SplayTreeSet<String>();

  _ReferenceFinder(this.namespace);

  @override
  void visitAssignmentExpression(AssignmentExpression node) {
    _addImplicitExtensionName(node.readElement2?.enclosingElement2);
    _addImplicitExtensionName(node.writeElement2?.enclosingElement2);
    super.visitAssignmentExpression(node);
  }

  @override
  void visitBinaryExpression(BinaryExpression node) {
    _addImplicitExtensionName(node.element?.enclosingElement2);
    super.visitBinaryExpression(node);
  }

  @override
  void visitFunctionExpressionInvocation(FunctionExpressionInvocation node) {
    _addImplicitExtensionName(node.element?.enclosingElement2);
    super.visitFunctionExpressionInvocation(node);
  }

  @override
  void visitIndexExpression(IndexExpression node) {
    _addImplicitExtensionName(node.element?.enclosingElement2);
    super.visitIndexExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    _addImplicitExtensionName(node.methodName.element?.enclosingElement2);
    super.visitMethodInvocation(node);
  }

  @override
  void visitNamedType(NamedType node) {
    _addName(node.name2, node.element2);
    super.visitNamedType(node);
  }

  @override
  void visitPatternField(PatternField node) {
    _addImplicitExtensionName(node.element2?.enclosingElement2);
    super.visitPatternField(node);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    _addImplicitExtensionName(node.element?.enclosingElement2);
    super.visitPrefixedIdentifier(node);
  }

  @override
  void visitPrefixExpression(PrefixExpression node) {
    _addImplicitExtensionName(node.element?.enclosingElement2);
    super.visitPrefixExpression(node);
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    _addImplicitExtensionName(node.propertyName.element?.enclosingElement2);
    super.visitPropertyAccess(node);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    var element = node.writeOrReadElement2;
    _addName(node.token, element);
  }

  void _addImplicitExtensionName(Element2? enclosingElement) {
    if (enclosingElement is ExtensionElement2) {
      if (namespace[enclosingElement.name3] == enclosingElement) {
        referencedNames.add(enclosingElement.displayName);
      }
    }
  }

  void _addName(Token nameToken, Element2? element) {
    if (element != null) {
      var name = nameToken.lexeme;
      if (namespace[name] == element || namespace['$name='] == element) {
        referencedNames.add(element.displayName);
      }
    }
  }
}

extension on Namespace {
  Set<String> hiddenNames(Namespace current) {
    var currentEntries = current.definedNames2.keys;
    return definedNames2.entries.keys
        .whereNot(currentEntries.contains)
        .toSet();
  }
}

extension on NodeList<Combinator> {
  int get end => endToken!.end;
  int get offset => beginToken!.offset;
}
