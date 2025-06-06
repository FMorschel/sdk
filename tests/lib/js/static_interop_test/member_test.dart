// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Test that instance members are disallowed from static interop classes.

import 'package:js/js.dart';

@JS()
@staticInterop
class StaticJSClass {
  external factory StaticJSClass();
  external factory StaticJSClass.externalFactory();
  factory StaticJSClass.redirectingFactory() = StaticJSClass;
  factory StaticJSClass.factory() => StaticJSClass();

  static String staticField = 'staticField';
  static String get staticGetSet => staticField;
  static set staticGetSet(String val) => staticField = val;
  static String staticMethod() => 'staticMethod';

  external static String externalStaticField;
  external static String get externalStaticGetSet;
  external static set externalStaticGetSet(String val);
  external static String externalStaticMethod();

  external int get getter;
  //               ^
  // [web] JS interop class 'StaticJSClass' with `@staticInterop` annotation cannot declare instance members.
  external set setter(_);
  //           ^
  // [web] JS interop class 'StaticJSClass' with `@staticInterop` annotation cannot declare instance members.
  external int method();
  //           ^
  // [web] JS interop class 'StaticJSClass' with `@staticInterop` annotation cannot declare instance members.
  external int field;
  //           ^
  // [web] JS interop class 'StaticJSClass' with `@staticInterop` annotation cannot declare instance members.
}

extension StaticJSClassExtension on StaticJSClass {
  external String externalField;
  external String get externalGetSet;
  external set externalGetSet(String val);
  external String externalMethod();

  String get getSet => this.externalGetSet;
  set getSet(String val) => this.externalGetSet = val;
  String method() => 'method';
}

// Abstract classes should behave the same way as concrete classes.
@JS()
@staticInterop
abstract class StaticAbstract {}

// Abstract classes with instance members should be non-static interop. The
// following have abstract or concrete members, so they're considered non-static
// interop.
@JS()
abstract class NonStaticAbstract {
  int abstractMethod();
}

@JS()
@staticInterop
abstract class NonStaticAbstractWithAbstractMembers {
  int abstractMethod();
  //  ^
  // [web] JS interop class 'NonStaticAbstractWithAbstractMembers' with `@staticInterop` annotation cannot declare instance members.
}

@JS()
@staticInterop
abstract class NonStaticAbstractWithConcreteMembers {
  external int instanceMethod();
  //           ^
  // [web] JS interop class 'NonStaticAbstractWithConcreteMembers' with `@staticInterop` annotation cannot declare instance members.
}
