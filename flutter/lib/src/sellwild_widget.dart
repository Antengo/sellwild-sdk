// Deprecated WebView surfaces: SellwildWidget (the full marketplace widget)
// and SellwildBanner. No feature work (native-first-mobile); only failure
// reporting. The HTML they load and the messages they decode are pure
// functions in widget_html.dart and widget_bridge.dart; these states are the
// thin shells that talk to the WebView, call the host and report failures
// once through logFailure.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'failures/sellwild_failure_code.dart';
import 'failures/sellwild_failures.dart';
import 'failures/sellwild_log.dart';
import 'sellwild_config.dart';
import 'sellwild_models.dart';
import 'widget_bridge.dart';
import 'widget_html.dart';

/// Full Sellwild marketplace widget rendered in a WebView.
///
/// Example:
/// ```dart
/// SellwildWidget(
///   config: SellwildConfig(
///     partnerCode: 'mysite',
///     listingsUrl: 'https://cache.sellwild.com/listings-img-data-sm',
///   ),
///   onListingTap: (listing) {
///     // Navigate to listing detail
///   },
/// )
/// ```
class SellwildWidget extends StatefulWidget {
  final SellwildConfig config;
  final void Function(SellwildListing listing)? onListingTap;
  final void Function(String zoneId)? onAdImpression;
  final void Function(Object error)? onError;
  final void Function()? onLoad;

  const SellwildWidget({
    super.key,
    required this.config,
    this.onListingTap,
    this.onAdImpression,
    this.onError,
    this.onLoad,
  });

  @override
  State<SellwildWidget> createState() => _SellwildWidgetState();
}

class _SellwildWidgetState extends State<SellwildWidget> {
  late final WebViewController _controller;
  bool _loading = true;

  /// Reports widget.load.timeout when no WIDGET_LOADED arrives within
  /// [widgetLoadedDeadline] (the spinner would never end). Failure
  /// reporting only: the spinner and the host see no change. Cancelled by
  /// WIDGET_LOADED, by a failure already reported for the page itself
  /// (setup or page load, so one failure is reported once) and by dispose.
  Timer? _loadWatchdog;

  @override
  void initState() {
    super.initState();
    _loadWatchdog = Timer(widgetLoadedDeadline, _reportLoadTimeout);
    final controller = _controller = WebViewController();
    _reportSetupFailure(
        SellwildFailureComponent.webview,
        [
          controller.setJavaScriptMode(JavaScriptMode.unrestricted),
          controller.setBackgroundColor(Colors.transparent),
          controller.addJavaScriptChannel(
            'SellwildWidgetBridge',
            onMessageReceived: (message) => _handleMessage(message.message),
          ),
          controller.setNavigationDelegate(NavigationDelegate(
            onPageFinished: (_) {
              // Widget sends WIDGET_LOADED via JS channel
            },
            onWebResourceError: _handleLoadError,
          )),
          controller.loadHtmlString(buildWidgetHtml(widget.config),
              baseUrl: widgetPageBaseUrl),
        ],
        onReported: _cancelLoadWatchdog);
  }

  @override
  void dispose() {
    _cancelLoadWatchdog();
    super.dispose();
  }

  void _cancelLoadWatchdog() {
    _loadWatchdog?.cancel();
    _loadWatchdog = null;
  }

  void _reportLoadTimeout() {
    _loadWatchdog = null;
    SellwildFailures.log(
      code: SellwildFailureCode.widgetLoadTimeout,
      component: SellwildFailureComponent.webview,
      message: 'no WIDGET_LOADED within ${widgetLoadedDeadline.inSeconds} s',
      url: widgetPageBaseUrl,
    );
  }

  void _handleLoadError(WebResourceError error) {
    if (isWidgetScriptLoadError(error)) {
      // partner.js failed (Android reports sub-resource errors): the widget
      // stays blank.
      SellwildFailures.log(
        code: SellwildFailureCode.widgetScriptLoadNetwork,
        component: SellwildFailureComponent.widget,
        severity: SellwildFailureSeverity.fatal,
        error: error.description,
        message: webResourceErrorSummary(error),
        url: error.url,
      );
    } else if (isPageLoadError(error)) {
      // Reported below as the page's own load failure.
      _cancelLoadWatchdog();
    }
    _reportLoadError(error, SellwildFailureComponent.webview, widget.onError);
  }

  void _handleMessage(String text) {
    const component = SellwildFailureComponent.webview;
    switch (decodeWidgetBridgeMessage(text)) {
      case final BridgeFailure failure:
        _reportBridgeFailure(failure, SellwildFailureComponent.bridge);
      case WidgetLoaded():
        // After dispose there is no spinner, and the host was not told
        // before either (setState threw): a lifecycle case, not a failure.
        if (!mounted) return;
        _cancelLoadWatchdog();
        setState(() => _loading = false);
        _callHost('onLoad', component, () => widget.onLoad?.call());
      case ListingClick(:final listing, :final droppedPhotos):
        if (droppedPhotos > 0) {
          // The listing still reaches the host, without those entries.
          SellwildFailures.log(
            code: SellwildFailureCode.listingsItemInvalid,
            component: SellwildFailureComponent.bridge,
            severity: SellwildFailureSeverity.warn,
            message: 'LISTING_CLICK listing has $droppedPhotos photos entries '
                'that are not objects; dropped',
          );
        }
        _callHost('onListingTap', component,
            () => widget.onListingTap?.call(listing));
      case AdImpression(:final zoneId):
        _callHost('onAdImpression', component,
            () => widget.onAdImpression?.call(zoneId));
      case UnreadMessage(:final reason):
        SellwildLog.debug(() => 'SellwildWidget: $reason, not called');
      case PageError(:final message):
        // A script error inside the page, which cannot report it itself.
        // The host still hears of it (existing onError), after the report.
        SellwildFailures.log(
          code: SellwildFailureCode.bridgeScriptException,
          component: component,
          message: message,
        );
        _callHost('onError', component,
            () => widget.onError?.call(Exception(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        WebViewWidget(controller: _controller),
        if (_loading) const Center(child: CircularProgressIndicator()),
      ],
    );
  }
}

/// Sellwild banner ad widget.
///
/// Example:
/// ```dart
/// SellwildBanner(
///   config: config,
///   adSize: SellwildAdSize.banner320x50,
///   zoneId: '12345',
///   onImpression: () => print('Ad shown'),
/// )
/// ```
class SellwildBanner extends StatefulWidget {
  final SellwildConfig config;
  final SellwildAdSize adSize;
  final String? zoneId;
  final void Function()? onImpression;
  final void Function()? onClick;
  final void Function(Object error)? onError;

  const SellwildBanner({
    super.key,
    required this.config,
    required this.adSize,
    this.zoneId,
    this.onImpression,
    this.onClick,
    this.onError,
  });

  @override
  State<SellwildBanner> createState() => _SellwildBannerState();
}

class _SellwildBannerState extends State<SellwildBanner> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    const component = SellwildFailureComponent.banner;
    final missing = missingBannerConfigReason(widget.config, widget.zoneId);
    if (missing != null) {
      // The page still loads, with a blank slot, as before.
      SellwildFailures.log(
        code: SellwildFailureCode.adBannerConfigMissing,
        component: component,
        severity: SellwildFailureSeverity.warn,
        message: missing,
      );
    }
    final controller = _controller = WebViewController();
    _reportSetupFailure(component, [
      controller.setJavaScriptMode(JavaScriptMode.unrestricted),
      controller.setBackgroundColor(Colors.transparent),
      controller.addJavaScriptChannel(
        'SellwildAdBridge',
        onMessageReceived: (message) => _handleMessage(message.message),
      ),
      controller.setNavigationDelegate(NavigationDelegate(
        onWebResourceError: (error) =>
            _reportLoadError(error, component, widget.onError),
      )),
      controller.loadHtmlString(
        buildBannerHtml(widget.config, widget.adSize, widget.zoneId),
        baseUrl: widgetPageBaseUrl,
      ),
    ]);
  }

  void _handleMessage(String text) {
    const component = SellwildFailureComponent.banner;
    switch (decodeAdBridgeMessage(text)) {
      case final BridgeFailure failure:
        _reportBridgeFailure(failure, component);
      case BannerImpression():
        _callHost('onImpression', component, () => widget.onImpression?.call());
      case BannerClick():
        _callHost('onClick', component, () => widget.onClick?.call());
      // The page's own reports (buildBannerHtml): the slot stays blank and
      // the host is not called, as before.
      case BannerScriptError(:final src):
        SellwildFailures.log(
          code: SellwildFailureCode.adBannerScriptNetwork,
          component: component,
          message: 'banner script failed to load',
          url: src,
        );
      case BannerSlotError(:final message):
        SellwildFailures.log(
          code: SellwildFailureCode.adGptSlotInvalid,
          component: component,
          message: message ?? 'defineSlot returned null',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.adSize.width.toDouble(),
      height: widget.adSize.height.toDouble(),
      child: WebViewWidget(controller: _controller),
    );
  }
}

/// The WebView setup [calls], started in order as the old cascade did. The
/// first that fails is reported once (widget.webview_load.exception: a
/// platform call threw, which is not a network failure), then [onReported]
/// runs: a WebView that cannot take its page shows nothing. Before, the
/// failure was an unhandled async error.
void _reportSetupFailure(String component, List<Future<void>> calls,
    {void Function()? onReported}) {
  unawaited(Future.wait(calls).then<void>((_) {}, onError: (Object error) {
    SellwildFailures.log(
      code: SellwildFailureCode.widgetWebviewLoadException,
      component: component,
      error: error,
      message: 'WebView setup failed',
      url: widgetPageBaseUrl,
    );
    onReported?.call();
  }));
}

/// A WebView load error: reported once when it is the page's own, then
/// passed to the host's onError as before (every error, as before). An
/// onError that throws is reported like every other host callback; before,
/// it escaped the navigation delegate.
void _reportLoadError(WebResourceError error, String component,
    void Function(Object error)? onError) {
  if (isPageLoadError(error)) {
    SellwildFailures.log(
      code: SellwildFailureCode.widgetWebviewLoadNetwork,
      component: component,
      error: error.description,
      message: webResourceErrorSummary(error),
      url: error.url,
    );
  }
  _callHost('onError', component, () => onError?.call(error));
}

void _reportBridgeFailure(BridgeFailure failure, String component) =>
    SellwildFailures.log(
      code: failure.code,
      component: component,
      severity: SellwildFailureSeverity.warn,
      error: failure.error,
      message: failure.message,
    );

/// Calls the host callback [name]. One that throws is reported
/// (widget.host_callback.exception) and not rethrown: it runs inside the
/// WebView channel callback, where it was swallowed silently before.
void _callHost(String name, String component, void Function() call) {
  try {
    call();
  } catch (e) {
    SellwildFailures.log(
      code: SellwildFailureCode.widgetHostCallbackException,
      component: component,
      severity: SellwildFailureSeverity.warn,
      error: e,
      message: '$name threw',
    );
  }
}
