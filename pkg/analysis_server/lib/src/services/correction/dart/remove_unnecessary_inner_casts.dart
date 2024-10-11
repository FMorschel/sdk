// Copyright (c) 2020, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analysis_server/src/services/correction/fix.dart';
import 'package:analysis_server/src/services/correction/util.dart';
import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_dart.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';
import 'package:analyzer_plugin/utilities/range_factory.dart';

class RemoveUnnecessaryInnerCasts extends ResolvedCorrectionProducer {
  RemoveUnnecessaryInnerCasts({required super.context});

  @override
  CorrectionApplicability get applicability =>
      CorrectionApplicability.automatically;

  @override
  FixKind get fixKind => DartFixKind.REMOVE_UNNECESSARY_INNER_CASTS;

  @override
  FixKind get multiFixKind => DartFixKind.REMOVE_UNNECESSARY_INNER_CASTS_MULTI;

  @override
  Future<void> compute(ChangeBuilder builder) async {
    var asExpression = coveringNode;
    if (asExpression is! AsExpression) {
      return;
    }

    var asExpressions = <AsExpression>[];

    DartType? type = asExpression.type.type;
    if (type == null) {
      return;
    }

    Expression? expression = asExpression.expression;
    if (asExpression.expression
        case ParenthesizedExpression(expression: var inner)) {
      // Look inside if there are other casts to the same type.
      expression = inner;
      if (inner case AsExpression inner when asExpression.type == inner.type) {
        if (inner.expression.staticType case var staticType?
            when !typeSystem.isSubtypeOf(staticType, type)) {
          asExpressions.add(inner);
        }
      }
    }

    if (expression
        case ConditionalExpression(
          thenExpression: var then,
          elseExpression: var elseExp
        )) {
      // Look inside if there are other casts to the same type.
      if (then case AsExpression inner when asExpression.type == inner.type) {
        if (inner.expression.staticType case var staticType?
            when !typeSystem.isSubtypeOf(staticType, type)) {
          asExpressions.add(inner);
        }
      }
      if (elseExp case AsExpression inner
          when asExpression.type == inner.type) {
        if (inner.expression.staticType case var staticType?
            when !typeSystem.isSubtypeOf(staticType, type)) {
          asExpressions.add(inner);
        }
      }
    }

    if (expression case SwitchExpression(cases: var cases)) {
      // Look inside if there are other casts to the same type.
      for (var switchCase in cases) {
        if (switchCase.expression case AsExpression inner
            when asExpression.type == inner.type) {
          if (inner.expression.staticType case var staticType?
              when !typeSystem.isSubtypeOf(staticType, type)) {
            asExpressions.add(inner);
          }
        }
      }
    }

    if (asExpressions.isEmpty) {
      return;
    }

    // remove 'as T' from 'e as T'
    for (var inner in asExpressions) {
      await builder.addDartFileEdit(file, (builder) {
        var expression = inner;
        builder.addDeletion(range.endEnd(expression, asExpression));
        builder.removeEnclosingParentheses(asExpression);
      });
    }
  }
}

extension on DartFileEditBuilder {
  /// Adds edits to this [DartFileEditBuilder] to remove any parentheses
  /// enclosing the [expression].
  void removeEnclosingParentheses(Expression expression) {
    var precedence = getExpressionPrecedence(expression);
    while (expression.parent is ParenthesizedExpression) {
      var parenthesized = expression.parent as ParenthesizedExpression;
      if (getExpressionParentPrecedence(parenthesized) > precedence) {
        break;
      }
      addDeletion(range.token(parenthesized.leftParenthesis));
      addDeletion(range.token(parenthesized.rightParenthesis));
      expression = parenthesized;
    }
  }
}
