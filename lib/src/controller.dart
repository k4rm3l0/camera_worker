import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:isoworker/isoworker.dart';
import 'dart:math';

/// Image width, height, and brightness.
@immutable
class Luminances {
  final int width;
  final int height;
  final Int8List luminances;
  final int lux;

  const Luminances(this.width, this.height, this.luminances, this.lux);
}

/// This is a library that converts streaming images from a camera to luminance
/// information for easy processing, and supports parallel processing by Isolate.
class WorkerController<T> {
  final T? Function(Luminances) workerMethod;
  CameraController? camera;
  IsoWorker? _worker;
  StreamController<T?>? _stream;
  List<CameraDescription>? cameras;

  WorkerController(this.workerMethod);

  /// Initializes the camera and worker.
  Future<void> init(
      {ResolutionPreset resolution = ResolutionPreset.veryHigh}) async {
    await initWithCamera(null);
  }

  Future<void> initWithCamera(CameraDescription? selectedCamera, {ResolutionPreset resolution = ResolutionPreset.veryHigh}) async {
    _worker ??= await IsoWorker.init(_workerMethod);
    //if (camera != null) return;
    cameras = await availableCameras();
    if (cameras!.isEmpty) return;
    camera = CameraController(
      selectedCamera ?? cameras!.first,
      resolution,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    await camera?.initialize();
  }

  /// Releases the resources.
  Future<void> dispose() async {
    await _stream?.close();
    await camera?.dispose();
    await _worker?.dispose();
  }

  /// Start streaming images.
  /// If `maxWidth` is specified, the image will be scaled down while maintaining the aspect ratio.
  Future<Stream<T?>> start({int maxWidth = 0}) async {
    bool flg = false;
    await stop();
    _stream = StreamController<T?>();
    const angles = {
      DeviceOrientation.portraitUp: 0,
      DeviceOrientation.landscapeLeft: 90,
      DeviceOrientation.portraitDown: 180,
      DeviceOrientation.landscapeRight: 270,
    };
    await camera?.startImageStream((CameraImage image) {
      if (flg || _worker == null) return;
      flg = true;
      final plane = image.planes.first;
      final int orientation;
      if (Platform.isIOS) {
        orientation = 0;
      } else {
        final angle = angles[camera!.value.deviceOrientation] ?? 0;
        orientation =
            (360 - camera!.description.sensorOrientation + angle) % 360;
      }
      _worker!.exec<T?>({
        'method': workerMethod,
        'bytesPerRow': plane.bytesPerRow,
        'height': image.height,
        'width': image.width,
        'buff': plane.bytes,
        'orientation': orientation,
        'maxWidth': maxWidth,
        'lensAperture' : image.lensAperture,
        'sensorSensitivity' : image.sensorSensitivity,
        'sensorExposureTime' : image.sensorExposureTime
      }).then((res) {
        final st = _stream;
        if (st != null && !st.isClosed) st.sink.add(res);
        flg = false;
      });
    });
    return _stream!.stream;
  }

  /// Stop streaming images.
  Future<void> stop() async {
    if (started) {
      _stream?.close();
      _stream = null;
      return camera?.stopImageStream();
    }
  }

  /// True when images from the camera are being streamed.
  bool get started => camera?.value.isStreamingImages ?? false;

  /// Create an Image from the Luminances class.
  /// It can be used for checking the processing results.
  Future<ui.Image> makeImage(Luminances luminances) {
    final c = Completer<ui.Image>();
    final size = luminances.width * luminances.height;
    final dst = Uint32List(size);
    const a = 0xff << 24;
    final src = luminances.luminances.buffer.asUint8List();
    for (var offset = 0; offset < size; offset++) {
      final pixel = src[offset];
      final r = pixel << 16;
      final g = pixel << 8;
      final b = pixel;
      dst[offset] = a | r | g | b;
    }
    ui.decodeImageFromPixels(
      dst.buffer.asUint8List(),
      luminances.width,
      luminances.height,
      ui.PixelFormat.bgra8888,
      c.complete,
    );
    return c.future;
  }
}

/// The worker method used from Isolate.
void _workerMethod(Stream<WorkerData> message) {
  void _rotate(int orientation, int width, int height, int bytesPerRow,
      Uint8List src, Function(int w, int h, Uint8List pixels) callback) {
    final int w, h;
    if (orientation == 0 || orientation == 180) {
      w = width;
      h = height;
    } else if (orientation == 90 || orientation == 270) {
      w = height;
      h = width;
    } else {
      throw ArgumentError();
    }
    final dst = Uint8List(src.length);
    for (int y = 0; y < h; y++) {
      final wy = w * y;
      for (int x = 0; x < w; x++) {
        if (orientation == 0) {
          dst[wy + x] = src[y * bytesPerRow + x];
        } else if (orientation == 90) {
          dst[wy + x] = src[x * bytesPerRow + (width - y - 1)];
        } else if (orientation == 180) {
          dst[wy + x] = src[(h - y - 1) * bytesPerRow + (w - x - 1)];
        } else {
          dst[wy + x] = src[(height - 1 - x) * bytesPerRow + y];
        }
      }
    }
    callback(w, h, dst);
  }

  void _scale(int width, int height, int maxWidth, List<int> src,
      Function(int w, int h, List<int> pixels) callback) {
    if (maxWidth > 0 && width > maxWidth) {
      final scale = width / maxWidth;
      final h = height ~/ scale;
      final dst = List.filled(maxWidth * h, 0);
      for (int y = 0; y < h; y++) {
        final wy = y * maxWidth;
        final oy = (y * scale).truncate() * width;
        for (int x = 0; x < maxWidth; x++) {
          dst[wy + x] = src[oy + (x * scale).truncate()];
        }
      }
      callback(maxWidth, h, dst);
    } else {
      callback(width, height, src);
    }
  }

  message.listen((data) {
    try {
      final method = data.value['method'] as Function;
      final bytesPerRow = data.value['bytesPerRow'] as int;
      final height = data.value['height'] as int;
      final width = data.value['width'] as int;
      final buff = data.value['buff'] as Uint8List;
      final orientation = data.value['orientation'] as int;
      final maxWidth = data.value['maxWidth'] as int;
      final lensAperture = data.value['lensAperture'] as double;
      final sensorSensitivity = data.value['sensorSensitivity'] as double;
      final sensorExposureTime = data.value['sensorExposureTime'] as int;

      double luxValue = (45 * lensAperture * lensAperture) / ((sensorExposureTime/1000000000) * sensorSensitivity);

      luxValue -= 14;

      if(luxValue<0){
        luxValue = 0;
      }

      _rotate(orientation, width, height, bytesPerRow, buff, (w, h, pixels) {
        _scale(w, h, maxWidth, pixels, (w, h, pixels) {
          final res = method.call(Luminances(w, h, Int8List.fromList(pixels), luxValue.toInt()));
          data.callback(res);
        });
      });
    } catch (_) {
      data.callback(null);
    }
  });
}
