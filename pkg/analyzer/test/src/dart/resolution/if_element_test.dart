// Copyright (c) 2018, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analyzer/src/dart/error/syntactic_errors.dart';
import 'package:analyzer/src/error/codes.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'context_collection_resolution.dart';

main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(IfElementResolutionTest);
  });
}

@reflectiveTest
class IfElementResolutionTest extends PubPackageResolutionTest {
  test_caseClause() async {
    await assertNoErrorsInCode(r'''
void f(Object x) {
  [if (x case 0) 1 else 2];
}
''');

    var node = findNode.ifElement('if');
    assertResolvedNodeText(node, r'''
IfElement
  ifKeyword: if
  leftParenthesis: (
  expression: SimpleIdentifier
    token: x
    element: <testLibraryFragment>::@function::f::@parameter::x#element
    staticType: Object
  caseClause: CaseClause
    caseKeyword: case
    guardedPattern: GuardedPattern
      pattern: ConstantPattern
        expression: IntegerLiteral
          literal: 0
          staticType: int
        matchedValueType: Object
  rightParenthesis: )
  thenElement: IntegerLiteral
    literal: 1
    staticType: int
  elseKeyword: else
  elseElement: IntegerLiteral
    literal: 2
    staticType: int
''');
  }

  test_caseClause_topLevelVariableInitializer() async {
    await assertNoErrorsInCode(r'''
final x = 0;
final y = [ if (x case var a) a ];
''');

    var node = findNode.singleIfElement;
    assertResolvedNodeText(node, r'''
IfElement
  ifKeyword: if
  leftParenthesis: (
  expression: SimpleIdentifier
    token: x
    element: <testLibraryFragment>::@getter::x#element
    staticType: int
  caseClause: CaseClause
    caseKeyword: case
    guardedPattern: GuardedPattern
      pattern: DeclaredVariablePattern
        keyword: var
        name: a
        declaredElement: hasImplicitType a@40
          type: int
        matchedValueType: int
  rightParenthesis: )
  thenElement: SimpleIdentifier
    token: a
    element: a@40
    staticType: int
''');
  }

  test_caseClause_variables_scope() async {
    // Each `guardedPattern` introduces a new case scope which is where the
    // variables defined by that case's pattern are bound.
    // There is no initializing expression for the variables in a case pattern,
    // but they are considered initialized after the entire case pattern,
    // before the guard expression if there is one. However, all pattern
    // variables are in scope in the entire pattern.
    await assertErrorsInCode(
      r'''
const a = 0;
void f(Object x) {
  [
    if (x case [int a, == a] when a > 0)
      a
    else
      a
  ];
}
''',
      [
        error(
          CompileTimeErrorCode.NON_CONSTANT_RELATIONAL_PATTERN_EXPRESSION,
          62,
          1,
        ),
        error(
          CompileTimeErrorCode.REFERENCED_BEFORE_DECLARATION,
          62,
          1,
          contextMessages: [message(testFile, 56, 1)],
        ),
      ],
    );

    var node = findNode.ifElement('if');
    assertResolvedNodeText(node, r'''
IfElement
  ifKeyword: if
  leftParenthesis: (
  expression: SimpleIdentifier
    token: x
    element: <testLibraryFragment>::@function::f::@parameter::x#element
    staticType: Object
  caseClause: CaseClause
    caseKeyword: case
    guardedPattern: GuardedPattern
      pattern: ListPattern
        leftBracket: [
        elements
          DeclaredVariablePattern
            type: NamedType
              name: int
              element2: dart:core::@class::int
              type: int
            name: a
            declaredElement: a@56
              type: int
            matchedValueType: Object?
          RelationalPattern
            operator: ==
            operand: SimpleIdentifier
              token: a
              element: a@56
              staticType: int
            element2: dart:core::<fragment>::@class::Object::@method::==#element
            matchedValueType: Object?
        rightBracket: ]
        matchedValueType: Object
        requiredType: List<Object?>
      whenClause: WhenClause
        whenKeyword: when
        expression: BinaryExpression
          leftOperand: SimpleIdentifier
            token: a
            element: a@56
            staticType: int
          operator: >
          rightOperand: IntegerLiteral
            literal: 0
            correspondingParameter: dart:core::<fragment>::@class::num::@method::>::@parameter::other#element
            staticType: int
          element: dart:core::<fragment>::@class::num::@method::>#element
          staticInvokeType: bool Function(num)
          staticType: bool
  rightParenthesis: )
  thenElement: SimpleIdentifier
    token: a
    element: a@56
    staticType: int
  elseKeyword: else
  elseElement: SimpleIdentifier
    token: a
    element: <testLibraryFragment>::@getter::a#element
    staticType: int
''');
  }

  test_caseClause_variables_single() async {
    await assertErrorsInCode(
      r'''
void f(Object x) {
  [
    if (x case int a when a > 0)
      a
    else
      a // error
  ];
}
''',
      [error(CompileTimeErrorCode.UNDEFINED_IDENTIFIER, 79, 1)],
    );

    var node = findNode.ifElement('if');
    assertResolvedNodeText(node, r'''
IfElement
  ifKeyword: if
  leftParenthesis: (
  expression: SimpleIdentifier
    token: x
    element: <testLibraryFragment>::@function::f::@parameter::x#element
    staticType: Object
  caseClause: CaseClause
    caseKeyword: case
    guardedPattern: GuardedPattern
      pattern: DeclaredVariablePattern
        type: NamedType
          name: int
          element2: dart:core::@class::int
          type: int
        name: a
        declaredElement: a@42
          type: int
        matchedValueType: Object
      whenClause: WhenClause
        whenKeyword: when
        expression: BinaryExpression
          leftOperand: SimpleIdentifier
            token: a
            element: a@42
            staticType: int
          operator: >
          rightOperand: IntegerLiteral
            literal: 0
            correspondingParameter: dart:core::<fragment>::@class::num::@method::>::@parameter::other#element
            staticType: int
          element: dart:core::<fragment>::@class::num::@method::>#element
          staticInvokeType: bool Function(num)
          staticType: bool
  rightParenthesis: )
  thenElement: SimpleIdentifier
    token: a
    element: a@42
    staticType: int
  elseKeyword: else
  elseElement: SimpleIdentifier
    token: a
    element: <null>
    staticType: InvalidType
''');
  }

  test_expression_super() async {
    await assertErrorsInCode(
      r'''
class A {
  void f() {
    [if (super) 0 else 1];
  }
}
''',
      [
        error(ParserErrorCode.MISSING_ASSIGNABLE_SELECTOR, 32, 5),
        error(CompileTimeErrorCode.NON_BOOL_CONDITION, 32, 5),
      ],
    );

    var node = findNode.singleIfElement;
    assertResolvedNodeText(node, r'''
IfElement
  ifKeyword: if
  leftParenthesis: (
  expression: SuperExpression
    superKeyword: super
    staticType: A
  rightParenthesis: )
  thenElement: IntegerLiteral
    literal: 0
    staticType: int
  elseKeyword: else
  elseElement: IntegerLiteral
    literal: 1
    staticType: int
''');
  }

  test_rewrite_caseClause_pattern() async {
    await assertNoErrorsInCode(r'''
void f(Object x) {
  [if (x case const A()) 0];
}

class A {
  const A();
}
''');

    var node = findNode.ifElement('if');
    assertResolvedNodeText(node, r'''
IfElement
  ifKeyword: if
  leftParenthesis: (
  expression: SimpleIdentifier
    token: x
    element: <testLibraryFragment>::@function::f::@parameter::x#element
    staticType: Object
  caseClause: CaseClause
    caseKeyword: case
    guardedPattern: GuardedPattern
      pattern: ConstantPattern
        const: const
        expression: InstanceCreationExpression
          constructorName: ConstructorName
            type: NamedType
              name: A
              element2: <testLibrary>::@class::A
              type: A
            element: <testLibraryFragment>::@class::A::@constructor::new#element
          argumentList: ArgumentList
            leftParenthesis: (
            rightParenthesis: )
          staticType: A
        matchedValueType: Object
  rightParenthesis: )
  thenElement: IntegerLiteral
    literal: 0
    staticType: int
''');
  }

  test_rewrite_expression() async {
    await assertNoErrorsInCode(r'''
void f(bool Function() a) {
  [if (a()) 0];
}
''');

    var node = findNode.ifElement('if');
    assertResolvedNodeText(node, r'''
IfElement
  ifKeyword: if
  leftParenthesis: (
  expression: FunctionExpressionInvocation
    function: SimpleIdentifier
      token: a
      element: <testLibraryFragment>::@function::f::@parameter::a#element
      staticType: bool Function()
    argumentList: ArgumentList
      leftParenthesis: (
      rightParenthesis: )
    element: <null>
    staticInvokeType: bool Function()
    staticType: bool
  rightParenthesis: )
  thenElement: IntegerLiteral
    literal: 0
    staticType: int
''');
  }

  test_rewrite_expression_caseClause() async {
    await assertNoErrorsInCode(r'''
void f(int Function() a) {
  [if (a() case 0) 1];
}
''');

    var node = findNode.ifElement('if');
    assertResolvedNodeText(node, r'''
IfElement
  ifKeyword: if
  leftParenthesis: (
  expression: FunctionExpressionInvocation
    function: SimpleIdentifier
      token: a
      element: <testLibraryFragment>::@function::f::@parameter::a#element
      staticType: int Function()
    argumentList: ArgumentList
      leftParenthesis: (
      rightParenthesis: )
    element: <null>
    staticInvokeType: int Function()
    staticType: int
  caseClause: CaseClause
    caseKeyword: case
    guardedPattern: GuardedPattern
      pattern: ConstantPattern
        expression: IntegerLiteral
          literal: 0
          staticType: int
        matchedValueType: int
  rightParenthesis: )
  thenElement: IntegerLiteral
    literal: 1
    staticType: int
''');
  }

  test_rewrite_whenClause() async {
    await assertNoErrorsInCode(r'''
void f(Object x, bool Function() a) {
  [if (x case 0 when a()) 1];
}
''');

    var node = findNode.ifElement('if');
    assertResolvedNodeText(node, r'''
IfElement
  ifKeyword: if
  leftParenthesis: (
  expression: SimpleIdentifier
    token: x
    element: <testLibraryFragment>::@function::f::@parameter::x#element
    staticType: Object
  caseClause: CaseClause
    caseKeyword: case
    guardedPattern: GuardedPattern
      pattern: ConstantPattern
        expression: IntegerLiteral
          literal: 0
          staticType: int
        matchedValueType: Object
      whenClause: WhenClause
        whenKeyword: when
        expression: FunctionExpressionInvocation
          function: SimpleIdentifier
            token: a
            element: <testLibraryFragment>::@function::f::@parameter::a#element
            staticType: bool Function()
          argumentList: ArgumentList
            leftParenthesis: (
            rightParenthesis: )
          element: <null>
          staticInvokeType: bool Function()
          staticType: bool
  rightParenthesis: )
  thenElement: IntegerLiteral
    literal: 1
    staticType: int
''');
  }

  test_whenClause() async {
    await assertNoErrorsInCode(r'''
void f(Object x) {
  [if (x case 0 when true) 1 else 2];
}
''');

    var node = findNode.ifElement('if');
    assertResolvedNodeText(node, r'''
IfElement
  ifKeyword: if
  leftParenthesis: (
  expression: SimpleIdentifier
    token: x
    element: <testLibraryFragment>::@function::f::@parameter::x#element
    staticType: Object
  caseClause: CaseClause
    caseKeyword: case
    guardedPattern: GuardedPattern
      pattern: ConstantPattern
        expression: IntegerLiteral
          literal: 0
          staticType: int
        matchedValueType: Object
      whenClause: WhenClause
        whenKeyword: when
        expression: BooleanLiteral
          literal: true
          staticType: bool
  rightParenthesis: )
  thenElement: IntegerLiteral
    literal: 1
    staticType: int
  elseKeyword: else
  elseElement: IntegerLiteral
    literal: 2
    staticType: int
''');
  }
}
