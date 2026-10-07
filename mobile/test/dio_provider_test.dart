import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:driver_shift_diary/api/dio_provider.dart';
import 'package:driver_shift_diary/config.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('HTTP client uses the compile-time API address', () {
    final container = ProviderContainer.test();

    expect(container.read(dioProvider).options.baseUrl, apiBaseUrl);
  });

  test('API address can be overridden for a target device', () {
    final container = ProviderContainer.test(
      overrides: [apiBaseUrlProvider.overrideWithValue('http://10.0.2.2:8000')],
    );

    expect(container.read(dioProvider).options.baseUrl, 'http://10.0.2.2:8000');
  });

  test('HTTP client can be replaced without making a network request', () {
    final replacement = Dio();
    addTearDown(replacement.close);
    final container = ProviderContainer.test(
      overrides: [dioProvider.overrideWithValue(replacement)],
    );

    expect(container.read(dioProvider), same(replacement));
  });

  test('disposing the provider container closes the HTTP adapter', () {
    final container = ProviderContainer();
    final adapter = _CloseTrackingAdapter();
    container.read(dioProvider).httpClientAdapter = adapter;

    container.dispose();

    expect(adapter.closed, isTrue);
  });
}

class _CloseTrackingAdapter implements HttpClientAdapter {
  bool closed = false;

  @override
  void close({bool force = false}) => closed = true;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => throw StateError('A foundation test must not make network requests.');
}
