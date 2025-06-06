// Copyright (c) 2024, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test_reflective_loader/test_reflective_loader.dart';

import '../../dart/resolution/node_text_expectations.dart';
import '../elements_base.dart';

main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(FormalParameterElementTest_keepLinking);
    defineReflectiveTests(FormalParameterElementTest_fromBytes);
    defineReflectiveTests(UpdateNodeTextExpectations);
  });
}

abstract class FormalParameterElementTest extends ElementsBaseTest {
  test_parameter() async {
    var library = await buildLibrary('void main(int p) {}');
    checkElementText(library, r'''
library
  reference: <testLibrary>
  fragments
    <testLibraryFragment>
      element: <testLibrary>
      functions
        main @5
          reference: <testLibraryFragment>::@function::main
          element: <testLibrary>::@function::main
          formalParameters
            p @14
              element: <testLibraryFragment>::@function::main::@parameter::p#element
  functions
    main
      reference: <testLibrary>::@function::main
      firstFragment: <testLibraryFragment>::@function::main
      formalParameters
        requiredPositional p
          type: int
      returnType: void
''');
  }

  test_parameter_covariant_explicit_named() async {
    var library = await buildLibrary('''
class A {
  void m({covariant A a}) {}
}
''');
    checkElementText(library, r'''
library
  reference: <testLibrary>
  fragments
    <testLibraryFragment>
      element: <testLibrary>
      classes
        class A @6
          reference: <testLibraryFragment>::@class::A
          element: <testLibrary>::@class::A
          constructors
            synthetic new
              reference: <testLibraryFragment>::@class::A::@constructor::new
              element: <testLibraryFragment>::@class::A::@constructor::new#element
              typeName: A
          methods
            m @17
              reference: <testLibraryFragment>::@class::A::@method::m
              element: <testLibraryFragment>::@class::A::@method::m#element
              formalParameters
                default a @32
                  reference: <testLibraryFragment>::@class::A::@method::m::@parameter::a
                  element: <testLibraryFragment>::@class::A::@method::m::@parameter::a#element
  classes
    class A
      reference: <testLibrary>::@class::A
      firstFragment: <testLibraryFragment>::@class::A
      constructors
        synthetic new
          firstFragment: <testLibraryFragment>::@class::A::@constructor::new
      methods
        m
          firstFragment: <testLibraryFragment>::@class::A::@method::m
          formalParameters
            optionalNamed covariant a
              firstFragment: <testLibraryFragment>::@class::A::@method::m::@parameter::a
              type: A
          returnType: void
''');
  }

  test_parameter_covariant_explicit_positional() async {
    var library = await buildLibrary('''
class A {
  void m([covariant A a]) {}
}
''');
    checkElementText(library, r'''
library
  reference: <testLibrary>
  fragments
    <testLibraryFragment>
      element: <testLibrary>
      classes
        class A @6
          reference: <testLibraryFragment>::@class::A
          element: <testLibrary>::@class::A
          constructors
            synthetic new
              reference: <testLibraryFragment>::@class::A::@constructor::new
              element: <testLibraryFragment>::@class::A::@constructor::new#element
              typeName: A
          methods
            m @17
              reference: <testLibraryFragment>::@class::A::@method::m
              element: <testLibraryFragment>::@class::A::@method::m#element
              formalParameters
                default a @32
                  element: <testLibraryFragment>::@class::A::@method::m::@parameter::a#element
  classes
    class A
      reference: <testLibrary>::@class::A
      firstFragment: <testLibraryFragment>::@class::A
      constructors
        synthetic new
          firstFragment: <testLibraryFragment>::@class::A::@constructor::new
      methods
        m
          firstFragment: <testLibraryFragment>::@class::A::@method::m
          formalParameters
            optionalPositional covariant a
              type: A
          returnType: void
''');
  }

  test_parameter_covariant_explicit_required() async {
    var library = await buildLibrary('''
class A {
  void m(covariant A a) {}
}
''');
    checkElementText(library, r'''
library
  reference: <testLibrary>
  fragments
    <testLibraryFragment>
      element: <testLibrary>
      classes
        class A @6
          reference: <testLibraryFragment>::@class::A
          element: <testLibrary>::@class::A
          constructors
            synthetic new
              reference: <testLibraryFragment>::@class::A::@constructor::new
              element: <testLibraryFragment>::@class::A::@constructor::new#element
              typeName: A
          methods
            m @17
              reference: <testLibraryFragment>::@class::A::@method::m
              element: <testLibraryFragment>::@class::A::@method::m#element
              formalParameters
                a @31
                  element: <testLibraryFragment>::@class::A::@method::m::@parameter::a#element
  classes
    class A
      reference: <testLibrary>::@class::A
      firstFragment: <testLibraryFragment>::@class::A
      constructors
        synthetic new
          firstFragment: <testLibraryFragment>::@class::A::@constructor::new
      methods
        m
          firstFragment: <testLibraryFragment>::@class::A::@method::m
          formalParameters
            requiredPositional covariant a
              type: A
          returnType: void
''');
  }

  test_parameter_covariant_inherited() async {
    var library = await buildLibrary(r'''
class A<T> {
  void f(covariant T t) {}
}
class B<T> extends A<T> {
  void f(T t) {}
}
''');
    checkElementText(library, r'''
library
  reference: <testLibrary>
  fragments
    <testLibraryFragment>
      element: <testLibrary>
      classes
        class A @6
          reference: <testLibraryFragment>::@class::A
          element: <testLibrary>::@class::A
          typeParameters
            T @8
              element: T@8
          constructors
            synthetic new
              reference: <testLibraryFragment>::@class::A::@constructor::new
              element: <testLibraryFragment>::@class::A::@constructor::new#element
              typeName: A
          methods
            f @20
              reference: <testLibraryFragment>::@class::A::@method::f
              element: <testLibraryFragment>::@class::A::@method::f#element
              formalParameters
                t @34
                  element: <testLibraryFragment>::@class::A::@method::f::@parameter::t#element
        class B @48
          reference: <testLibraryFragment>::@class::B
          element: <testLibrary>::@class::B
          typeParameters
            T @50
              element: T@50
          constructors
            synthetic new
              reference: <testLibraryFragment>::@class::B::@constructor::new
              element: <testLibraryFragment>::@class::B::@constructor::new#element
              typeName: B
          methods
            f @75
              reference: <testLibraryFragment>::@class::B::@method::f
              element: <testLibraryFragment>::@class::B::@method::f#element
              formalParameters
                t @79
                  element: <testLibraryFragment>::@class::B::@method::f::@parameter::t#element
  classes
    class A
      reference: <testLibrary>::@class::A
      firstFragment: <testLibraryFragment>::@class::A
      typeParameters
        T
      constructors
        synthetic new
          firstFragment: <testLibraryFragment>::@class::A::@constructor::new
      methods
        f
          firstFragment: <testLibraryFragment>::@class::A::@method::f
          hasEnclosingTypeParameterReference: true
          formalParameters
            requiredPositional covariant t
              type: T
          returnType: void
    class B
      reference: <testLibrary>::@class::B
      firstFragment: <testLibraryFragment>::@class::B
      typeParameters
        T
      supertype: A<T>
      constructors
        synthetic new
          firstFragment: <testLibraryFragment>::@class::B::@constructor::new
          superConstructor: <testLibraryFragment>::@class::A::@constructor::new#element
      methods
        f
          firstFragment: <testLibraryFragment>::@class::B::@method::f
          hasEnclosingTypeParameterReference: true
          formalParameters
            requiredPositional covariant t
              type: T
          returnType: void
''');
  }

  test_parameter_covariant_inherited_named() async {
    var library = await buildLibrary('''
class A {
  void m({covariant A a}) {}
}
class B extends A {
  void m({B a}) {}
}
''');
    checkElementText(library, r'''
library
  reference: <testLibrary>
  fragments
    <testLibraryFragment>
      element: <testLibrary>
      classes
        class A @6
          reference: <testLibraryFragment>::@class::A
          element: <testLibrary>::@class::A
          constructors
            synthetic new
              reference: <testLibraryFragment>::@class::A::@constructor::new
              element: <testLibraryFragment>::@class::A::@constructor::new#element
              typeName: A
          methods
            m @17
              reference: <testLibraryFragment>::@class::A::@method::m
              element: <testLibraryFragment>::@class::A::@method::m#element
              formalParameters
                default a @32
                  reference: <testLibraryFragment>::@class::A::@method::m::@parameter::a
                  element: <testLibraryFragment>::@class::A::@method::m::@parameter::a#element
        class B @47
          reference: <testLibraryFragment>::@class::B
          element: <testLibrary>::@class::B
          constructors
            synthetic new
              reference: <testLibraryFragment>::@class::B::@constructor::new
              element: <testLibraryFragment>::@class::B::@constructor::new#element
              typeName: B
          methods
            m @68
              reference: <testLibraryFragment>::@class::B::@method::m
              element: <testLibraryFragment>::@class::B::@method::m#element
              formalParameters
                default a @73
                  reference: <testLibraryFragment>::@class::B::@method::m::@parameter::a
                  element: <testLibraryFragment>::@class::B::@method::m::@parameter::a#element
  classes
    class A
      reference: <testLibrary>::@class::A
      firstFragment: <testLibraryFragment>::@class::A
      constructors
        synthetic new
          firstFragment: <testLibraryFragment>::@class::A::@constructor::new
      methods
        m
          firstFragment: <testLibraryFragment>::@class::A::@method::m
          formalParameters
            optionalNamed covariant a
              firstFragment: <testLibraryFragment>::@class::A::@method::m::@parameter::a
              type: A
          returnType: void
    class B
      reference: <testLibrary>::@class::B
      firstFragment: <testLibraryFragment>::@class::B
      supertype: A
      constructors
        synthetic new
          firstFragment: <testLibraryFragment>::@class::B::@constructor::new
          superConstructor: <testLibraryFragment>::@class::A::@constructor::new#element
      methods
        m
          firstFragment: <testLibraryFragment>::@class::B::@method::m
          formalParameters
            optionalNamed covariant a
              firstFragment: <testLibraryFragment>::@class::B::@method::m::@parameter::a
              type: B
          returnType: void
''');
  }

  test_parameter_parameters() async {
    var library = await buildLibrary('class C { f(g(x, y)) {} }');
    checkElementText(library, r'''
library
  reference: <testLibrary>
  fragments
    <testLibraryFragment>
      element: <testLibrary>
      classes
        class C @6
          reference: <testLibraryFragment>::@class::C
          element: <testLibrary>::@class::C
          constructors
            synthetic new
              reference: <testLibraryFragment>::@class::C::@constructor::new
              element: <testLibraryFragment>::@class::C::@constructor::new#element
              typeName: C
          methods
            f @10
              reference: <testLibraryFragment>::@class::C::@method::f
              element: <testLibraryFragment>::@class::C::@method::f#element
              formalParameters
                g @12
                  element: <testLibraryFragment>::@class::C::@method::f::@parameter::g#element
  classes
    class C
      reference: <testLibrary>::@class::C
      firstFragment: <testLibraryFragment>::@class::C
      constructors
        synthetic new
          firstFragment: <testLibraryFragment>::@class::C::@constructor::new
      methods
        f
          firstFragment: <testLibraryFragment>::@class::C::@method::f
          formalParameters
            requiredPositional g
              type: dynamic Function(dynamic, dynamic)
              formalParameters
                requiredPositional hasImplicitType x
                  type: dynamic
                requiredPositional hasImplicitType y
                  type: dynamic
          returnType: dynamic
''');
  }

  test_parameter_parameters_in_generic_class() async {
    var library = await buildLibrary('class C<A, B> { f(A g(B x)) {} }');
    checkElementText(library, r'''
library
  reference: <testLibrary>
  fragments
    <testLibraryFragment>
      element: <testLibrary>
      classes
        class C @6
          reference: <testLibraryFragment>::@class::C
          element: <testLibrary>::@class::C
          typeParameters
            A @8
              element: A@8
            B @11
              element: B@11
          constructors
            synthetic new
              reference: <testLibraryFragment>::@class::C::@constructor::new
              element: <testLibraryFragment>::@class::C::@constructor::new#element
              typeName: C
          methods
            f @16
              reference: <testLibraryFragment>::@class::C::@method::f
              element: <testLibraryFragment>::@class::C::@method::f#element
              formalParameters
                g @20
                  element: <testLibraryFragment>::@class::C::@method::f::@parameter::g#element
  classes
    class C
      reference: <testLibrary>::@class::C
      firstFragment: <testLibraryFragment>::@class::C
      typeParameters
        A
        B
      constructors
        synthetic new
          firstFragment: <testLibraryFragment>::@class::C::@constructor::new
      methods
        f
          firstFragment: <testLibraryFragment>::@class::C::@method::f
          hasEnclosingTypeParameterReference: true
          formalParameters
            requiredPositional g
              type: A Function(B)
              formalParameters
                requiredPositional x
                  type: B
          returnType: dynamic
''');
  }

  test_parameter_return_type() async {
    var library = await buildLibrary('class C { f(int g()) {} }');
    checkElementText(library, r'''
library
  reference: <testLibrary>
  fragments
    <testLibraryFragment>
      element: <testLibrary>
      classes
        class C @6
          reference: <testLibraryFragment>::@class::C
          element: <testLibrary>::@class::C
          constructors
            synthetic new
              reference: <testLibraryFragment>::@class::C::@constructor::new
              element: <testLibraryFragment>::@class::C::@constructor::new#element
              typeName: C
          methods
            f @10
              reference: <testLibraryFragment>::@class::C::@method::f
              element: <testLibraryFragment>::@class::C::@method::f#element
              formalParameters
                g @16
                  element: <testLibraryFragment>::@class::C::@method::f::@parameter::g#element
  classes
    class C
      reference: <testLibrary>::@class::C
      firstFragment: <testLibraryFragment>::@class::C
      constructors
        synthetic new
          firstFragment: <testLibraryFragment>::@class::C::@constructor::new
      methods
        f
          firstFragment: <testLibraryFragment>::@class::C::@method::f
          formalParameters
            requiredPositional g
              type: int Function()
          returnType: dynamic
''');
  }

  test_parameter_return_type_void() async {
    var library = await buildLibrary('class C { f(void g()) {} }');
    checkElementText(library, r'''
library
  reference: <testLibrary>
  fragments
    <testLibraryFragment>
      element: <testLibrary>
      classes
        class C @6
          reference: <testLibraryFragment>::@class::C
          element: <testLibrary>::@class::C
          constructors
            synthetic new
              reference: <testLibraryFragment>::@class::C::@constructor::new
              element: <testLibraryFragment>::@class::C::@constructor::new#element
              typeName: C
          methods
            f @10
              reference: <testLibraryFragment>::@class::C::@method::f
              element: <testLibraryFragment>::@class::C::@method::f#element
              formalParameters
                g @17
                  element: <testLibraryFragment>::@class::C::@method::f::@parameter::g#element
  classes
    class C
      reference: <testLibrary>::@class::C
      firstFragment: <testLibraryFragment>::@class::C
      constructors
        synthetic new
          firstFragment: <testLibraryFragment>::@class::C::@constructor::new
      methods
        f
          firstFragment: <testLibraryFragment>::@class::C::@method::f
          formalParameters
            requiredPositional g
              type: void Function()
          returnType: dynamic
''');
  }

  test_parameter_typeParameters() async {
    var library = await buildLibrary(r'''
void f(T a<T, U>(U u)) {}
''');
    checkElementText(library, r'''
library
  reference: <testLibrary>
  fragments
    <testLibraryFragment>
      element: <testLibrary>
      functions
        f @5
          reference: <testLibraryFragment>::@function::f
          element: <testLibrary>::@function::f
          formalParameters
            a @9
              element: <testLibraryFragment>::@function::f::@parameter::a#element
  functions
    f
      reference: <testLibrary>::@function::f
      firstFragment: <testLibraryFragment>::@function::f
      formalParameters
        requiredPositional a
          type: T Function<T, U>(U)
          formalParameters
            requiredPositional u
              type: U
      returnType: void
''');
  }

  test_parameterTypeNotInferred_constructor() async {
    // Strong mode doesn't do type inference on constructor parameters, so it's
    // ok that we don't store inferred type info for them in summaries.
    var library = await buildLibrary('''
class C {
  C.positional([x = 1]);
  C.named({x: 1});
}
''');
    checkElementText(library, r'''
library
  reference: <testLibrary>
  fragments
    <testLibraryFragment>
      element: <testLibrary>
      classes
        class C @6
          reference: <testLibraryFragment>::@class::C
          element: <testLibrary>::@class::C
          constructors
            positional @14
              reference: <testLibraryFragment>::@class::C::@constructor::positional
              element: <testLibraryFragment>::@class::C::@constructor::positional#element
              typeName: C
              typeNameOffset: 12
              periodOffset: 13
              formalParameters
                default x @26
                  element: <testLibraryFragment>::@class::C::@constructor::positional::@parameter::x#element
                  initializer: expression_0
                    IntegerLiteral
                      literal: 1 @30
                      staticType: int
            named @39
              reference: <testLibraryFragment>::@class::C::@constructor::named
              element: <testLibraryFragment>::@class::C::@constructor::named#element
              typeName: C
              typeNameOffset: 37
              periodOffset: 38
              formalParameters
                default x @46
                  reference: <testLibraryFragment>::@class::C::@constructor::named::@parameter::x
                  element: <testLibraryFragment>::@class::C::@constructor::named::@parameter::x#element
                  initializer: expression_1
                    IntegerLiteral
                      literal: 1 @49
                      staticType: int
  classes
    class C
      reference: <testLibrary>::@class::C
      firstFragment: <testLibraryFragment>::@class::C
      constructors
        positional
          firstFragment: <testLibraryFragment>::@class::C::@constructor::positional
          formalParameters
            optionalPositional hasImplicitType x
              type: dynamic
              constantInitializer
                expression: expression_0
        named
          firstFragment: <testLibraryFragment>::@class::C::@constructor::named
          formalParameters
            optionalNamed hasImplicitType x
              firstFragment: <testLibraryFragment>::@class::C::@constructor::named::@parameter::x
              type: dynamic
              constantInitializer
                fragment: <testLibraryFragment>::@class::C::@constructor::named::@parameter::x
                expression: expression_1
''');
  }

  test_parameterTypeNotInferred_initializingFormal() async {
    // Strong mode doesn't do type inference on initializing formals, so it's
    // ok that we don't store inferred type info for them in summaries.
    var library = await buildLibrary('''
class C {
  var x;
  C.positional([this.x = 1]);
  C.named({this.x: 1});
}
''');
    checkElementText(library, r'''
library
  reference: <testLibrary>
  fragments
    <testLibraryFragment>
      element: <testLibrary>
      classes
        class C @6
          reference: <testLibraryFragment>::@class::C
          element: <testLibrary>::@class::C
          fields
            x @16
              reference: <testLibraryFragment>::@class::C::@field::x
              element: <testLibraryFragment>::@class::C::@field::x#element
              getter2: <testLibraryFragment>::@class::C::@getter::x
              setter2: <testLibraryFragment>::@class::C::@setter::x
          constructors
            positional @23
              reference: <testLibraryFragment>::@class::C::@constructor::positional
              element: <testLibraryFragment>::@class::C::@constructor::positional#element
              typeName: C
              typeNameOffset: 21
              periodOffset: 22
              formalParameters
                default this.x @40
                  element: <testLibraryFragment>::@class::C::@constructor::positional::@parameter::x#element
                  initializer: expression_0
                    IntegerLiteral
                      literal: 1 @44
                      staticType: int
            named @53
              reference: <testLibraryFragment>::@class::C::@constructor::named
              element: <testLibraryFragment>::@class::C::@constructor::named#element
              typeName: C
              typeNameOffset: 51
              periodOffset: 52
              formalParameters
                default this.x @65
                  reference: <testLibraryFragment>::@class::C::@constructor::named::@parameter::x
                  element: <testLibraryFragment>::@class::C::@constructor::named::@parameter::x#element
                  initializer: expression_1
                    IntegerLiteral
                      literal: 1 @68
                      staticType: int
          getters
            synthetic get x
              reference: <testLibraryFragment>::@class::C::@getter::x
              element: <testLibraryFragment>::@class::C::@getter::x#element
          setters
            synthetic set x
              reference: <testLibraryFragment>::@class::C::@setter::x
              element: <testLibraryFragment>::@class::C::@setter::x#element
              formalParameters
                _x
                  element: <testLibraryFragment>::@class::C::@setter::x::@parameter::_x#element
  classes
    class C
      reference: <testLibrary>::@class::C
      firstFragment: <testLibraryFragment>::@class::C
      fields
        x
          firstFragment: <testLibraryFragment>::@class::C::@field::x
          type: dynamic
          getter: <testLibraryFragment>::@class::C::@getter::x#element
          setter: <testLibraryFragment>::@class::C::@setter::x#element
      constructors
        positional
          firstFragment: <testLibraryFragment>::@class::C::@constructor::positional
          formalParameters
            optionalPositional final hasImplicitType x
              type: dynamic
              constantInitializer
                expression: expression_0
        named
          firstFragment: <testLibraryFragment>::@class::C::@constructor::named
          formalParameters
            optionalNamed final hasImplicitType x
              firstFragment: <testLibraryFragment>::@class::C::@constructor::named::@parameter::x
              type: dynamic
              constantInitializer
                fragment: <testLibraryFragment>::@class::C::@constructor::named::@parameter::x
                expression: expression_1
      getters
        synthetic get x
          firstFragment: <testLibraryFragment>::@class::C::@getter::x
          returnType: dynamic
      setters
        synthetic set x
          firstFragment: <testLibraryFragment>::@class::C::@setter::x
          formalParameters
            requiredPositional _x
              type: dynamic
          returnType: void
''');
  }

  test_parameterTypeNotInferred_staticMethod() async {
    // Strong mode doesn't do type inference on parameters of static methods,
    // so it's ok that we don't store inferred type info for them in summaries.
    var library = await buildLibrary('''
class C {
  static void positional([x = 1]) {}
  static void named({x: 1}) {}
}
''');
    checkElementText(library, r'''
library
  reference: <testLibrary>
  fragments
    <testLibraryFragment>
      element: <testLibrary>
      classes
        class C @6
          reference: <testLibraryFragment>::@class::C
          element: <testLibrary>::@class::C
          constructors
            synthetic new
              reference: <testLibraryFragment>::@class::C::@constructor::new
              element: <testLibraryFragment>::@class::C::@constructor::new#element
              typeName: C
          methods
            positional @24
              reference: <testLibraryFragment>::@class::C::@method::positional
              element: <testLibraryFragment>::@class::C::@method::positional#element
              formalParameters
                default x @36
                  element: <testLibraryFragment>::@class::C::@method::positional::@parameter::x#element
                  initializer: expression_0
                    IntegerLiteral
                      literal: 1 @40
                      staticType: int
            named @61
              reference: <testLibraryFragment>::@class::C::@method::named
              element: <testLibraryFragment>::@class::C::@method::named#element
              formalParameters
                default x @68
                  reference: <testLibraryFragment>::@class::C::@method::named::@parameter::x
                  element: <testLibraryFragment>::@class::C::@method::named::@parameter::x#element
                  initializer: expression_1
                    IntegerLiteral
                      literal: 1 @71
                      staticType: int
  classes
    class C
      reference: <testLibrary>::@class::C
      firstFragment: <testLibraryFragment>::@class::C
      constructors
        synthetic new
          firstFragment: <testLibraryFragment>::@class::C::@constructor::new
      methods
        static positional
          firstFragment: <testLibraryFragment>::@class::C::@method::positional
          formalParameters
            optionalPositional hasImplicitType x
              type: dynamic
              constantInitializer
                expression: expression_0
          returnType: void
        static named
          firstFragment: <testLibraryFragment>::@class::C::@method::named
          formalParameters
            optionalNamed hasImplicitType x
              firstFragment: <testLibraryFragment>::@class::C::@method::named::@parameter::x
              type: dynamic
              constantInitializer
                fragment: <testLibraryFragment>::@class::C::@method::named::@parameter::x
                expression: expression_1
          returnType: void
''');
  }

  test_parameterTypeNotInferred_topLevelFunction() async {
    // Strong mode doesn't do type inference on parameters of top level
    // functions, so it's ok that we don't store inferred type info for them in
    // summaries.
    var library = await buildLibrary('''
void positional([x = 1]) {}
void named({x: 1}) {}
''');
    checkElementText(library, r'''
library
  reference: <testLibrary>
  fragments
    <testLibraryFragment>
      element: <testLibrary>
      functions
        positional @5
          reference: <testLibraryFragment>::@function::positional
          element: <testLibrary>::@function::positional
          formalParameters
            default x @17
              element: <testLibraryFragment>::@function::positional::@parameter::x#element
              initializer: expression_0
                IntegerLiteral
                  literal: 1 @21
                  staticType: int
        named @33
          reference: <testLibraryFragment>::@function::named
          element: <testLibrary>::@function::named
          formalParameters
            default x @40
              reference: <testLibraryFragment>::@function::named::@parameter::x
              element: <testLibraryFragment>::@function::named::@parameter::x#element
              initializer: expression_1
                IntegerLiteral
                  literal: 1 @43
                  staticType: int
  functions
    positional
      reference: <testLibrary>::@function::positional
      firstFragment: <testLibraryFragment>::@function::positional
      formalParameters
        optionalPositional hasImplicitType x
          type: dynamic
          constantInitializer
            expression: expression_0
      returnType: void
    named
      reference: <testLibrary>::@function::named
      firstFragment: <testLibraryFragment>::@function::named
      formalParameters
        optionalNamed hasImplicitType x
          firstFragment: <testLibraryFragment>::@function::named::@parameter::x
          type: dynamic
          constantInitializer
            fragment: <testLibraryFragment>::@function::named::@parameter::x
            expression: expression_1
      returnType: void
''');
  }
}

@reflectiveTest
class FormalParameterElementTest_fromBytes extends FormalParameterElementTest {
  @override
  bool get keepLinkingLibraries => false;
}

@reflectiveTest
class FormalParameterElementTest_keepLinking
    extends FormalParameterElementTest {
  @override
  bool get keepLinkingLibraries => true;
}
