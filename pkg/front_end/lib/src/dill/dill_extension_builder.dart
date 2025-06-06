// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:kernel/ast.dart';

import '../base/name_space.dart';
import '../builder/declaration_builders.dart';
import '../builder/type_builder.dart';
import 'dill_builder_mixins.dart';
import 'dill_class_builder.dart';
import 'dill_extension_member_builder.dart';
import 'dill_library_builder.dart';

class DillExtensionBuilder extends ExtensionBuilderImpl
    with DillDeclarationBuilderMixin {
  @override
  final DillLibraryBuilder libraryBuilder;

  @override
  final Extension extension;

  final DeclarationNameSpace _nameSpace;

  List<NominalParameterBuilder>? _typeParameters;
  TypeBuilder? _onType;

  DillExtensionBuilder(this.extension, this.libraryBuilder)
      : _nameSpace = new DeclarationNameSpaceImpl() {
    for (ExtensionMemberDescriptor descriptor in extension.memberDescriptors) {
      Name name = descriptor.name;
      switch (descriptor.kind) {
        case ExtensionMemberKind.Method:
          if (descriptor.isStatic) {
            Procedure procedure = descriptor.memberReference!.asProcedure;
            _nameSpace.addLocalMember(
                name.text,
                new DillExtensionStaticMethodBuilder(
                    procedure, descriptor, libraryBuilder, this),
                setter: false);
          } else {
            Procedure procedure = descriptor.memberReference!.asProcedure;
            Procedure? tearOff = descriptor.tearOffReference?.asProcedure;
            assert(tearOff != null, "No tear found for ${descriptor}");
            _nameSpace.addLocalMember(
                name.text,
                new DillExtensionInstanceMethodBuilder(
                    procedure, descriptor, libraryBuilder, this, tearOff!),
                setter: false);
          }
          break;
        case ExtensionMemberKind.Getter:
          Procedure procedure = descriptor.memberReference!.asProcedure;
          _nameSpace.addLocalMember(
              name.text,
              new DillExtensionGetterBuilder(
                  procedure, descriptor, libraryBuilder, this),
              setter: false);
          break;
        case ExtensionMemberKind.Field:
          Field field = descriptor.memberReference!.asField;
          _nameSpace.addLocalMember(
              name.text,
              new DillExtensionFieldBuilder(
                  field, descriptor, libraryBuilder, this),
              setter: false);
          break;
        case ExtensionMemberKind.Setter:
          Procedure procedure = descriptor.memberReference!.asProcedure;
          _nameSpace.addLocalMember(
              name.text,
              new DillExtensionSetterBuilder(
                  procedure, descriptor, libraryBuilder, this),
              setter: true);
          break;
        case ExtensionMemberKind.Operator:
          Procedure procedure = descriptor.memberReference!.asProcedure;
          _nameSpace.addLocalMember(
              name.text,
              new DillExtensionOperatorBuilder(
                  procedure, descriptor, libraryBuilder, this),
              setter: false);
          break;
      }
    }
  }

  @override
  DillLibraryBuilder get parent => libraryBuilder;

  @override
  Reference get reference => extension.reference;

  @override
  int get fileOffset => extension.fileOffset;

  @override
  String get name => extension.name;

  @override
  Uri get fileUri => extension.fileUri;

  @override
  DeclarationNameSpace get nameSpace => _nameSpace;

  @override
  List<NominalParameterBuilder>? get typeParameters {
    if (_typeParameters == null && extension.typeParameters.isNotEmpty) {
      _typeParameters = computeTypeParameterBuilders(
          extension.typeParameters, libraryBuilder.loader);
    }
    return _typeParameters;
  }

  @override
  // Coverage-ignore(suite): Not run.
  TypeBuilder get onType {
    return _onType ??=
        libraryBuilder.loader.computeTypeBuilder(extension.onType);
  }

  @override
  // Coverage-ignore(suite): Not run.
  List<TypeParameter> get typeParameterNodes => extension.typeParameters;
}
