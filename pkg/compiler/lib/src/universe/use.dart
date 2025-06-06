// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// This library defines individual world impacts.
///
/// We call these building blocks `uses`. Each `use` is a single impact of the
/// world. Some example uses are:
///
///  * an invocation of a top level function
///  * a call to the `foo()` method on an unknown class.
///  * an instantiation of class T
///
/// The different compiler stages combine these uses into `WorldImpact` objects,
/// which are later used to construct a closed-world understanding of the
/// program.
library;

import 'package:kernel/ast.dart' as ir;

import '../common.dart';
import '../constants/values.dart';
import '../elements/types.dart';
import '../elements/entities.dart';
import '../inferrer/abstract_value_domain.dart';
import '../serialization/serialization.dart';
import '../js_model/closure.dart' show JContextField;
import '../util/enumset.dart';
import '../util/util.dart' show equalElements, Hashing;
import 'call_structure.dart' show CallStructure;
import 'selector.dart' show Selector;
import 'world_impact.dart';

enum DynamicUseKind { invoke, get, set }

/// The use of a dynamic property. [selector] defined the name and kind of the
/// property and [receiverConstraint] defines the known constraint for the
/// object on which the property is accessed.
class DynamicUse {
  static const String tag = 'dynamic-use';

  final Selector selector;
  final Object? receiverConstraint;
  final List<DartType>? _typeArguments;

  DynamicUse(this.selector, this.receiverConstraint, this._typeArguments)
    : assert(
        selector.callStructure.typeArgumentCount ==
            (_typeArguments?.length ?? 0),
        "Type argument count mismatch. Selector has "
        "${selector.callStructure.typeArgumentCount} but "
        "${_typeArguments?.length ?? 0} were passed.",
      );

  DynamicUse withReceiverConstraint(Object? otherReceiverConstraint) {
    if (otherReceiverConstraint == receiverConstraint) {
      return this;
    }
    return DynamicUse(selector, otherReceiverConstraint, _typeArguments);
  }

  factory DynamicUse.readFromDataSource(DataSourceReader source) {
    source.begin(tag);
    Selector selector = Selector.readFromDataSource(source);
    bool hasConstraint = source.readBool();
    Object? receiverConstraint;
    if (hasConstraint) {
      receiverConstraint = source.readAbstractValue();
    }
    List<DartType>? typeArguments = source.readDartTypesOrNull();
    source.end(tag);
    return DynamicUse(selector, receiverConstraint, typeArguments);
  }

  void writeToDataSink(DataSinkWriter sink) {
    sink.begin(tag);
    selector.writeToDataSink(sink);
    var constraint = receiverConstraint;
    sink.writeBool(constraint != null);
    if (constraint != null) {
      if (constraint is AbstractValue) {
        sink.writeAbstractValue(constraint);
      } else {
        throw UnsupportedError("Unsupported receiver constraint: $constraint");
      }
    }
    sink.writeDartTypesOrNull(_typeArguments);
    sink.end(tag);
  }

  /// Short textual representation use for testing.
  String get shortText {
    StringBuffer sb = StringBuffer();
    if (receiverConstraint != null) {
      final constraint = receiverConstraint;
      if (constraint is ClassEntity) {
        sb.write(constraint.name);
      } else {
        sb.write(constraint);
      }
      sb.write('.');
    }
    sb.write(selector.name);
    if (typeArguments.isNotEmpty) {
      sb.write('<');
      sb.write(typeArguments.join(','));
      sb.write('>');
    }
    if (selector.isCall) {
      sb.write(selector.callStructure.shortText);
    } else if (selector.isSetter) {
      sb.write('=');
    }
    return sb.toString();
  }

  DynamicUseKind get kind {
    if (selector.isGetter) {
      return DynamicUseKind.get;
    } else if (selector.isSetter) {
      return DynamicUseKind.set;
    } else {
      return DynamicUseKind.invoke;
    }
  }

  List<DartType> get typeArguments => _typeArguments ?? const [];

  @override
  int get hashCode => Hashing.listHash(
    typeArguments,
    Hashing.objectsHash(selector, receiverConstraint),
  );

  @override
  bool operator ==(other) {
    if (identical(this, other)) return true;
    if (other is! DynamicUse) return false;
    return selector == other.selector &&
        receiverConstraint == other.receiverConstraint &&
        equalElements(typeArguments, other.typeArguments);
  }

  @override
  String toString() => '$selector,$receiverConstraint,$typeArguments';
}

enum StaticUseKind {
  staticTearOff,
  superTearOff,
  superFieldSet,
  superGet,
  superSetterSet,
  superInvoke,
  instanceFieldGet,
  instanceFieldSet,
  closure,
  closureCall,
  callMethod,
  constructorInvoke,
  constConstructorInvoke,
  directInvoke,
  inlining,
  staticInvoke,
  staticGet,
  staticSet,
  fieldInit,
  fieldConstantInit,
  weakStaticTearOff,
}

enum _StaticUseFlag {
  type,
  callStructure,
  deferredImport,
  constant,
  typeArguments,
}

/// Statically known use of an [Entity].
// TODO(johnniwinther): Create backend-specific implementations with better
// invariants.
class StaticUse {
  static const String tag = 'static-use';

  final Entity element;
  final StaticUseKind kind;
  @override
  final int hashCode;

  static final Map<StaticUse, StaticUse> _cache = {};

  static void clearCache() => _cache.clear();

  static StaticUse internal(
    Entity element,
    StaticUseKind kind, {
    InterfaceType? type,
    CallStructure? callStructure,
    ImportEntity? deferredImport,
    ConstantValue? constant,
    List<DartType>? typeArguments,
  }) {
    StaticUse use;
    if (type == null &&
        callStructure == null &&
        deferredImport == null &&
        constant == null &&
        typeArguments == null) {
      use = StaticUse._(element, kind);
    } else {
      use = _ExtendedStaticUse._(
        element,
        kind,
        type: type,
        callStructure: callStructure,
        deferredImport: deferredImport,
        typeArguments: typeArguments,
        constant: constant,
      );
    }
    return _cache[use] ??= use;
  }

  /// Use the [StaticUse.internal] factory to ensure canonicalization.
  StaticUse._(this.element, this.kind, {int? hashCode})
    : hashCode = hashCode ?? Hashing.objectHash(element, kind.hashCode);

  factory StaticUse.readFromDataSource(DataSourceReader source) {
    source.begin(tag);
    MemberEntity element = source.readMember();
    StaticUseKind kind = source.readEnum(StaticUseKind.values);
    final bitMask = EnumSet<_StaticUseFlag>.fromRawBits(source.readInt());
    InterfaceType? type;
    CallStructure? callStructure;
    ImportEntity? deferredImport;
    ConstantValue? constant;
    List<DartType>? typeArguments;

    if (bitMask.contains(_StaticUseFlag.type)) {
      type = source.readDartType() as InterfaceType;
    }
    if (bitMask.contains(_StaticUseFlag.callStructure)) {
      callStructure = CallStructure.readFromDataSource(source);
    }
    if (bitMask.contains(_StaticUseFlag.deferredImport)) {
      deferredImport = source.readImport();
    }
    if (bitMask.contains(_StaticUseFlag.constant)) {
      constant = source.readConstant();
    }
    if (bitMask.contains(_StaticUseFlag.typeArguments)) {
      typeArguments = source.readDartTypes();
    }
    source.end(tag);
    return StaticUse.internal(
      element,
      kind,
      type: type,
      callStructure: callStructure,
      deferredImport: deferredImport,
      constant: constant,
      typeArguments: typeArguments,
    );
  }

  void writeToDataSink(DataSinkWriter sink) {
    sink.begin(tag);
    sink.writeMember(element as MemberEntity);
    sink.writeEnum(kind);
    final bitMask = EnumSet<_StaticUseFlag>.fromValues([
      if (type != null) _StaticUseFlag.type,
      if (callStructure != null) _StaticUseFlag.callStructure,
      if (deferredImport != null) _StaticUseFlag.deferredImport,
      if (constant != null) _StaticUseFlag.constant,
      if (typeArguments != null) _StaticUseFlag.typeArguments,
    ]);
    sink.writeInt(bitMask.mask.bits);
    if (type != null) {
      sink.writeDartType(type!);
    }
    if (callStructure != null) {
      callStructure!.writeToDataSink(sink);
    }
    if (deferredImport != null) {
      sink.writeImport(deferredImport!);
    }
    if (constant != null) {
      sink.writeConstant(constant!);
    }
    if (typeArguments != null) {
      sink.writeDartTypes(typeArguments!);
    }
    sink.end(tag);
  }

  bool _checkGenericInvariants() => true;

  CallStructure? get callStructure => null;

  ConstantValue? get constant => null;

  ImportEntity? get deferredImport => null;

  InterfaceType? get type => null;

  List<DartType>? get typeArguments => null;

  @override
  bool operator ==(other) {
    if (identical(this, other)) return true;
    if (other is _ExtendedStaticUse) return false;
    return other is StaticUse && element == other.element && kind == other.kind;
  }

  @override
  String toString() => 'StaticUse($element,$kind)';

  /// Short textual representation use for testing.
  String get shortText {
    StringBuffer sb = StringBuffer();
    switch (kind) {
      case StaticUseKind.instanceFieldSet:
      case StaticUseKind.superFieldSet:
      case StaticUseKind.superSetterSet:
      case StaticUseKind.staticSet:
        sb.write('set:');
        break;
      case StaticUseKind.fieldInit:
        sb.write('init:');
        break;
      case StaticUseKind.closure:
        sb.write('def:');
        break;
      case StaticUseKind.staticTearOff:
      case StaticUseKind.superTearOff:
      case StaticUseKind.superGet:
      case StaticUseKind.superInvoke:
      case StaticUseKind.instanceFieldGet:
      case StaticUseKind.closureCall:
      case StaticUseKind.callMethod:
      case StaticUseKind.constructorInvoke:
      case StaticUseKind.constConstructorInvoke:
      case StaticUseKind.directInvoke:
      case StaticUseKind.inlining:
      case StaticUseKind.staticInvoke:
      case StaticUseKind.staticGet:
      case StaticUseKind.fieldConstantInit:
      case StaticUseKind.weakStaticTearOff:
        break;
    }
    final member = element;
    if (member is MemberEntity) {
      if (member.enclosingClass != null) {
        sb.write(member.enclosingClass!.name);
        sb.write('.');
      }
    }
    if (member.name == null) {
      sb.write('<anonymous>');
    } else {
      sb.write(member.name);
    }
    if (typeArguments != null && typeArguments!.isNotEmpty) {
      sb.write('<');
      sb.write(typeArguments!.join(','));
      sb.write('>');
    }
    final callStructureLocal = callStructure;
    if (callStructureLocal != null) {
      sb.write('(');
      sb.write(callStructureLocal.positionalArgumentCount);
      if (callStructureLocal.namedArgumentCount > 0) {
        sb.write(',');
        sb.write(callStructureLocal.getOrderedNamedArguments().join(','));
      }
      sb.write(')');
    }
    if (deferredImport != null) {
      sb.write('{');
      sb.write(deferredImport!.name);
      sb.write('}');
    }
    if (constant != null) {
      sb.write('=');
      sb.write(constant!.toStructuredText(null));
    }
    return sb.toString();
  }

  /// Invocation of a static or top-level [element] with the given
  /// [callStructure].
  factory StaticUse.staticInvoke(
    FunctionEntity element,
    CallStructure callStructure, [
    List<DartType>? typeArguments,
    ImportEntity? deferredImport,
  ]) {
    assert(
      element.isStatic || element.isTopLevel,
      failedAt(
        element,
        "Static invoke element $element must be a top-level "
        "or static method.",
      ),
    );
    assert(
      element.isFunction,
      failedAt(element, "Static get element $element must be a function."),
    );
    StaticUse staticUse = StaticUse.internal(
      element,
      StaticUseKind.staticInvoke,
      callStructure: callStructure,
      typeArguments: typeArguments,
      deferredImport: deferredImport,
    );
    assert(staticUse._checkGenericInvariants());
    return staticUse;
  }

  /// Closurization of a static or top-level function [element].
  factory StaticUse.staticTearOff(
    FunctionEntity element, [
    ImportEntity? deferredImport,
  ]) {
    assert(
      element.isStatic || element.isTopLevel,
      failedAt(
        element,
        "Static tear-off element $element must be a top-level "
        "or static method.",
      ),
    );
    assert(
      element.isFunction,
      failedAt(element, "Static get element $element must be a function."),
    );
    return StaticUse.internal(
      element,
      StaticUseKind.staticTearOff,
      deferredImport: deferredImport,
    );
  }

  /// Weak reference to a tear-off of a static or top-level function [element].
  factory StaticUse.weakStaticTearOff(
    FunctionEntity element, [
    ImportEntity? deferredImport,
  ]) {
    assert(
      element.isStatic || element.isTopLevel,
      failedAt(
        element,
        "Weak tear-off element $element must be a top-level "
        "or static method.",
      ),
    );
    return StaticUse.internal(
      element,
      StaticUseKind.weakStaticTearOff,
      deferredImport: deferredImport,
    );
  }

  /// Read access of a static or top-level field or getter [element].
  factory StaticUse.staticGet(
    MemberEntity element, [
    ImportEntity? deferredImport,
  ]) {
    assert(
      element.isStatic || element.isTopLevel,
      failedAt(
        element,
        "Static get element $element must be a top-level "
        "or static field or getter.",
      ),
    );
    assert(
      element is FieldEntity || element.isGetter,
      failedAt(
        element,
        "Static get element $element must be a field or a getter.",
      ),
    );
    return StaticUse.internal(
      element,
      StaticUseKind.staticGet,
      deferredImport: deferredImport,
    );
  }

  /// Write access of a static or top-level field or setter [element].
  factory StaticUse.staticSet(
    MemberEntity element, [
    ImportEntity? deferredImport,
  ]) {
    assert(
      element.isStatic || element.isTopLevel,
      failedAt(
        element,
        "Static set element $element "
        "must be a top-level or static method.",
      ),
    );
    assert(
      (element is FieldEntity && element.isAssignable) || element.isSetter,
      failedAt(
        element,
        "Static set element $element must be a field or a setter.",
      ),
    );
    return StaticUse.internal(
      element,
      StaticUseKind.staticSet,
      deferredImport: deferredImport,
    );
  }

  /// Invocation of the lazy initializer for a static or top-level field
  /// [element].
  factory StaticUse.staticInit(FieldEntity element) {
    assert(
      element.isStatic || element.isTopLevel,
      failedAt(
        element,
        "Static init element $element must be a top-level "
        "or static method.",
      ),
    );
    return StaticUse.internal(element, StaticUseKind.fieldInit);
  }

  /// Invocation of a super method [element] with the given [callStructure].
  factory StaticUse.superInvoke(
    FunctionEntity element,
    CallStructure callStructure, [
    List<DartType>? typeArguments,
  ]) {
    assert(
      element.isInstanceMember,
      failedAt(
        element,
        "Super invoke element $element must be an instance method.",
      ),
    );
    StaticUse staticUse = StaticUse.internal(
      element,
      StaticUseKind.superInvoke,
      callStructure: callStructure,
      typeArguments: typeArguments,
    );
    assert(staticUse._checkGenericInvariants());
    return staticUse;
  }

  /// Read access of a super field or getter [element].
  factory StaticUse.superGet(MemberEntity element) {
    assert(
      element.isInstanceMember,
      failedAt(
        element,
        "Super get element $element must be an instance method.",
      ),
    );
    assert(
      element is FieldEntity || element.isGetter,
      failedAt(
        element,
        "Super get element $element must be a field or a getter.",
      ),
    );
    return StaticUse.internal(element, StaticUseKind.superGet);
  }

  /// Write access of a super field [element].
  factory StaticUse.superFieldSet(FieldEntity element) {
    assert(
      element.isInstanceMember,
      failedAt(
        element,
        "Super set element $element must be an instance method.",
      ),
    );
    return StaticUse.internal(element, StaticUseKind.superFieldSet);
  }

  /// Write access of a super setter [element].
  factory StaticUse.superSetterSet(FunctionEntity element) {
    assert(
      element.isInstanceMember,
      failedAt(
        element,
        "Super set element $element must be an instance method.",
      ),
    );
    assert(
      element.isSetter,
      failedAt(element, "Super set element $element must be a setter."),
    );
    return StaticUse.internal(element, StaticUseKind.superSetterSet);
  }

  /// Closurization of a super method [element].
  factory StaticUse.superTearOff(FunctionEntity element) {
    assert(
      element.isInstanceMember && element.isFunction,
      failedAt(
        element,
        "Super invoke element $element must be an instance method.",
      ),
    );
    return StaticUse.internal(element, StaticUseKind.superTearOff);
  }

  /// Invocation of a constructor [element] through a this or super
  /// constructor call with the given [callStructure].
  factory StaticUse.superConstructorInvoke(
    ConstructorEntity element,
    CallStructure callStructure,
  ) {
    assert(
      element.isGenerativeConstructor,
      failedAt(
        element,
        "Constructor invoke element $element must be a "
        "generative constructor.",
      ),
    );
    return StaticUse.internal(
      element,
      StaticUseKind.staticInvoke,
      callStructure: callStructure,
    );
  }

  /// Invocation of a constructor (body) [element] through a this or super
  /// constructor call with the given [callStructure].
  factory StaticUse.constructorBodyInvoke(
    ConstructorBodyEntity element,
    CallStructure callStructure,
  ) {
    return StaticUse.internal(
      element,
      StaticUseKind.staticInvoke,
      callStructure: callStructure,
    );
  }

  /// Direct invocation of a generator (body) [element], as a static call or
  /// through a this or super constructor call.
  factory StaticUse.generatorBodyInvoke(FunctionEntity element) {
    return StaticUse.internal(
      element,
      StaticUseKind.staticInvoke,
      callStructure: CallStructure.noArgs,
    );
  }

  /// Direct invocation of a method [element] with the given [callStructure].
  factory StaticUse.directInvoke(
    FunctionEntity element,
    CallStructure callStructure,
    List<DartType>? typeArguments,
  ) {
    assert(
      element.isInstanceMember,
      failedAt(
        element,
        "Direct invoke element $element must be an instance member.",
      ),
    );
    assert(
      element.isFunction,
      failedAt(element, "Direct invoke element $element must be a method."),
    );
    StaticUse staticUse = StaticUse.internal(
      element,
      StaticUseKind.directInvoke,
      callStructure: callStructure,
      typeArguments: typeArguments,
    );
    assert(staticUse._checkGenericInvariants());
    return staticUse;
  }

  /// Direct read access of a field or getter [element].
  factory StaticUse.directGet(MemberEntity element) {
    assert(
      element.isInstanceMember,
      failedAt(
        element,
        "Direct get element $element must be an instance member.",
      ),
    );
    assert(
      element is FieldEntity || element.isGetter,
      failedAt(
        element,
        "Direct get element $element must be a field or a getter.",
      ),
    );
    return StaticUse.internal(element, StaticUseKind.staticGet);
  }

  /// Direct write access of a field [element].
  factory StaticUse.directSet(FieldEntity element) {
    assert(
      element.isInstanceMember,
      failedAt(
        element,
        "Direct set element $element must be an instance member.",
      ),
    );
    return StaticUse.internal(element, StaticUseKind.staticSet);
  }

  /// Constructor invocation of [element] with the given [callStructure].
  factory StaticUse.constructorInvoke(
    ConstructorEntity element,
    CallStructure callStructure,
  ) {
    return StaticUse.internal(
      element,
      StaticUseKind.staticInvoke,
      callStructure: callStructure,
    );
  }

  /// Constructor invocation of [element] with the given [callStructure] on
  /// [type].
  factory StaticUse.typedConstructorInvoke(
    ConstructorEntity element,
    CallStructure callStructure,
    InterfaceType type,
    ImportEntity? deferredImport,
  ) {
    return StaticUse.internal(
      element,
      StaticUseKind.constructorInvoke,
      type: type,
      callStructure: callStructure,
      deferredImport: deferredImport,
    );
  }

  /// Constant constructor invocation of [element] with the given
  /// [callStructure] on [type].
  factory StaticUse.constConstructorInvoke(
    ConstructorEntity element,
    CallStructure callStructure,
    InterfaceType type,
    ImportEntity? deferredImport,
  ) {
    return StaticUse.internal(
      element,
      StaticUseKind.constConstructorInvoke,
      type: type,
      callStructure: callStructure,
      deferredImport: deferredImport,
    );
  }

  /// Initialization of an instance field [element].
  factory StaticUse.fieldInit(FieldEntity element) {
    assert(
      element.isInstanceMember,
      failedAt(
        element,
        "Field init element $element must be an instance field.",
      ),
    );
    return StaticUse.internal(element, StaticUseKind.fieldInit);
  }

  /// Constant initialization of an instance field [element].
  factory StaticUse.fieldConstantInit(
    FieldEntity element,
    ConstantValue constant,
  ) {
    assert(
      element.isInstanceMember,
      failedAt(
        element,
        "Field init element $element must be an instance field.",
      ),
    );
    return StaticUse.internal(
      element,
      StaticUseKind.fieldConstantInit,
      constant: constant,
    );
  }

  /// Read access of an instance field or boxed field [element].
  factory StaticUse.fieldGet(FieldEntity element) {
    assert(
      element.isInstanceMember || element is JContextField,
      failedAt(
        element,
        "Field init element $element must be an instance or boxed field.",
      ),
    );
    return StaticUse.internal(element, StaticUseKind.instanceFieldGet);
  }

  /// Write access of an instance field or boxed field [element].
  factory StaticUse.fieldSet(FieldEntity element) {
    assert(
      element.isInstanceMember || element is JContextField,
      failedAt(
        element,
        "Field init element $element must be an instance or boxed field.",
      ),
    );
    return StaticUse.internal(element, StaticUseKind.instanceFieldSet);
  }

  /// Read of a local function [element].
  factory StaticUse.closure(Local element) {
    return StaticUse.internal(element, StaticUseKind.closure);
  }

  /// An invocation of a local function [element] with the provided
  /// [callStructure] and [typeArguments].
  factory StaticUse.closureCall(
    Local element,
    CallStructure callStructure,
    List<DartType>? typeArguments,
  ) {
    StaticUse staticUse = StaticUse.internal(
      element,
      StaticUseKind.closureCall,
      callStructure: callStructure,
      typeArguments: typeArguments,
    );
    assert(staticUse._checkGenericInvariants());
    return staticUse;
  }

  /// Read of a call [method] on a closureClass.
  factory StaticUse.callMethod(FunctionEntity method) {
    return StaticUse.internal(method, StaticUseKind.callMethod);
  }

  /// Implicit method/constructor invocation of [element] created by the
  /// backend.
  factory StaticUse.implicitInvoke(FunctionEntity element) {
    return StaticUse.internal(
      element,
      StaticUseKind.staticInvoke,
      callStructure: element.parameterStructure.callStructure,
    );
  }

  /// Inlining of [element].
  factory StaticUse.constructorInlining(
    ConstructorEntity element,
    InterfaceType? instanceType,
  ) {
    return StaticUse.internal(
      element,
      StaticUseKind.inlining,
      type: instanceType,
    );
  }

  /// Inlining of [element].
  factory StaticUse.methodInlining(
    FunctionEntity element,
    List<DartType>? typeArguments,
  ) {
    return StaticUse.internal(
      element,
      StaticUseKind.inlining,
      typeArguments: typeArguments,
    );
  }
}

/// A [StaticUse] which has additional data beyond its [element] and [kind].
///
/// This is only used when one or more of these exta fields are specified in
/// order to keep the representation of [StaticUse] compact when possible.
class _ExtendedStaticUse extends StaticUse {
  @override
  final InterfaceType? type;
  @override
  final CallStructure? callStructure;
  @override
  final ImportEntity? deferredImport;
  @override
  final ConstantValue? constant;
  @override
  final List<DartType>? typeArguments;

  /// Use the [StaticUse.internal] factory to ensure canonicalization.
  _ExtendedStaticUse._(
    super.element,
    super.kind, {
    this.type,
    this.callStructure,
    this.deferredImport,
    this.constant,
    this.typeArguments,
  }) : super._(
         hashCode: Hashing.listHash([
           element,
           kind,
           type,
           Hashing.listHash(typeArguments),
           callStructure,
           deferredImport,
           constant,
         ]),
       );

  @override
  bool _checkGenericInvariants() {
    assert(
      (callStructure?.typeArgumentCount ?? 0) == (typeArguments?.length ?? 0),
      failedAt(
        element,
        "Type argument count mismatch. Call structure has "
        "${callStructure?.typeArgumentCount ?? 0} but "
        "${typeArguments?.length ?? 0} were passed in $this.",
      ),
    );
    return true;
  }

  @override
  // ignore: hash_and_equals
  bool operator ==(other) {
    if (identical(this, other)) return true;
    // Subtypes of StaticUse are normalized so we can just compare against this
    // specific subtype.
    return other is _ExtendedStaticUse &&
        element == other.element &&
        kind == other.kind &&
        type == other.type &&
        callStructure == other.callStructure &&
        equalElements(typeArguments, other.typeArguments) &&
        deferredImport == other.deferredImport &&
        constant == other.constant;
  }

  @override
  String toString() =>
      'StaticUse($element,$kind,$type,$typeArguments,$callStructure)';
}

enum TypeUseKind {
  isCheck,
  asCast,
  catchType,
  typeLiteral,
  instantiation,
  nativeInstantiation,
  constInstantiation,
  recordInstantiation,
  constructorReference,
  implicitCast,
  parameterCheck,
  rtiValue,
  typeArgument,
  namedTypeVariable,
  typeVariableBoundCheck,
}

/// Use of a [DartType].
class TypeUse {
  static const String tag = 'type-use';

  final DartType type;
  final TypeUseKind kind;
  @override
  final int hashCode;
  final ImportEntity? deferredImport;

  TypeUse.internal(this.type, this.kind, [this.deferredImport])
    : hashCode = Hashing.objectsHash(type, kind, deferredImport);

  factory TypeUse.readFromDataSource(DataSourceReader source) {
    source.begin(tag);
    DartType type = source.readDartType();
    TypeUseKind kind = source.readEnum(TypeUseKind.values);
    ImportEntity? deferredImport = source.readImportOrNull();
    source.end(tag);
    return TypeUse.internal(type, kind, deferredImport);
  }

  void writeToDataSink(DataSinkWriter sink) {
    sink.begin(tag);
    sink.writeDartType(type);
    sink.writeEnum(kind);
    sink.writeImportOrNull(deferredImport);
    sink.end(tag);
  }

  /// Short textual representation use for testing.
  String get shortText {
    StringBuffer sb = StringBuffer();
    switch (kind) {
      case TypeUseKind.isCheck:
        sb.write('is:');
        break;
      case TypeUseKind.asCast:
        sb.write('as:');
        break;
      case TypeUseKind.catchType:
        sb.write('catch:');
        break;
      case TypeUseKind.typeLiteral:
        sb.write('lit:');
        break;
      case TypeUseKind.instantiation:
        sb.write('inst:');
        break;
      case TypeUseKind.constInstantiation:
        sb.write('const:');
        break;
      case TypeUseKind.recordInstantiation:
        sb.write('record:');
        break;
      case TypeUseKind.constructorReference:
        sb.write('constructor:');
        break;
      case TypeUseKind.nativeInstantiation:
        sb.write('native:');
        break;
      case TypeUseKind.implicitCast:
        sb.write('impl:');
        break;
      case TypeUseKind.parameterCheck:
        sb.write('param:');
        break;
      case TypeUseKind.rtiValue:
        sb.write('rti:');
        break;
      case TypeUseKind.typeArgument:
        sb.write('typeArg:');
        break;
      case TypeUseKind.namedTypeVariable:
        sb.write('named:');
        break;
      case TypeUseKind.typeVariableBoundCheck:
        sb.write('bound:');
        break;
    }
    sb.write(type);
    if (deferredImport != null) {
      sb.write('{');
      sb.write(deferredImport!.name);
      sb.write('}');
    }
    return sb.toString();
  }

  /// [type] used in an is check, like `e is T` or `e is! T`.
  factory TypeUse.isCheck(DartType type) {
    return TypeUse.internal(type, TypeUseKind.isCheck);
  }

  /// [type] used in an as cast, like `e as T`.
  factory TypeUse.asCast(DartType type) {
    return TypeUse.internal(type, TypeUseKind.asCast);
  }

  /// [type] used as a parameter type or field type in Dart 2, like `T` in:
  ///
  ///    method(T t) {}
  ///    T field;
  ///
  factory TypeUse.parameterCheck(DartType type) {
    return TypeUse.internal(type, TypeUseKind.parameterCheck);
  }

  /// [type] used in an implicit cast in Dart 2, like `T` in
  ///
  ///    dynamic foo = Object();
  ///    T bar = foo; // Implicitly `T bar = foo as T`.
  ///
  factory TypeUse.implicitCast(DartType type) {
    return TypeUse.internal(type, TypeUseKind.implicitCast);
  }

  /// [type] used in a on type catch clause, like `try {} on T catch (e) {}`.
  factory TypeUse.catchType(DartType type) {
    return TypeUse.internal(type, TypeUseKind.catchType);
  }

  /// [type] used as a type literal, like `foo() => T;`.
  factory TypeUse.typeLiteral(DartType type, ImportEntity? deferredImport) {
    return TypeUse.internal(type, TypeUseKind.typeLiteral, deferredImport);
  }

  /// [type] used in an instantiation, like `new T();`.
  factory TypeUse.instantiation(InterfaceType type) {
    return TypeUse.internal(type, TypeUseKind.instantiation);
  }

  /// [type] used in a constant instantiation, like `const T();`.
  factory TypeUse.constInstantiation(
    InterfaceType type,
    ImportEntity? deferredImport,
  ) {
    return TypeUse.internal(
      type,
      TypeUseKind.constInstantiation,
      deferredImport,
    );
  }

  /// [type] used in a native instantiation.
  factory TypeUse.nativeInstantiation(InterfaceType type) {
    return TypeUse.internal(type, TypeUseKind.nativeInstantiation);
  }

  /// [type] used in a record instantiation, like `(1, 2)` or `const (1, 2)`.
  factory TypeUse.recordInstantiation(RecordType type) {
    return TypeUse.internal(type, TypeUseKind.recordInstantiation);
  }

  /// [type] used as a direct RTI value.
  factory TypeUse.constTypeLiteral(DartType type) {
    return TypeUse.internal(type, TypeUseKind.rtiValue);
  }

  /// [type] constructor used, for example in a `instanceof` check.
  factory TypeUse.constructorReference(DartType type) {
    return TypeUse.internal(type, TypeUseKind.constructorReference);
  }

  /// [type] used directly as a type argument.
  ///
  /// The happens during optimization where a type variable can be replaced by
  /// an invariable type argument derived from a constant receiver.
  factory TypeUse.typeArgument(DartType type) {
    return TypeUse.internal(type, TypeUseKind.typeArgument);
  }

  /// [type] used as a named type variable in a recipe.
  factory TypeUse.namedTypeVariable(TypeVariableType type) =>
      TypeUse.internal(type, TypeUseKind.namedTypeVariable);

  /// [type] used as a bound on a type variable.
  factory TypeUse.typeVariableBoundCheck(DartType type) =>
      TypeUse.internal(type, TypeUseKind.typeVariableBoundCheck);

  @override
  bool operator ==(other) {
    if (identical(this, other)) return true;
    if (other is! TypeUse) return false;
    return type == other.type && kind == other.kind;
  }

  @override
  String toString() => 'TypeUse($type,$kind)';
}

/// Use of a [ConstantValue].
class ConstantUse {
  static const String tag = 'constant-use';

  final ConstantValue value;

  ConstantUse._(this.value);

  factory ConstantUse.readFromDataSource(DataSourceReader source) {
    source.begin(tag);
    ConstantValue value = source.readConstant();
    source.end(tag);
    return ConstantUse._(value);
  }

  void writeToDataSink(DataSinkWriter sink) {
    sink.begin(tag);
    sink.writeConstant(value);
    sink.end(tag);
  }

  /// Short textual representation use for testing.
  String get shortText {
    return value.toDartText(null);
  }

  /// Constant used as the initial value of a field.
  ConstantUse.init(ConstantValue value) : this._(value);

  /// Type constant used for registration of custom elements.
  ConstantUse.customElements(TypeConstantValue value) : this._(value);

  /// Constant literal used in code.
  ConstantUse.literal(ConstantValue value) : this._(value);

  /// Deferred constant used in code.
  ConstantUse.deferred(DeferredGlobalConstantValue value) : this._(value);

  @override
  bool operator ==(other) {
    if (identical(this, other)) return true;
    if (other is! ConstantUse) return false;
    return value == other.value;
  }

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'ConstantUse(${value.toStructuredText(null)})';
}

/// Conditional impact and Kernel nodes for replacement if it isn't applied.
///
/// If one of [original], [replacement], or [replacementImpact] is provided, the
/// others must also be provided.
class ConditionalUse {
  /// If any of the members in this list are reachable from the program then
  /// these conditions are considered "satisfied", [original] is kept in the
  /// Kernel tree and [impact] is applied to the world. Otherwise [original] is
  /// replaced with [replacement] in the Kernel tree and [replacementImpact] is
  /// instead applied to the world.
  final List<MemberEntity> originalConditions;

  /// The node to replace if [originalConditions] are not satisfied.
  /// [impact] is the impact implied by this node.
  final ir.TreeNode? original;

  /// The node to replace [original] with is [originalConditions] are not
  /// satisfied.
  final ir.TreeNode? replacement;

  /// The impact to apply for [original] if [originalConditions] are satisfied.
  final WorldImpact impact;

  /// The impact to apply for [replacement] if [originalConditions] are not
  /// satisifed.
  final WorldImpact? replacementImpact;

  ConditionalUse.noReplacement({
    required this.impact,
    required this.originalConditions,
  }) : original = null,
       replacement = null,
       replacementImpact = null,
       assert(originalConditions.isNotEmpty);

  ConditionalUse.withReplacement({
    required this.original,
    required this.replacement,
    required this.replacementImpact,
    required this.impact,
    required this.originalConditions,
  }) : assert(originalConditions.isNotEmpty);
}
