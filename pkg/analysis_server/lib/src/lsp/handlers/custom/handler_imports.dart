// Copyright (c) 2019, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analysis_server/lsp_protocol/protocol.dart' hide Element;
import 'package:analysis_server/src/lsp/constants.dart';
import 'package:analysis_server/src/lsp/handlers/custom/abstract_go_to.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';

class ImportsHandler extends AbstractGoToHandler {
  ImportsHandler(super.server);

  @override
  Method get handlesMessage => CustomMethods.super_;

  @override
  bool get requiresTrustedCaller => false;

  @override
  List<Element> findRelatedElements(Element element, CompilationUnit unit) {
    var imports = [
      ...unit.directives
          .whereType<ImportDirective>()
          .map((d) => d.element)
          .nonNulls
    ];
    var elements = <Element>[];
    for (var import in imports) {
      var prefix = import.prefix?.element.name ?? '';
      if (import.namespace.getPrefixed(prefix, element.name ?? '') != null) {
        elements.add(import);
      }
    }
    return elements;
  }
}
