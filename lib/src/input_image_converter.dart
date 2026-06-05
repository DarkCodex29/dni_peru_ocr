import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/painting.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

abstract final class InputImageConverter {
  static InputImage? fromCameraImage(
    CameraImage image,
    CameraDescription camera,
  ) {
    final rotation = _rotationFromSensorOrientation(camera.sensorOrientation);

    if (Platform.isAndroid) {
      return _fromAndroid(image, rotation);
    } else if (Platform.isIOS) {
      return _fromIos(image, rotation);
    }
    return null;
  }

  static InputImage? _fromAndroid(
    CameraImage image,
    InputImageRotation rotation,
  ) {
    final width = image.width;
    final height = image.height;

    // Some Android cameras deliver a pre-interleaved NV21 image as a single plane.
    if (image.planes.length == 1) {
      final plane = image.planes[0];
      return InputImage.fromBytes(
        bytes: plane.bytes,
        metadata: InputImageMetadata(
          size: Size(width.toDouble(), height.toDouble()),
          rotation: rotation,
          format: InputImageFormat.nv21,
          bytesPerRow: plane.bytesPerRow,
        ),
      );
    }

    // YUV_420_888 → NV21 with correct stride handling.
    //
    // yPlane.bytes has length = height * yPlane.bytesPerRow, where bytesPerRow
    // is often LARGER than width (stride padding). Copying the first width*height
    // bytes of the flat buffer produces corrupted row data. Copy row-by-row instead.
    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    final yBytes = yPlane.bytes;
    final uBytes = uPlane.bytes;
    final vBytes = vPlane.bytes;

    final ySize = width * height;
    final uvSize = width * height ~/ 2;
    final nv21 = Uint8List(ySize + uvSize);

    final yRowStride = yPlane.bytesPerRow;
    for (int row = 0; row < height; row++) {
      nv21.setRange(
        row * width,
        (row + 1) * width,
        yBytes,
        row * yRowStride,
      );
    }

    final uvRowStride = uPlane.bytesPerRow;
    final uvPixelStride = uPlane.bytesPerPixel ?? 1;
    int uvIndex = ySize;
    for (int row = 0; row < height ~/ 2; row++) {
      for (int col = 0; col < width ~/ 2; col++) {
        final uvOffset = row * uvRowStride + col * uvPixelStride;
        if (uvIndex + 1 < nv21.length) {
          nv21[uvIndex++] = vBytes[uvOffset];
          nv21[uvIndex++] = uBytes[uvOffset];
        }
      }
    }

    return InputImage.fromBytes(
      bytes: nv21,
      metadata: InputImageMetadata(
        size: Size(width.toDouble(), height.toDouble()),
        rotation: rotation,
        format: InputImageFormat.nv21,
        // The NV21 we generate has stride-free rows (exactly width bytes each).
        bytesPerRow: width,
      ),
    );
  }

  static InputImage? _fromIos(CameraImage image, InputImageRotation rotation) {
    if (image.planes.isEmpty) return null;
    final plane = image.planes[0];
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: InputImageFormat.bgra8888,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  static InputImageRotation _rotationFromSensorOrientation(int orientation) {
    return switch (orientation) {
      90 => InputImageRotation.rotation90deg,
      180 => InputImageRotation.rotation180deg,
      270 => InputImageRotation.rotation270deg,
      _ => InputImageRotation.rotation0deg,
    };
  }
}
