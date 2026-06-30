import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('opencv_dart integration (PR2 dependency + floor + version)', () {
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

    String fieldFor(String content, String field) {
      final pattern = RegExp('^$field:\\s*(.+)\$', multiLine: true);
      final match = pattern.firstMatch(content);
      expect(match, isNotNull, reason: 'Expected a "$field" line.');
      return match!.group(1)!.trim();
    }

    test('opencv_dart is pinned to the published 2.2.1+4', () {
      expect(constraintFor(pubspec, 'opencv_dart'), '^2.2.1+4');
    });

    test('library version is at the 1.x MAJOR or higher', () {
      final version = fieldFor(pubspec, 'version');
      final major = int.parse(version.split('.').first);
      expect(major, greaterThanOrEqualTo(1),
          reason: 'opencv_dart landed in the 1.0.0 MAJOR; version must stay >=1.x.');
    });

    test('SDK floor is raised to Dart >=3.10 for opencv_dart 2.x hooks', () {
      expect(constraintFor(pubspec, 'sdk'), "'>=3.10.0 <4.0.0'");
      expect(constraintFor(examplePubspec, 'sdk'), "'>=3.10.0 <4.0.0'");
    });

    test('Flutter floor is raised to >=3.38.0 for opencv_dart 2.x', () {
      expect(constraintFor(pubspec, 'flutter'), "'>=3.38.0'");
      expect(constraintFor(examplePubspec, 'flutter'), "'>=3.38.0'");
    });

    test('dartcv4 module trim restricts native modules to quad-detection needs',
        () {
      expect(
        pubspec,
        contains('hooks:'),
        reason: 'Expected a hooks block to configure the dartcv4 module trim.',
      );
      expect(
        pubspec,
        contains('include_modules:'),
        reason: 'Expected include_modules to trim the OpenCV native binary.',
      );
      for (final module in const ['core', 'imgproc', 'imgcodecs']) {
        expect(
          pubspec,
          contains('- $module'),
          reason: 'Expected module "$module" in the dartcv4 include_modules '
              'trim (perspective ops live in imgproc; no calib3d).',
        );
      }
      expect(
        pubspec.contains('- calib3d'),
        isFalse,
        reason: 'calib3d must NOT be included — quad detection does not need it.',
      );
    });
  });
}
