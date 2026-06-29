import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Dependency currency (PR1 isolated deps gate)', () {
    late String pubspec;
    late String examplePubspec;

    setUpAll(() {
      pubspec = File('pubspec.yaml').readAsStringSync();
      examplePubspec = File('example/pubspec.yaml').readAsStringSync();
    });

    String constraintFor(String content, String dependency) {
      final pattern = RegExp('^  $dependency:\\s*(.+)\$', multiLine: true);
      final match = pattern.firstMatch(content);
      expect(
        match,
        isNotNull,
        reason: 'Expected a direct constraint for "$dependency".',
      );
      return match!.group(1)!.trim();
    }

    test('camera is upgraded to the 0.12.x line', () {
      expect(constraintFor(pubspec, 'camera'), '^0.12.0+1');
      expect(constraintFor(examplePubspec, 'camera'), '^0.12.0+1');
    });

    test('path_provider is upgraded to 2.1.6', () {
      expect(constraintFor(pubspec, 'path_provider'), '^2.1.6');
    });

    test('sensors_plus is upgraded to 7.1.0', () {
      expect(constraintFor(pubspec, 'sensors_plus'), '^7.1.0');
    });

    test('flutter_lints dev dependency is upgraded to 6.0.0', () {
      expect(constraintFor(pubspec, 'flutter_lints'), '^6.0.0');
      expect(constraintFor(examplePubspec, 'flutter_lints'), '^6.0.0');
    });
  });
}
