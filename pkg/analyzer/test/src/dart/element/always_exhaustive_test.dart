// Copyright (c) 2023, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analyzer/dart/element/type.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import '../../../generated/type_system_base.dart';

main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(IsAlwaysExhaustiveTest);
  });
}

@reflectiveTest
class IsAlwaysExhaustiveTest extends AbstractTypeSystemTest {
  void isAlwaysExhaustive(DartType type) {
    expect(typeSystem.isAlwaysExhaustive(type), isTrue);
  }

  void isNotAlwaysExhaustive(DartType type) {
    expect(typeSystem.isAlwaysExhaustive(type), isFalse);
  }

  test_class_bool() {
    isAlwaysExhaustive(boolNone);
    isAlwaysExhaustive(boolQuestion);
  }

  test_class_int() {
    isNotAlwaysExhaustive(intNone);
    isNotAlwaysExhaustive(intQuestion);
  }

  test_class_Null() {
    isAlwaysExhaustive(nullNone);
  }

  test_class_sealed() {
    var A = class_2(name: 'A', isSealed: true);
    isAlwaysExhaustive(interfaceTypeNone(A));
    isAlwaysExhaustive(interfaceTypeQuestion2(A));
  }

  test_enum() {
    var E = enum_2(name: 'E', constants: []);
    isAlwaysExhaustive(interfaceTypeNone(E));
    isAlwaysExhaustive(interfaceTypeQuestion2(E));
  }

  test_extensionType() {
    isAlwaysExhaustive(
      interfaceTypeNone(extensionType2('A', representationType: boolNone)),
    );

    isAlwaysExhaustive(
      interfaceTypeNone(extensionType2('A', representationType: boolQuestion)),
    );

    isNotAlwaysExhaustive(
      interfaceTypeNone(extensionType2('A', representationType: intNone)),
    );
  }

  test_futureOr() {
    isAlwaysExhaustive(futureOrNone(boolNone));
    isAlwaysExhaustive(futureOrQuestion(boolNone));

    isAlwaysExhaustive(futureOrNone(boolQuestion));
    isAlwaysExhaustive(futureOrQuestion(boolQuestion));

    isNotAlwaysExhaustive(futureOrNone(intNone));
    isNotAlwaysExhaustive(futureOrQuestion(intNone));
  }

  test_recordType() {
    isAlwaysExhaustive(recordTypeNone(positionalTypes: [boolNone]));

    isAlwaysExhaustive(recordTypeNone(namedTypes: {'f0': boolNone}));

    isNotAlwaysExhaustive(recordTypeNone(positionalTypes: [intNone]));

    isNotAlwaysExhaustive(recordTypeNone(positionalTypes: [boolNone, intNone]));

    isNotAlwaysExhaustive(recordTypeNone(namedTypes: {'f0': intNone}));

    isNotAlwaysExhaustive(
      recordTypeNone(namedTypes: {'f0': boolNone, 'f1': intNone}),
    );
  }

  test_typeParameter() {
    isAlwaysExhaustive(
      typeParameterTypeNone(typeParameter('T', bound: boolNone)),
    );

    isNotAlwaysExhaustive(
      typeParameterTypeNone(typeParameter('T', bound: numNone)),
    );

    isAlwaysExhaustive(
      typeParameterTypeNone(typeParameter('T'), promotedBound: boolNone),
    );

    isNotAlwaysExhaustive(
      typeParameterTypeNone(typeParameter('T'), promotedBound: intNone),
    );
  }
}
