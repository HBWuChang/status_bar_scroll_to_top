import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Registers an eligible foreground page for OEM Android status-bar scroll-to-top.
///
/// Return true from [onScrollToTop] only after the page has reached the top.
/// The app must set [enabled] for tabs, nested navigators and overlays whose
/// foreground state cannot be inferred from this widget's ModalRoute.
class StatusBarScrollToTop extends StatefulWidget {
  const StatusBarScrollToTop({
    super.key,
    required this.canScrollToTop,
    required this.onScrollToTop,
    required this.child,
    this.enabled = true,
    this.onDebugEvent,
  });

  final bool enabled;
  final bool canScrollToTop;
  final Future<bool> Function() onScrollToTop;
  final Widget child;
  final ValueChanged<Map<String, Object?>>? onDebugEvent;

  @override
  State<StatusBarScrollToTop> createState() => _TargetState();
}

class _TargetState extends State<StatusBarScrollToTop> {
  final int token = _Bridge.nextToken++;
  bool currentRoute = true;
  bool tickerEnabled = true;

  bool get eligible => mounted && widget.enabled && currentRoute && tickerEnabled;

  @override
  void initState() {
    super.initState();
    _Bridge.instance.add(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    currentRoute = ModalRoute.of(context)?.isCurrent ?? true;
    tickerEnabled = TickerMode.valuesOf(context).enabled;
    _Bridge.instance.schedule();
  }

  @override
  void didUpdateWidget(StatusBarScrollToTop oldWidget) {
    super.didUpdateWidget(oldWidget);
    _Bridge.instance.schedule();
  }

  @override
  void dispose() {
    _Bridge.instance.remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _Bridge with WidgetsBindingObserver {
  static final instance = _Bridge();
  static int nextToken = 1;
  static const channel = MethodChannel('status_bar_scroll_to_top');
  final targets = <_TargetState>[];
  bool scheduled = false;
  _TargetState? runningTarget;
  bool foreground = true;
  Map<String, Object?>? lastSent;

  bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  _TargetState? get selected {
    for (final target in targets.reversed) {
      if (target.eligible) return target;
    }
    return null;
  }

  void add(_TargetState target) {
    if (targets.isEmpty) {
      foreground = WidgetsBinding.instance.lifecycleState == null ||
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
      WidgetsBinding.instance.addObserver(this);
      channel.setMethodCallHandler(handle);
      lastSent = null;
    }
    targets.add(target);
    schedule();
  }

  void remove(_TargetState target) {
    targets.remove(target);
    if (targets.isEmpty) WidgetsBinding.instance.removeObserver(this);
    schedule();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    schedule();
  }

  void schedule() {
    if (scheduled || !supported) return;
    scheduled = true;
    scheduleMicrotask(() async {
      scheduled = false;
      final target = selected;
      final state = <String, Object?>{
        'token': target?.token,
        'enabled': foreground && (target?.eligible ?? false),
        'canScrollToTop': target?.widget.canScrollToTop ?? false,
        'debug': target?.widget.onDebugEvent != null,
      };
      if (mapEquals(lastSent, state)) return;
      lastSent = state;
      try {
        await channel.invokeMethod<void>('update', state);
      } on MissingPluginException {
        lastSent = null;
      } on PlatformException catch (error) {
        lastSent = null;
        target?.widget.onDebugEvent?.call({'event': 'channelError', 'message': error.message});
      }
    });
  }

  Future<Object?> handle(MethodCall call) async {
    if (call.method == 'debug') {
      final data = Map<String, Object?>.from(call.arguments as Map);
      for (final target in List<_TargetState>.of(targets)) {
        if (target.mounted && target.token == data['token']) {
          target.widget.onDebugEvent?.call(data);
        }
      }
      return null;
    }
    if (call.method != 'scrollToTop') throw MissingPluginException();
    final data = Map<Object?, Object?>.from(call.arguments as Map);
    final target = selected;
    if (!foreground || target == null || runningTarget == target || target.token != data['token'] ||
        !target.widget.canScrollToTop) return {'handled': false};
    runningTarget = target;
    try {
      final handled = await target.widget.onScrollToTop();
      return {'handled': handled && target.eligible && foreground && selected == target};
    } catch (error, stack) {
      FlutterError.reportError(FlutterErrorDetails(exception: error, stack: stack,
        library: 'status_bar_scroll_to_top', context: ErrorDescription('while handling scroll-to-top')));
      return {'handled': false};
    } finally {
      if (runningTarget == target) runningTarget = null;
      lastSent = null;
      schedule();
    }
  }
}
