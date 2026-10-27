import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:taktooka/widgets/home_banners.dart';

final pixel = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a0xkAAAAASUVORK5CYII=',
);

class ImageClient implements HttpClient {
  @override
  Future<HttpClientRequest> getUrl(Uri url) async => ImageRequest();
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class ImageRequest implements HttpClientRequest {
  @override
  Future<HttpClientResponse> close() async => ImageResponse();
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class ImageResponse extends Stream<List<int>> implements HttpClientResponse {
  @override
  int get statusCode => 200;
  @override
  int get contentLength => pixel.length;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(pixel).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  void imageTest(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      debugNetworkImageHttpClientProvider = () => ImageClient();
      try {
        await body(tester);
      } finally {
        debugNetworkImageHttpClientProvider = null;
        PaintingBinding.instance.imageCache.clear();
      }
    });
  }

  final images = [
    {'image_path': 'first.jpg', 'title': 'First'},
    {'image_path': 'second.jpg', 'title': 'Second'},
  ];
  Widget page(List<Map<String, dynamic>> rows, {bool enabled = true}) =>
      MaterialApp(
        home: Scaffold(
          body: TickerMode(
            enabled: enabled,
            child: BannerCarousel(
              images: rows,
              fallback: const Text('Original artwork'),
            ),
          ),
        ),
      );
  imageTest('empty slot retains original artwork', (tester) async {
    await tester.pumpWidget(page([]));
    expect(find.text('Original artwork'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });
  imageTest(
    'rotates every two seconds despite parent rebuild and pauses hidden routes',
    (tester) async {
      await tester.pumpWidget(page(images));
      expect(find.byKey(const ValueKey('first.jpg')), findsWidgets);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpWidget(page(List.of(images)));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const ValueKey('second.jpg')), findsWidgets);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpWidget(page(images, enabled: false));
      await tester.pump(const Duration(seconds: 5));
      expect(find.byKey(const ValueKey('second.jpg')), findsWidgets);
      await tester.pumpWidget(page(images));
      await tester.pump(const Duration(seconds: 2));
      expect(find.byKey(const ValueKey('first.jpg')), findsWidgets);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
  imageTest('removed image cannot remain selected', (tester) async {
    await tester.pumpWidget(page(images));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpWidget(page([images.first]));
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byKey(const ValueKey('second.jpg')), findsNothing);
    expect(find.byKey(const ValueKey('first.jpg')), findsWidgets);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}
