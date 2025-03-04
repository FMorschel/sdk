// Copyright (c) 2025, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element2.dart';

import '../analyzer.dart';

const _desc = "Avoid switch on 'runtimeType'";

const _objectName = 'Object';
const _objectRuntimeTypeName = 'runtimeType';
final _objectUri = Uri.parse('dart:core');

class AvoidSwitchOnRuntimeType extends LintRule {
  AvoidSwitchOnRuntimeType()
    : super(name: LintNames.avoid_switch_on_runtimetype, description: _desc);

  @override
  LintCode get lintCode => LinterLintCode.avoid_switch_on_runtimetype;

  @override
  void registerNodeProcessors(
    NodeLintRegistry registry,
    LinterContext context,
  ) {
    registry.addSwitchExpression(this, _Visitor(this, context));
    registry.addSwitchStatement(this, _Visitor(this, context));
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  final LintRule rule;

  final LinterContext context;

  late AstNode node;

  _Visitor(this.rule, this.context);

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    if (node.identifier.element.isExactDartObjectRuntimeType) {
      rule.reportLint(this.node);
    }
  }

  @override
  void visitSwitchExpression(SwitchExpression node) {
    this.node = node;
    if (node.expression case PrefixedIdentifier exp) {
      visitPrefixedIdentifier(exp);
    }
  }

  @override
  void visitSwitchStatement(SwitchStatement node) {
    this.node = node;
    if (node.expression case PrefixedIdentifier exp) {
      visitPrefixedIdentifier(exp);
    }
  }
}

extension on Element2? {
  bool get isExactDartObjectRuntimeType {
    var self = this;
    if (self == null) {
      return false;
    }
    var element = self.baseElement;
    // TODO(FMorschel): Consider overrides.
    var enclosingElement = element.enclosingElement2;
    if (enclosingElement is! ClassElement2) {
      return false;
    }
    if (element.firstFragment.libraryFragment?.source.uri != _objectUri) {
      return false;
    }
    if (enclosingElement.name3 != _objectName) {
      return false;
    }
    return element.name3 == _objectRuntimeTypeName;
  }
}
