// Copyright (c) 2017, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../analyzer.dart';

const _desc = r'Use a function declaration to bind a function to a name.';

class PreferFunctionDeclarationsOverVariables extends LintRule {
  PreferFunctionDeclarationsOverVariables()
    : super(
        name: LintNames.prefer_function_declarations_over_variables,
        description: _desc,
      );

  @override
  LintCode get lintCode =>
      LinterLintCode.prefer_function_declarations_over_variables;

  @override
  void registerNodeProcessors(
    NodeLintRegistry registry,
    LinterContext context,
  ) {
    var visitor = _Visitor(this);
    registry.addVariableDeclaration(this, visitor);
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  final LintRule rule;

  _Visitor(this.rule);

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    if (node.initializer is FunctionExpression) {
      var function = node.thisOrAncestorOfType<FunctionBody>();
      if (function == null) {
        // When there is no enclosing function body, this is a variable
        // definition for a field or a top-level variable, which should only
        // be reported if final.
        if (node.isFinal) {
          rule.reportAtNode(node);
        }
      } else {
        var declaredElement = node.declaredElement2;
        if (declaredElement != null &&
            !function.isPotentiallyMutatedInScope2(declaredElement)) {
          rule.reportAtNode(node);
        }
      }
    }
  }
}
