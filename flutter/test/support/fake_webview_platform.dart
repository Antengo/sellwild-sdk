// Fake webview_flutter platform for flutter_test.
//
// WebViewController() asserts when WebViewPlatform.instance is null, which it
// always is under flutter_test (no native plugin registers). Install this fake
// in setUp, pump the widget, then drive the captured JS channels and navigation
// callbacks directly:
//
//   late FakeWebViewPlatform webviews;
//   setUp(() => webviews = FakeWebViewPlatform.install());
//
//   await tester.pumpWidget(MaterialApp(home: SellwildWidget(config: cfg)));
//   webviews.lastController.postJson('SellwildWidgetBridge', {'type': 'WIDGET_LOADED'});
//   webviews.lastController.navigationDelegate!.emitWebResourceError(...);
//
// Nothing here loads a page or touches the network. Methods the SDK does not
// call keep the platform interface's UnimplementedError, so a new call site
// fails loudly until the fake learns it.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

class FakeWebViewPlatform extends WebViewPlatform {
  /// Sets a fresh fake as [WebViewPlatform.instance] and returns it.
  /// The instance setter rejects null, so each test installs its own.
  static FakeWebViewPlatform install() {
    final platform = FakeWebViewPlatform();
    WebViewPlatform.instance = platform;
    return platform;
  }

  final List<FakeWebViewController> controllers = [];
  final List<FakeNavigationDelegate> navigationDelegates = [];
  final List<FakeWebViewWidget> widgets = [];

  /// When set, every controller's loadHtmlString/loadRequest completes with
  /// this error instead of recording a load. Lets tests reach load-failure
  /// paths without a real WebView.
  Object? loadError;

  FakeWebViewController get lastController {
    if (controllers.isEmpty) {
      throw StateError(
          'No WebViewController was created on the fake platform.');
    }
    return controllers.last;
  }

  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    final controller = FakeWebViewController(params, this);
    controllers.add(controller);
    return controller;
  }

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) {
    final delegate = FakeNavigationDelegate(params);
    navigationDelegates.add(delegate);
    return delegate;
  }

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) {
    final widget = FakeWebViewWidget(params);
    widgets.add(widget);
    return widget;
  }
}

/// One loadHtmlString call.
class LoadedHtml {
  const LoadedHtml(this.html, this.baseUrl);

  final String html;
  final String? baseUrl;
}

class FakeWebViewController extends PlatformWebViewController {
  FakeWebViewController(super.params, this._platform) : super.implementation();

  final FakeWebViewPlatform _platform;

  final Map<String, JavaScriptChannelParams> channels = {};
  final List<LoadedHtml> loadedHtml = [];
  final List<LoadRequestParams> loadedRequests = [];
  final List<String> ranJavaScript = [];
  JavaScriptMode? javaScriptMode;
  Color? backgroundColor;
  String? userAgent;
  FakeNavigationDelegate? navigationDelegate;
  void Function(JavaScriptConsoleMessage message)? onConsoleMessage;

  /// Last HTML passed to loadHtmlString.
  LoadedHtml get lastHtml {
    if (loadedHtml.isEmpty) {
      throw StateError('loadHtmlString was never called on this controller.');
    }
    return loadedHtml.last;
  }

  /// Delivers [message] to the named JS channel, as the page's
  /// `<channel>.postMessage(message)` would. Throws if the channel was never
  /// added, so a renamed channel cannot pass silently.
  void postMessage(String channel, String message) {
    final params = channels[channel];
    if (params == null) {
      throw StateError(
        'No JavaScript channel "$channel". Registered: ${channels.keys.toList()}',
      );
    }
    params.onMessageReceived(JavaScriptMessage(message: message));
  }

  /// [postMessage] with a JSON-encoded body.
  void postJson(String channel, Object? message) =>
      postMessage(channel, jsonEncode(message));

  @override
  Future<void> loadHtmlString(String html, {String? baseUrl}) async {
    _throwIfLoadFails();
    loadedHtml.add(LoadedHtml(html, baseUrl));
  }

  @override
  Future<void> loadRequest(LoadRequestParams params) async {
    _throwIfLoadFails();
    loadedRequests.add(params);
  }

  void _throwIfLoadFails() {
    final error = _platform.loadError;
    if (error != null) throw error;
  }

  @override
  Future<void> addJavaScriptChannel(JavaScriptChannelParams params) async {
    channels[params.name] = params;
  }

  @override
  Future<void> removeJavaScriptChannel(String javaScriptChannelName) async {
    channels.remove(javaScriptChannelName);
  }

  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) async {
    this.javaScriptMode = javaScriptMode;
  }

  @override
  Future<void> setBackgroundColor(Color color) async {
    backgroundColor = color;
  }

  @override
  Future<void> setUserAgent(String? userAgent) async {
    this.userAgent = userAgent;
  }

  @override
  Future<String?> getUserAgent() async => userAgent;

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {
    navigationDelegate = handler as FakeNavigationDelegate;
  }

  @override
  Future<void> runJavaScript(String javaScript) async {
    ranJavaScript.add(javaScript);
  }

  @override
  Future<void> setOnConsoleMessage(
    void Function(JavaScriptConsoleMessage consoleMessage) onConsoleMessage,
  ) async {
    this.onConsoleMessage = onConsoleMessage;
  }

  @override
  Future<String?> currentUrl() async => loadedRequests.isEmpty
      ? (loadedHtml.isEmpty ? null : loadedHtml.last.baseUrl)
      : loadedRequests.last.uri.toString();

  @override
  Future<void> reload() async {}
}

class FakeNavigationDelegate extends PlatformNavigationDelegate {
  FakeNavigationDelegate(super.params) : super.implementation();

  NavigationRequestCallback? onNavigationRequest;
  PageEventCallback? onPageStarted;
  PageEventCallback? onPageFinished;
  ProgressCallback? onProgress;
  WebResourceErrorCallback? onWebResourceError;
  HttpResponseErrorCallback? onHttpError;
  UrlChangeCallback? onUrlChange;

  @override
  Future<void> setOnNavigationRequest(
      NavigationRequestCallback callback) async {
    onNavigationRequest = callback;
  }

  @override
  Future<void> setOnPageStarted(PageEventCallback callback) async {
    onPageStarted = callback;
  }

  @override
  Future<void> setOnPageFinished(PageEventCallback callback) async {
    onPageFinished = callback;
  }

  @override
  Future<void> setOnProgress(ProgressCallback callback) async {
    onProgress = callback;
  }

  @override
  Future<void> setOnWebResourceError(WebResourceErrorCallback callback) async {
    onWebResourceError = callback;
  }

  @override
  Future<void> setOnHttpError(HttpResponseErrorCallback callback) async {
    onHttpError = callback;
  }

  @override
  Future<void> setOnUrlChange(UrlChangeCallback callback) async {
    onUrlChange = callback;
  }

  // The emit* helpers throw when the SDK never registered the callback, so a
  // test cannot "fire" an event the code under test does not listen to.

  void emitPageStarted(String url) =>
      _require(onPageStarted, 'onPageStarted')(url);

  void emitPageFinished(String url) =>
      _require(onPageFinished, 'onPageFinished')(url);

  void emitProgress(int progress) =>
      _require(onProgress, 'onProgress')(progress);

  void emitWebResourceError(WebResourceError error) =>
      _require(onWebResourceError, 'onWebResourceError')(error);

  void emitHttpError(HttpResponseError error) =>
      _require(onHttpError, 'onHttpError')(error);

  FutureOr<NavigationDecision> requestNavigation(
    String url, {
    bool isMainFrame = true,
  }) =>
      _require(onNavigationRequest, 'onNavigationRequest')(
        NavigationRequest(url: url, isMainFrame: isMainFrame),
      );

  T _require<T>(T? callback, String name) {
    if (callback == null) {
      throw StateError('The code under test never set $name.');
    }
    return callback;
  }
}

class FakeWebViewWidget extends PlatformWebViewWidget {
  FakeWebViewWidget(super.params) : super.implementation();

  static const Key widgetKey = ValueKey<String>('fake-webview');

  @override
  Widget build(BuildContext context) => const SizedBox.expand(key: widgetKey);
}
