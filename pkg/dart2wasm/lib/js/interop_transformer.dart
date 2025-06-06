// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:_js_interop_checks/src/transformations/js_util_optimizer.dart'
    show ExtensionIndex;
import 'package:kernel/ast.dart';
import 'package:kernel/class_hierarchy.dart';
import 'package:kernel/core_types.dart';
import 'package:kernel/type_environment.dart';

import 'callback_specializer.dart';
import 'inline_expander.dart';
import 'interop_specializer.dart';
import 'method_collector.dart';
import 'util.dart';

/// Lowers static interop to JS, generating specialized JS methods as required.
/// We lower methods to JS, but wait to emit the runtime until after we complete
/// translation. Ideally, we'd do everything after translation, but
/// unfortunately the TFA assumes classes with external factory constructors
/// that aren't mark with `entry-point` are abstract, and their methods thus get
/// replaced with `throw`s. Since we have to lower factory methods anyways, we
/// go ahead and lower everything, let the TFA tree shake, and then emit JS only
/// for the remaining nodes. We can revisit this if it becomes a performance
/// issue.
/// TODO(joshualitt): Only support JS types in static interop APIs, then
/// simpify this code significantly and clean up the nullabilities.
class InteropTransformer extends Transformer {
  final StatefulStaticTypeContext _staticTypeContext;
  final CallbackSpecializer _callbackSpecializer;
  final InlineExpander _inlineExpander;
  final InteropSpecializerFactory _interopSpecializerFactory;
  final MethodCollector _methodCollector;
  final CoreTypesUtil _util;

  InteropTransformer._(this._staticTypeContext, this._util,
      this._methodCollector, extensionIndex)
      : _callbackSpecializer =
            CallbackSpecializer(_staticTypeContext, _util, _methodCollector),
        _inlineExpander =
            InlineExpander(_staticTypeContext, _util, _methodCollector),
        _interopSpecializerFactory = InteropSpecializerFactory(
            _staticTypeContext, _util, _methodCollector, extensionIndex);

  factory InteropTransformer(CoreTypes coreTypes, ClassHierarchy hierarchy) {
    final typeEnvironment = TypeEnvironment(coreTypes, hierarchy);
    final extensionIndex = ExtensionIndex(coreTypes, typeEnvironment);
    final util = CoreTypesUtil(coreTypes, extensionIndex);
    return InteropTransformer._(
        StatefulStaticTypeContext.stacked(typeEnvironment),
        util,
        MethodCollector(util),
        extensionIndex);
  }

  @override
  Library visitLibrary(Library lib) {
    _methodCollector.enterLibrary(lib);
    _staticTypeContext.enterLibrary(lib);
    lib.transformChildren(this);
    _staticTypeContext.leaveLibrary(lib);
    return lib;
  }

  @override
  Member defaultMember(Member node) {
    _staticTypeContext.enterMember(node);
    node.transformChildren(this);
    _staticTypeContext.leaveMember(node);
    return node;
  }

  @override
  Expression visitStaticInvocation(StaticInvocation node) {
    node = super.visitStaticInvocation(node) as StaticInvocation;
    Procedure target = node.target;
    if (target == _util.allowInteropTarget) {
      return _callbackSpecializer.allowInterop(node);
    } else if (target == _util.functionToJSTarget) {
      return _callbackSpecializer.functionToJS(node);
    } else if (target == _util.functionToJSCaptureThisTarget) {
      return _callbackSpecializer.functionToJS(node, captureThis: true);
    } else if (target == _util.inlineJSTarget) {
      return _inlineExpander.expand(node);
    } else {
      return _interopSpecializerFactory.maybeSpecializeInvocation(
              target, node) ??
          node;
    }
  }

  @override
  Procedure visitProcedure(Procedure node) {
    if (!_interopSpecializerFactory.maybeSpecializeProcedure(node)) {
      _staticTypeContext.enterMember(node);
      _inlineExpander.enterProcedure();
      node.transformChildren(this);
      _inlineExpander.exitProcedure(node);
      _staticTypeContext.leaveMember(node);
    }
    return node;
  }

  JSMethods get jsMethods => _methodCollector.jsMethods;
}
