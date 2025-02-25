// Copyright (c) 2022, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analysis_server/src/services/correction/status.dart';
import 'package:analysis_server/src/services/refactoring/legacy/naming_conventions.dart';
import 'package:analysis_server/src/services/refactoring/legacy/refactoring.dart';
import 'package:analysis_server/src/services/refactoring/legacy/rename.dart';
import 'package:analysis_server/src/services/refactoring/legacy/rename_local.dart';
import 'package:analysis_server/src/services/refactoring/legacy/visible_ranges_computer.dart';
import 'package:analysis_server/src/services/search/hierarchy.dart';
import 'package:analyzer/dart/element/element2.dart';
import 'package:analyzer/src/generated/java_core.dart';

/// A [Refactoring] for renaming [FormalParameterElement]s.
class RenameParameterRefactoringImpl extends RenameRefactoringImpl {
  final bool _lookForHierarchy;

  List<FormalParameterElement> elements = [];
  bool _renameAllPositionalOccurences;

  RenameParameterRefactoringImpl(
    super.workspace,
    super.sessionHelper,
    FormalParameterElement super.element, {
    bool renameAllPositionalOccurences = false,
    bool lookForHierarchy = true,
  }) : _lookForHierarchy = lookForHierarchy,
       _renameAllPositionalOccurences = renameAllPositionalOccurences,
       super();

  @override
  FormalParameterElement get element => super.element as FormalParameterElement;

  @override
  String get refactoringName {
    return 'Rename Parameter';
  }

  @override
  Future<RefactoringStatus> checkFinalConditions() async {
    var result = RefactoringStatus();
    await _prepareElements();
    for (var element in elements) {
      if (newName.startsWith('_') && element.isNamed) {
        result.addError(
          format(
            "The parameter '{0}' is named and can not be private.",
            element.name3,
          ),
        );
        break;
      }
      var resolvedUnit = await sessionHelper.getResolvedUnitByElement(element);
      if (resolvedUnit != null) {
        // If any of the resolved units have the lint enabled, we should avoid
        // renaming method parameters separately from the other implementations.
        if (!_renameAllPositionalOccurences) {
          _renameAllPositionalOccurences |=
              getCodeStyleOptions(
                resolvedUnit.file,
              ).avoidRenamingMethodParameters;
        }

        var unit = resolvedUnit.unit;
        unit.accept(
          ConflictValidatorVisitor(
            result,
            newName,
            element,
            VisibleRangesComputer.forNode(unit),
          ),
        );
      }
    }
    return result;
  }

  @override
  RefactoringStatus checkNewName() {
    var result = super.checkNewName();
    result.addStatus(validateParameterName(newName));
    return result;
  }

  @override
  Future<void> fillChange() async {
    var processor = RenameProcessor(workspace, sessionHelper, change, newName);
    for (var element in elements) {
      var fieldRenamed = false;
      if (element is FieldFormalParameterElement2) {
        var field = element.field2;
        if (field != null) {
          await processor.renameElement(field);
          fieldRenamed = true;
        }
      }

      if (!fieldRenamed) {
        processor.addDeclarationEdit(element);
      }
      var references = await searchEngine.searchReferences(element);

      // Remove references that don't have to have the same name.

      // Implicit references to optional positional parameters.
      if (element.isOptionalPositional) {
        references.removeWhere((match) => match.sourceRange.length == 0);
      }
      // References to positional parameters from super-formal.
      if (element.isPositional) {
        references.removeWhere(
          (match) => match.element is SuperFormalParameterElement2,
        );
        var method = element.enclosingElement2;
        if (method is MethodElement2 && _lookForHierarchy) {
          var index = method.parameterIndex(element);
          var methods =
              (await getHierarchyMembers(searchEngine, method))
                  .where((element) => element != method)
                  .whereType<MethodElement2>();
          for (var method in methods) {
            await _renameParametersInMethodOccurences(method, index);
          }
        }
      }

      processor.addReferenceEdits(references);
    }
  }

  /// Fills [elements] with [Element2]s to rename.
  Future<void> _prepareElements() async {
    var element = this.element;
    if (element.isNamed) {
      elements =
          (await getHierarchyNamedParameters(searchEngine, element)).toList();
    } else {
      elements = [element];
    }
  }

  Future<void> _renameParametersInMethodOccurences(
    MethodElement2 method,
    int? index,
  ) async {
    if (index == null) {
      return;
    }
    if (!_renameAllPositionalOccurences) {
      return;
    }
    var parameter = method.formalParameters[index];
    if (parameter.name3 == newName) {
      return;
    }
    var refactorOther = RenameParameterRefactoringImpl(
      workspace,
      sessionHelper,
      parameter,
      renameAllPositionalOccurences: true,
      lookForHierarchy: false,
    );
    refactorOther.newName = newName;
  }
}

extension on MethodElement2 {
  int? parameterIndex(FormalParameterElement parameter) {
    var index = 0;
    for (var p in formalParameters) {
      if (p == parameter) {
        return index;
      }
      index++;
    }
    return null;
  }
}
