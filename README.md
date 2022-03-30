# camera_worker

[![pub package](https://img.shields.io/pub/v/camera_worker.svg)](https://pub.dartlang.org/packages/camera_worker)


**[English](https://github.com/zuvola/camera_worker/blob/master/README.md), [日本語](https://github.com/zuvola/camera_worker/blob/master/README_jp.md)**


`camera_worker` is a library that converts streaming images from a camera to luminance information for easy processing, and supports parallel processing by Isolate.


## Getting started

Prepare a function to process the brightness information of each frame.  
It should be a top class function or a static method because it will be processed by Isolate so that it can handle heavy processing such as image recognition.  
The return value type is free.

```dart
String _workerMethod(Luminances lumi) {
  /// Do image processing, etc.
  return 'abc';
}
```

Create a `WorkerController` with the methods prepared above.

```dart
final controller = WorkerController<String>(_workerMethod);
```

Initialize and destroy the `WorkerController` with `init`/`dispose`.

```dart
@override
void initState() {
  controller.init().then((_) {
    ///
  });
  super.initState();
}

@override
void dispose() {
  controller.dispose();
  super.dispose();
}
```

Streaming will be started with `start`.
The value received will be the return value of the method specified when creating the `WorkerController`.
If `maxWidth` is specified, the image will be scaled down while maintaining the aspect ratio.

```dart
final stream = await controller.start(maxWidth: 800);
stream.listen((e) {
  print(e);
});
```
