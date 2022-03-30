# camera_worker

[![pub package](https://img.shields.io/pub/v/camera_worker.svg)](https://pub.dartlang.org/packages/camera_worker)


**[English](https://github.com/zuvola/camera_worker/blob/master/README.md), [日本語](https://github.com/zuvola/camera_worker/blob/master/README_jp.md)**


`camera_worker`はカメラからのストリーミング画像を処理しやすい輝度情報へ変換しIsolateで並列処理を行う事をサポートするライブラリです。


## Getting started

各フレームの輝度情報が処理する関数を用意します。
画像認識のような重い処理でも大丈夫なようにIsolateで処理されるのでトップクラス関数かStaticメソッドにしてください。
返り値は自由です。

```dart
String _workerMethod(Luminances lumi) {
  /// 画像処理などを行う
  return 'abc';
}
```

上記で用意したメソッドを指定して`WorkerController`を作成します。

```dart
final controller = WorkerController<String>(_workerMethod);
```

`init`/`dispose`で`WorkerController`の初期化と破棄を行います。

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

`start`でストリーミングが開始されます。
受け取る値は`WorkerController`作成時に指定したメソッドの返り値になります。
`maxWidth`を指定するとアスペクト比を維持したまま画像の縮小が行われます。

```dart
final stream = await controller.start(maxWidth: 800);
stream.listen((e) {
  print(e);
});
```
