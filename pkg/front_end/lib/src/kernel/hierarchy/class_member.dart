// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:kernel/ast.dart';
import 'package:kernel/type_algebra.dart';

import '../../base/messages.dart'
    show
        LocatedMessage,
        messageDeclaredMemberConflictsWithInheritedMembersCause,
        messageDeclaredMemberConflictsWithOverriddenMembersCause,
        templateCombinedMemberSignatureFailed,
        templateExtensionTypeCombinedMemberSignatureFailed;
import '../../builder/declaration_builders.dart';
import '../../builder/member_builder.dart';
import '../../builder/property_builder.dart';
import '../../source/source_class_builder.dart';
import '../../source/source_extension_type_declaration_builder.dart';
import '../../source/source_library_builder.dart' show SourceLibraryBuilder;
import '../combined_member_signature.dart';
import '../forwarding_node.dart' show ForwardingNode;
import '../member_covariance.dart';
import 'members_builder.dart';

/// The result of a member computation through [ClassMember].
sealed class MemberResult {
  /// Returns `true` if the member was declared as a field.
  ///
  /// This is used for messaging in error reporting.
  bool get isDeclaredAsField;

  /// Returns the full name of this member, i.e. the member name prefixed by
  /// the name of its enclosing declaration.
  String get fullName;

  /// Returns the file offset for the declaration of this member.
  ///
  /// This is used for error reporting.
  int get fileOffset;

  /// Returns the file uri for the declaration of this member.
  ///
  /// This is used for error reporting.
  Uri get fileUri;

  /// Returns the type of this member as found through a receiver of static
  /// type [thisType].
  ///
  /// The type depends of the kind of member: The type of a field is the field
  /// type, the type of a getter is the return type, the type of a setter is
  /// the parameter type and the type of a method is the tear-off type.
  DartType getMemberType(
      ClassMembersBuilder membersBuilder, TypeDeclarationType thisType);
}

class TypeDeclarationInstanceMemberResult implements MemberResult {
  final Member member;
  final ClassMemberKind kind;
  @override
  final bool isDeclaredAsField;

  TypeDeclarationInstanceMemberResult(this.member, this.kind,
      {required this.isDeclaredAsField})
      : assert(
            member.enclosingTypeDeclaration != null,
            "Type declaration member without enclosing type "
            "declaration $member.");

  @override
  String get fullName {
    Member origin = member.memberSignatureOrigin ?? member;
    return '${origin.enclosingTypeDeclaration!.name}.${origin.name.text}';
  }

  @override
  int get fileOffset {
    Member origin = member.memberSignatureOrigin ?? member;
    return origin.fileOffset;
  }

  @override
  Uri get fileUri {
    Member origin = member.memberSignatureOrigin ?? member;
    return origin.fileUri;
  }

  @override
  DartType getMemberType(
      ClassMembersBuilder membersBuilder, TypeDeclarationType thisType) {
    DartType type = switch (kind) {
      ClassMemberKind.Method => // Coverage-ignore(suite): Not run.
        member.getterType,
      ClassMemberKind.Getter => member.getterType,
      ClassMemberKind.Setter => member.setterType,
    };
    TypeDeclaration typeDeclaration = member.enclosingTypeDeclaration!;
    if (typeDeclaration.typeParameters.isNotEmpty) {
      type = Substitution.fromPairs(
              typeDeclaration.typeParameters,
              membersBuilder.hierarchyBuilder.types
                  .getTypeArgumentsAsInstanceOf(thisType, typeDeclaration)!)
          .substituteType(type);
    }
    return type;
  }
}

class StaticMemberResult implements MemberResult {
  final Member member;
  final ClassMemberKind kind;
  @override
  final bool isDeclaredAsField;
  @override
  final String fullName;

  StaticMemberResult(this.member, this.kind,
      {required this.isDeclaredAsField, required this.fullName});

  @override
  int get fileOffset {
    Member origin = member.memberSignatureOrigin ?? member;
    return origin.fileOffset;
  }

  @override
  Uri get fileUri {
    Member origin = member.memberSignatureOrigin ?? member;
    return origin.fileUri;
  }

  @override
  DartType getMemberType(
      ClassMembersBuilder membersBuilder, TypeDeclarationType thisType) {
    return switch (kind) {
      ClassMemberKind.Method => // Coverage-ignore(suite): Not run.
        member.getterType,
      ClassMemberKind.Getter => member.getterType,
      ClassMemberKind.Setter => member.setterType,
    };
  }
}

class ExtensionTypeMemberResult implements MemberResult {
  final ExtensionTypeDeclaration extensionTypeDeclaration;
  final Member member;
  final ClassMemberKind kind;
  final Name name;
  @override
  final bool isDeclaredAsField;

  ExtensionTypeMemberResult(
      this.extensionTypeDeclaration, this.member, this.kind, this.name,
      {required this.isDeclaredAsField})
      : assert(member.isExtensionTypeMember);

  @override
  String get fullName {
    return '${extensionTypeDeclaration.name}.${name.text}';
  }

  @override
  int get fileOffset {
    return member.fileOffset;
  }

  @override
  Uri get fileUri {
    return member.fileUri;
  }

  @override
  DartType getMemberType(
      ClassMembersBuilder membersBuilder, TypeDeclarationType thisType) {
    assert(member.getterType is FunctionType,
        "Unexpected member type for $member (${member.runtimeType}).");
    FunctionType type = member.getterType as FunctionType;
    if (type.typeParameters.isNotEmpty) {
      // Coverage-ignore-block(suite): Not run.
      type = FunctionTypeInstantiator.instantiate(
          type,
          membersBuilder.hierarchyBuilder.types.getTypeArgumentsAsInstanceOf(
              thisType, extensionTypeDeclaration)!);
    }
    switch (kind) {
      case ClassMemberKind.Method:
        // Coverage-ignore(suite): Not run.
        // For methods [member] is the tear-off so the member type is the return
        // type.
        return type.returnType;
      case ClassMemberKind.Getter:
        return type.returnType;
      case ClassMemberKind.Setter:
        return type.positionalParameters[1];
    }
  }
}

enum ClassMemberKind {
  Method,
  Getter,
  Setter,
}

abstract class ClassMember {
  Name get name;
  bool get isStatic;
  bool get isSetter;
  bool get forSetter;

  ClassMemberKind get memberKind;

  /// Returns `true` if this member corresponds to a declaration in the source
  /// code.
  bool get isSourceDeclaration;

  /// Returns `true` if this member is a field, getter or setter.
  bool get isProperty;

  /// Computes the [Member] node resulting from this class member.
  Member getMember(ClassMembersBuilder membersBuilder);

  /// Computes the tear off [Member] node resulting from this class member, if
  /// this is different from the [Member] returned from [getMember].
  ///
  /// Returns `null` if this class member does not have a tear off.
  Member? getTearOff(ClassMembersBuilder membersBuilder);

  /// Returns the member [Covariance] for this class member.
  Covariance getCovariance(ClassMembersBuilder membersBuilder);

  // TODO(johnniwinther): Combine [getMemberResult] with [getMember],
  // [getTearOff], and [getCovariance] and use for member type computation.
  /// Computes the [MemberResult] node resulting from this class member.
  MemberResult getMemberResult(ClassMembersBuilder membersBuilder);

  bool get isDuplicate;

  /// The name of the member prefixed by the name of the enclosing declaration.
  String get fullName;

  /// The name corresponding to the [Builder.fullNameForErrors].
  // TODO(johnniwinther): We need better semantics for this.
  String get fullNameForErrors;

  /// Returns the enclosing declaration of this member.
  DeclarationBuilder get declarationBuilder;

  /// Returns `true` if this class member is declared in Object from dart:core.
  bool isObjectMember(ClassBuilder objectClass);

  /// If this member is declared in an extension type declaration.
  ///
  /// This includes explicit extension type members, static or instance, and
  /// the representation field, but _not_ non-extension type members inherited
  /// into the extension type declaration.
  bool get isExtensionTypeMember;

  Uri get fileUri;
  int get charOffset;

  /// Returns `true` if this class member is an interface member.
  bool get isAbstract;

  /// Returns `true` if this member doesn't corresponds to a declaration in the
  /// source code.
  bool get isSynthesized;

  /// Returns `true` if this member is a noSuchMethod forwarder.
  bool get isNoSuchMethodForwarder;

  /// Returns `true` if this member is composed from a list of class members
  /// accessible through [declarations].
  bool get hasDeclarations;

  /// If [hasDeclaration] is `true`, this returns the list of class members
  /// from which this class member is composed.
  ///
  /// This is used in [unfoldDeclarations] to retrieve all underlying member
  /// source declarations, and in [toSet] to retrieve all members used for
  /// this class member wrt. certain level of the hierarchy.
  /// TODO(johnniwinther): Can the use of [toSet] be replaced with a direct
  /// use of [declarations]?
  List<ClassMember> get declarations;

  /// The interface member corresponding to this member.
  ///
  /// If this member is declared in the source, the interface member is
  /// the member itself. For instance
  ///
  ///     abstract class Class {
  ///        void concreteMethod() {}
  ///        void abstractMethod();
  ///     }
  ///
  /// the interface members for `concreteMethod` and `abstractMethod` are the
  /// members themselves.
  ///
  /// If this member is a synthesized interface member, the
  /// interface member is the member itself. For instance
  ///
  ///     abstract class Interface1 {
  ///        void method() {}
  ///     }
  ///     abstract class Interface2 {
  ///        void method() {}
  ///     }
  ///     abstract class Class implements Interface1, Interface2 {}
  ///
  /// the interface member for `method` in `Class` is the synthesized interface
  /// member created for the implemented members `Interface1.method` and
  /// `Interface2.method`.
  ///
  /// If this member is a concrete member that implements an interface member,
  /// the interface member is the implemented interface member. For instance
  ///
  ///     class Super {
  ///        void method() {}
  ///     }
  ///     class Interface {
  ///        void method() {}
  ///     }
  ///     class Class extends Super implements Interface {}
  ///
  /// the interface member for `Super.method` implementing `method` in `Class`
  /// is the synthesized interface member created for the implemented members
  /// `Super.method` and `Interface.method`.
  ClassMember get interfaceMember;

  void inferType(ClassMembersBuilder membersBuilder);

  /// Registers that this class member overrides [overriddenMembers].
  ///
  /// This is used to infer types from the [overriddenMembers].
  void registerOverrideDependency(
      ClassMembersBuilder membersBuilder, Set<ClassMember> overriddenMembers);

  /// Returns `true` if this has the same underlying declaration as [other].
  ///
  /// This is used for avoiding unnecessary checks and can this trivially
  /// return `false`.
  bool isSameDeclaration(ClassMember other);
}

abstract class SynthesizedMember extends ClassMember {
  @override
  final Name name;

  @override
  final ClassMemberKind memberKind;

  SynthesizedMember(this.name, this.memberKind);

  @override
  bool get forSetter => memberKind == ClassMemberKind.Setter;

  @override
  bool get isProperty => memberKind != ClassMemberKind.Method;

  @override
  // Coverage-ignore(suite): Not run.
  List<ClassMember> get declarations => throw new UnimplementedError();

  @override
  // Coverage-ignore(suite): Not run.
  void inferType(ClassMembersBuilder membersBuilder) {}

  @override
  bool get isDuplicate => false;

  @override
  bool get isSetter => forSetter;

  @override
  bool get isSourceDeclaration => false;

  @override
  bool get isStatic => false;

  @override
  // Coverage-ignore(suite): Not run.
  bool get isSynthesized => true;

  @override
  // Coverage-ignore(suite): Not run.
  void registerOverrideDependency(
      ClassMembersBuilder membersBuilder, Set<ClassMember> overriddenMembers) {}

  @override
  MemberResult getMemberResult(ClassMembersBuilder membersBuilder) {
    return new TypeDeclarationInstanceMemberResult(
        getMember(membersBuilder), memberKind,
        isDeclaredAsField: false);
  }

  @override
  // Coverage-ignore(suite): Not run.
  bool get isExtensionTypeMember => false;

  @override
  // Coverage-ignore(suite): Not run.
  Member? getTearOff(ClassMembersBuilder membersBuilder) {
    // Ensure member is computed.
    getMember(membersBuilder);
    return null;
  }
}

/// Class member for a set of interface members.
///
/// This is used to compute combined member signature of a set of interface
/// members inherited into the same class, and to insert forwarding stubs,
/// mixin stubs, and member signatures where needed.
class SynthesizedInterfaceMember extends SynthesizedMember {
  final ClassBuilder classBuilder;

  @override
  final List<ClassMember> declarations;

  /// The concrete member in the super class overridden by [declarations], if
  /// any.
  ///
  /// This is used to as the target when creating concrete forwarding and mixin
  /// stub. For instance:
  ///
  ///    class Super {
  ///      method(int i) {}
  ///    }
  ///    class Interface {
  ///      method(covariant int i) {}
  ///    }
  ///    class Class extends Super implements Interface {
  ///      // Concrete forwarding stub calling [_superClassMember]:
  ///      method(covariant int i) => super.method(i);
  ///
  final ClassMember? _superClassMember;

  /// The canonical member of the combined member signature if it is known by
  /// construction. The canonical member defines the type of combined member
  /// signature.
  ///
  /// This is used when a declared member is part of a set of implemented
  /// members. For instance
  ///
  ///     class Super {
  ///       method(int i) {}
  ///     }
  ///     class Interface {
  ///       method(covariant num i) {}
  ///     }
  ///     class Class implements Interface {
  ///       // This member is updated to be a concrete forwarding stub with an
  ///       // covariant parameter but with its declared parameter type:
  ///       //    method(covariant int i) => super.method(i);
  ///       method(int i);
  ///     }
  final ClassMember? _canonicalMember;

  /// The member in [declarations] that is mixed in, if any.
  ///
  /// This is used to create mixin stubs. If the mixed in member is abstract,
  /// an abstract mixin stub is created:
  ///
  ///    class Super {
  ///      void method() {}
  ///    }
  ///    class Mixin {
  ///      void method();
  ///    }
  ///    // Abstract mixin stub with `Mixin.method` as target inserted:
  ///    //   void method();
  ///    class Class = Super with Mixin;
  ///
  /// If the mixed in member is concrete, a concrete mixin member is created:
  ///
  ///    class Super {
  ///      void method() {}
  ///    }
  ///    class Mixin {
  ///      void method() {}
  ///    }
  ///    // Concrete mixin stub with `Mixin.method` as target inserted:
  ///    //   void method() => super.method();
  ///    class Class = Super with Mixin;
  ///
  /// If a forwarding stub is needed, the created stub will be a possibly
  /// concrete forwarding stub:
  ///
  ///    class Super {
  ///      void method(int i) {}
  ///    }
  ///    class Interface {
  ///      void method(covariant num i) {}
  ///    }
  ///    class Mixin {
  ///      void method(int i);
  ///    }
  ///    // Concrete forwarding stub with `Super.method` as target inserted:
  ///    //   void method(covariant int i) => super.method(i);
  ///    class Class = Super with Mixin implements Interface;
  ///
  final ClassMember? _mixedInMember;

  /// If `true`, a stub should be inserted, if needed.
  final bool _shouldModifyKernel;

  Member? _member;
  Covariance? _covariance;

  ClassMember? _noSuchMethodTarget;

  SynthesizedInterfaceMember(this.classBuilder, Name name, this.declarations,
      {ClassMember? superClassMember,
      ClassMember? canonicalMember,
      ClassMember? mixedInMember,
      ClassMember? noSuchMethodTarget,
      required ClassMemberKind memberKind,
      required bool shouldModifyKernel})
      : this._superClassMember = superClassMember,
        this._canonicalMember = canonicalMember,
        this._mixedInMember = mixedInMember,
        this._noSuchMethodTarget = noSuchMethodTarget,
        this._shouldModifyKernel = shouldModifyKernel,
        super(name, memberKind);

  @override
  bool get hasDeclarations => true;

  @override
  DeclarationBuilder get declarationBuilder => classBuilder;

  void _ensureMemberAndCovariance(ClassMembersBuilder membersBuilder) {
    if (_member != null) {
      return;
    }
    if (classBuilder.libraryBuilder is! SourceLibraryBuilder) {
      if (_canonicalMember != null) {
        _member = _canonicalMember.getMember(membersBuilder);
        _covariance = _canonicalMember.getCovariance(membersBuilder);
      } else {
        _member = declarations.first.getMember(membersBuilder);
        _covariance = declarations.first.getCovariance(membersBuilder);
      }
      return;
    }
    CombinedMemberSignatureBase combinedMemberSignature;
    if (_canonicalMember != null) {
      combinedMemberSignature = new CombinedClassMemberSignature.internal(
          membersBuilder,
          classBuilder,
          declarations.indexOf(_canonicalMember),
          declarations,
          forSetter: isSetter);
    } else {
      combinedMemberSignature = new CombinedClassMemberSignature(
          membersBuilder, classBuilder, declarations,
          forSetter: isSetter);

      if (combinedMemberSignature.canonicalMember == null) {
        String name = classBuilder.fullNameForErrors;
        int nameLength =
            classBuilder.isAnonymousMixinApplication ? 1 : name.length;
        List<LocatedMessage> context = declarations.map((ClassMember d) {
          return messageDeclaredMemberConflictsWithOverriddenMembersCause
              .withLocation(
                  d.fileUri, d.charOffset, d.fullNameForErrors.length);
        }).toList();

        classBuilder.addProblem(
            templateCombinedMemberSignatureFailed.withArguments(
                name, declarations.first.fullNameForErrors),
            classBuilder.fileOffset,
            nameLength,
            context: context);
        // TODO(johnniwinther): Maybe we should have an invalid marker to avoid
        // cascading errors.
        _member = declarations.first.getMember(membersBuilder);
        _covariance = declarations.first.getCovariance(membersBuilder);
        return;
      }
    }

    if (_shouldModifyKernel) {
      SourceClassBuilder sourceClassBuilder =
          classBuilder as SourceClassBuilder;
      SourceLibraryBuilder libraryBuilder = sourceClassBuilder.libraryBuilder;
      ProcedureKind kind = ProcedureKind.Method;
      Member canonicalMember =
          combinedMemberSignature.canonicalMember!.getMember(membersBuilder);
      if (combinedMemberSignature.canonicalMember!.isProperty) {
        kind = isSetter ? ProcedureKind.Setter : ProcedureKind.Getter;
      } else if (canonicalMember is Procedure &&
          canonicalMember.kind == ProcedureKind.Operator) {
        kind = ProcedureKind.Operator;
      }

      Procedure? stub = new ForwardingNode(
              libraryBuilder,
              sourceClassBuilder,
              sourceClassBuilder.cls,
              sourceClassBuilder.indexedClass,
              combinedMemberSignature,
              kind,
              superClassMember: _superClassMember,
              mixedInMember: _mixedInMember,
              noSuchMethodTarget: _noSuchMethodTarget,
              declarationIsMixinApplication:
                  sourceClassBuilder.isMixinApplication)
          .finalize();
      if (stub != null) {
        assert(classBuilder.cls == stub.enclosingClass);
        assert(stub != canonicalMember);
        classBuilder.cls.addProcedure(stub);
        if (libraryBuilder.fieldNonPromotabilityInfo
                ?.individualPropertyReasons[canonicalMember]
            case var reason?) {
          // Transfer the non-promotability reason to the stub, so that accesses
          // to the stub will still cause the appropriate "why not promoted"
          // context message to be generated.
          libraryBuilder.fieldNonPromotabilityInfo!
              .individualPropertyReasons[stub] = reason;
        }
        if (canonicalMember is Procedure) {
          libraryBuilder.forwardersOrigins
            ..add(stub)
            ..add(canonicalMember);
        }
        _member = stub;
        _covariance = combinedMemberSignature.combinedMemberSignatureCovariance;
        assert(
            _covariance ==
                new Covariance.fromMember(_member!, forSetter: forSetter),
            "Unexpected covariance for combined members signature "
            "$_member. Found $_covariance, expected "
            "${new Covariance.fromMember(_member!, forSetter: forSetter)}.");
        return;
      }
    }

    _member =
        combinedMemberSignature.canonicalMember!.getMember(membersBuilder);
    _covariance = combinedMemberSignature.combinedMemberSignatureCovariance;
  }

  @override
  Member getMember(ClassMembersBuilder membersBuilder) {
    _ensureMemberAndCovariance(membersBuilder);
    return _member!;
  }

  @override
  Covariance getCovariance(ClassMembersBuilder membersBuilder) {
    _ensureMemberAndCovariance(membersBuilder);
    return _covariance!;
  }

  @override
  ClassMember get interfaceMember => this;

  @override
  // Coverage-ignore(suite): Not run.
  bool isObjectMember(ClassBuilder objectClass) {
    return false;
  }

  @override
  bool isSameDeclaration(ClassMember other) {
    // TODO(johnniwinther): Optimize this.
    return false;
  }

  @override
  bool get isNoSuchMethodForwarder =>
      _noSuchMethodTarget != null && _shouldModifyKernel;

  @override
  int get charOffset => declarations.first.charOffset;

  @override
  Uri get fileUri => declarations.first.fileUri;

  @override
  bool get isAbstract => _noSuchMethodTarget == null;

  @override
  String get fullNameForErrors =>
      declarations.map((ClassMember m) => m.fullName).join("%");

  @override
  // Coverage-ignore(suite): Not run.
  String get fullName {
    String suffix = isSetter ? "=" : "";
    return "${fullNameForErrors}$suffix";
  }

  @override
  String toString() => 'SynthesizedInterfaceMember($classBuilder,$name,'
      '$declarations,forSetter=$forSetter)';
}

/// Class member for an inherited concrete member that implements an interface
/// member.
///
/// This is used to ensure that both the inherited concrete member and the
/// interface member is taken into account when computing the resulting [Member]
/// node.
///
/// This is needed because an interface member, though initially abstract, can
/// result in a concrete stub that overrides the concrete member. For instance
///
///    class Super {
///      method(int i) {}
///    }
///    class Interface {
///      method(covariant int i) {}
///    }
///    class Class extends Super implements Interface {
///      // A concrete forwarding stub is inserted:
///      method(covariant int i) => super.method(i);
///    }
///    class Sub extends Class implements Interface {
///      // No forwarding stub should be inserted since `Class.method` is
///      // adequate.
///    }
///
///
///  Here the create stub `Class.method` overrides `Super.method` and should
///  be used to determine whether to insert a forwarding stub in subclasses.
class InheritedClassMemberImplementsInterface extends SynthesizedMember {
  final ClassBuilder classBuilder;
  final ClassMember inheritedClassMember;
  final ClassMember implementedInterfaceMember;

  Member? _member;
  Covariance? _covariance;

  InheritedClassMemberImplementsInterface(this.classBuilder, Name name,
      {required this.inheritedClassMember,
      required this.implementedInterfaceMember,
      required ClassMemberKind memberKind})
      : super(name, memberKind);

  @override
  DeclarationBuilder get declarationBuilder => classBuilder;

  void _ensureMemberAndCovariance(ClassMembersBuilder membersBuilder) {
    if (_member == null) {
      Member classMember = inheritedClassMember.getMember(membersBuilder);
      Member interfaceMember =
          implementedInterfaceMember.getMember(membersBuilder);
      if (!interfaceMember.isAbstract &&
          interfaceMember.enclosingClass == classBuilder.cls) {
        /// The interface member resulted in a concrete stub being inserted.
        /// For instance for `method1` but _not_ for `method2` here:
        ///
        ///    class Super {
        ///      method1(int i) {}
        ///      method2(covariant int i) {}
        ///    }
        ///    class Interface {
        ///      method1(covariant int i) {}
        ///      method2(int i) {}
        ///    }
        ///    class Class extends Super implements Interface {
        ///      // A concrete forwarding stub is inserted for `method1` since
        ///      // the parameter on `Super.method1` is _not_ marked as
        ///      // covariant:
        ///      method1(covariant int i) => super.method(i);
        ///      // No concrete forwarding stub is inserted for `method2` since
        ///      // the parameter on `Super.method2` is already marked as
        ///      // covariant.
        ///    }
        ///
        /// The inserted stub should be used as the resulting member.
        _member = interfaceMember;
        _covariance = implementedInterfaceMember.getCovariance(membersBuilder);
      } else {
        /// The interface member did not result in an inserted stub or the
        /// inserted stub was abstract. For instance:
        ///
        ///    // Opt-in:
        ///    class Super {
        ///      method(int? i) {}
        ///    }
        ///    // Opt-out:
        ///    class Class extends Super {
        ///      // An abstract member signature stub is inserted:
        ///      method(int* i);
        ///    }
        ///
        /// The inserted stub should _not_ be used as the resulting member
        /// since it is abstract and therefore not a class member.
        _member = classMember;
        _covariance = inheritedClassMember.getCovariance(membersBuilder);
      }
    }
  }

  @override
  Member getMember(ClassMembersBuilder membersBuilder) {
    _ensureMemberAndCovariance(membersBuilder);
    return _member!;
  }

  @override
  Covariance getCovariance(ClassMembersBuilder membersBuilder) {
    _ensureMemberAndCovariance(membersBuilder);
    return _covariance!;
  }

  @override
  ClassMember get interfaceMember => implementedInterfaceMember;

  @override
  // Coverage-ignore(suite): Not run.
  bool isObjectMember(ClassBuilder objectClass) {
    return inheritedClassMember.isObjectMember(objectClass);
  }

  @override
  // Coverage-ignore(suite): Not run.
  bool isSameDeclaration(ClassMember other) {
    // TODO(johnniwinther): Optimize this.
    return false;
  }

  @override
  bool get isNoSuchMethodForwarder {
    // [implementedInterfaceMember] can only be a noSuchMethod forwarder if
    // [inheritedClassMember] also is, since we don't allow overriding a regular
    // member with a noSuchMethodForwarder.
    //
    // If the current class is abstract, [inheritedClassMember] can be a
    // a noSuchMethod forwarder while [implementedInterfaceMember] is not,
    // because we only insert noSuchMethod forwarders into non-abstract classes.
    //
    // For instance
    //
    //     class Super {
    //       noSuchMethod(_) => null;
    //       method1(); // noSuchMethod forwarder created for this.
    //       method2(int i); // noSuchMethod forwarder created for this.
    //       method3(int i); // noSuchMethod forwarder created for this.
    //       method4(int i) {}
    //     }
    //     abstract class Abstract extends Super {
    //       method2(num i); // No noSuchMethod forwarder will be inserted here.
    //     }
    //     class Class extends Abstract {
    //       method1(); // noSuchMethod forwarder from Super is valid.
    //       /* method2(num i) */ // A new noSuchMethod forwarder is created.
    //       method3(num i); // A new noSuchMethod forwarder is created.
    //       method4(num i); // No noSuchMethod forwarder will be inserted
    //                       // and this will be an error.
    //     }
    //
    assert(
        !(implementedInterfaceMember.isNoSuchMethodForwarder &&
            !inheritedClassMember.isNoSuchMethodForwarder),
        "The inherited $inheritedClassMember has "
        "isNoSuchMethodForwarder="
        "${inheritedClassMember.isNoSuchMethodForwarder} but "
        "the implemented $implementedInterfaceMember has "
        "isNoSuchMethodForwarder="
        "${implementedInterfaceMember.isNoSuchMethodForwarder}.");
    return inheritedClassMember.isNoSuchMethodForwarder;
  }

  @override
  int get charOffset => inheritedClassMember.charOffset;

  @override
  Uri get fileUri => inheritedClassMember.fileUri;

  @override
  bool get hasDeclarations => false;

  @override
  bool get isAbstract => false;

  @override
  String get fullNameForErrors => inheritedClassMember.fullNameForErrors;

  @override
  // Coverage-ignore(suite): Not run.
  String get fullName => inheritedClassMember.fullName;

  @override
  String toString() =>
      'InheritedClassMemberImplementsInterface($classBuilder,$name,'
      'inheritedClassMember=$inheritedClassMember,'
      'implementedInterfaceMember=$implementedInterfaceMember,'
      'forSetter=$forSetter)';
}

/// Class member for a set of non-extension type members implemented by an
/// extension type.
///
/// This is used to compute combined member signature of a set of interface
/// members inherited into the same class.
class SynthesizedNonExtensionTypeMember extends SynthesizedMember {
  final ExtensionTypeDeclarationBuilder extensionTypeDeclarationBuilder;

  @override
  final List<ClassMember> declarations;

  Member? _member;
  Covariance? _covariance;

  /// If `true`, a stub should be inserted, if needed.
  final bool _shouldModifyKernel;

  SynthesizedNonExtensionTypeMember(
      this.extensionTypeDeclarationBuilder, Name name, this.declarations,
      {required ClassMemberKind memberKind, required bool shouldModifyKernel})
      : this._shouldModifyKernel = shouldModifyKernel,
        super(name, memberKind);

  @override
  DeclarationBuilder get declarationBuilder => extensionTypeDeclarationBuilder;

  @override
  // Coverage-ignore(suite): Not run.
  bool get hasDeclarations => true;

  void _ensureMemberAndCovariance(ClassMembersBuilder membersBuilder) {
    if (_member != null) {
      return;
    }
    CombinedExtensionTypeMemberSignature combinedMemberSignature =
        new CombinedExtensionTypeMemberSignature(
            membersBuilder, extensionTypeDeclarationBuilder, declarations,
            forSetter: isSetter);

    if (combinedMemberSignature.canonicalMember == null) {
      String name = extensionTypeDeclarationBuilder.fullNameForErrors;
      int nameLength = name.length;
      List<LocatedMessage> context = declarations.map((ClassMember d) {
        return messageDeclaredMemberConflictsWithInheritedMembersCause
            .withLocation(d.fileUri, d.charOffset, d.fullNameForErrors.length);
      }).toList();

      extensionTypeDeclarationBuilder.addProblem(
          templateExtensionTypeCombinedMemberSignatureFailed.withArguments(
              name, declarations.first.fullNameForErrors),
          extensionTypeDeclarationBuilder.fileOffset,
          nameLength,
          context: context);
      // TODO(johnniwinther): Maybe we should have an invalid marker to avoid
      // cascading errors.
      _member = declarations.first.getMember(membersBuilder);
      _covariance = declarations.first.getCovariance(membersBuilder);
      return;
    }

    if (_shouldModifyKernel) {
      SourceExtensionTypeDeclarationBuilder
          sourceExtensionTypeDeclarationBuilder =
          extensionTypeDeclarationBuilder
              as SourceExtensionTypeDeclarationBuilder;
      SourceLibraryBuilder libraryBuilder =
          sourceExtensionTypeDeclarationBuilder.libraryBuilder;
      ExtensionTypeDeclaration extensionTypeDeclaration =
          sourceExtensionTypeDeclarationBuilder.extensionTypeDeclaration;
      ProcedureKind kind = ProcedureKind.Method;
      Member canonicalMember =
          combinedMemberSignature.canonicalMember!.getMember(membersBuilder);
      if (combinedMemberSignature.canonicalMember!.isProperty) {
        kind = isSetter ? ProcedureKind.Setter : ProcedureKind.Getter;
      } else if (canonicalMember is Procedure &&
          canonicalMember.kind == ProcedureKind.Operator) {
        kind = ProcedureKind.Operator;
      }

      Procedure? stub = new ForwardingNode(
              libraryBuilder,
              sourceExtensionTypeDeclarationBuilder,
              extensionTypeDeclaration,
              sourceExtensionTypeDeclarationBuilder.indexedContainer,
              combinedMemberSignature,
              kind,
              declarationIsMixinApplication: false)
          .finalize();
      if (stub != null) {
        assert(
            extensionTypeDeclaration == stub.enclosingExtensionTypeDeclaration);
        assert(stub != canonicalMember);
        extensionTypeDeclaration.addProcedure(stub);
        if (canonicalMember is Procedure) {
          libraryBuilder.forwardersOrigins
            ..add(stub)
            ..add(canonicalMember);
        }
        _member = stub;
        _covariance = combinedMemberSignature.combinedMemberSignatureCovariance;
        assert(
            _covariance ==
                new Covariance.fromMember(_member!, forSetter: forSetter),
            "Unexpected covariance for combined members signature "
            "$_member. Found $_covariance, expected "
            "${new Covariance.fromMember(_member!, forSetter: forSetter)}.");
        return;
      }
    }

    _member =
        combinedMemberSignature.canonicalMember!.getMember(membersBuilder);
    _covariance = combinedMemberSignature.combinedMemberSignatureCovariance;
  }

  @override
  Member getMember(ClassMembersBuilder membersBuilder) {
    _ensureMemberAndCovariance(membersBuilder);
    return _member!;
  }

  @override
  Covariance getCovariance(ClassMembersBuilder membersBuilder) {
    _ensureMemberAndCovariance(membersBuilder);
    return _covariance!;
  }

  @override
  // Coverage-ignore(suite): Not run.
  ClassMember get interfaceMember => this;

  @override
  // Coverage-ignore(suite): Not run.
  bool isObjectMember(ClassBuilder objectClass) {
    return false;
  }

  @override
  // Coverage-ignore(suite): Not run.
  bool isSameDeclaration(ClassMember other) {
    // TODO(johnniwinther): Optimize this.
    return false;
  }

  @override
  // Coverage-ignore(suite): Not run.
  bool get isNoSuchMethodForwarder => false;

  @override
  // Coverage-ignore(suite): Not run.
  int get charOffset => declarations.first.charOffset;

  @override
  // Coverage-ignore(suite): Not run.
  Uri get fileUri => declarations.first.fileUri;

  @override
  // Coverage-ignore(suite): Not run.
  bool get isAbstract => true;

  @override
  // Coverage-ignore(suite): Not run.
  String get fullNameForErrors =>
      declarations.map((ClassMember m) => m.fullName).join("%");

  @override
  // Coverage-ignore(suite): Not run.
  String get fullName {
    String suffix = isSetter ? "=" : "";
    return "${fullNameForErrors}$suffix";
  }

  @override
  String toString() =>
      'SynthesizedNonExtensionTypeMember($declarationBuilder,$name,'
      '$declarations,forSetter=$forSetter)';
}

/// Helper method for [MemberResult]s that determines whether [memberBuilder] is
/// known to be declared as a field. If [forSetter] is `true`, this determined
/// for the setter aspect of the builder, otherwise for the getter aspect.
///
/// This is used for messages related to [MemberResult]s.
bool isDeclaredAsField(MemberBuilder memberBuilder, {required bool forSetter}) {
  if (forSetter) {
    return memberBuilder is PropertyBuilder &&
        memberBuilder.hasField &&
        (memberBuilder.setterQuality == SetterQuality.Implicit ||
            // Coverage-ignore(suite): Not run.
            memberBuilder.setterQuality == SetterQuality.ImplicitExternal ||
            // Coverage-ignore(suite): Not run.
            memberBuilder.setterQuality == SetterQuality.ImplicitAbstract);
  } else {
    return memberBuilder is PropertyBuilder && memberBuilder.hasField;
  }
}
