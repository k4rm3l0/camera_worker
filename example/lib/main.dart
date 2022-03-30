import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:camera_worker/camera_worker.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const Scaffold(body: MyHomePage()),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key}) : super(key: key);

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final controller = WorkerController<Luminances>(_workerMethod);
  final ValueNotifier<ui.Image?> image = ValueNotifier(null);

  @override
  void initState() {
    controller.init(resolution: ResolutionPreset.high).then((_) {
      setState(() {});
    });
    super.initState();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _buttonPressed() async {
    if (controller.started) {
      return controller.stop();
    } else {
      final stream = await controller.start(maxWidth: 800);
      bool skip = false;
      stream.listen((e) {
        if (skip) return;
        skip = true;
        final luminances = e;
        if (luminances != null) {
          controller.makeImage(luminances).then((value) {
            image.value = value;
            skip = false;
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final camera = controller.camera;
    return Scaffold(
      body: Stack(
        children: [
          camera == null ? const SizedBox.shrink() : CameraPreview(camera),
          ValueListenableBuilder<ui.Image?>(
            valueListenable: image,
            builder: (context, image, _) {
              if (image == null) {
                return const SizedBox.shrink();
              }
              return Transform.scale(
                scale: 0.5,
                alignment: Alignment.bottomLeft,
                child: RawImage(
                  image: image,
                  width: image.width.toDouble(),
                  height: image.height.toDouble(),
                  colorBlendMode: BlendMode.src,
                  alignment: Alignment.bottomLeft,
                ),
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _buttonPressed(),
        child: const Icon(Icons.camera),
      ),
    );
  }
}

Luminances _workerMethod(Luminances lumi) {
  // Perform heavy processing such as image recognition
  return lumi;
}
