import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:status_bar_scroll_to_top/status_bar_scroll_to_top.dart';

void main() {
  const channel = MethodChannel('status_bar_scroll_to_top');
  const codec = StandardMethodCodec();
  final updates = <Map<Object?, Object?>>[];
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<Object?> request(WidgetTester tester, Object? token) {
    final reply = Completer<ByteData?>();
    tester.binding.channelBuffers.push(channel.name,
      codec.encodeMethodCall(MethodCall('scrollToTop', {'token': token})), reply.complete);
    return reply.future.then((data) => codec.decodeEnvelope(data!));
  }

  Widget target(Future<bool> Function() callback, {bool enabled = true, Key? key}) {
    return Directionality(textDirection: TextDirection.ltr,
      child: StatusBarScrollToTop(key: key, enabled: enabled, canScrollToTop: true,
        onScrollToTop: callback, child: const SizedBox()));
  }

  setUp(() {
    updates.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
        updates.add(Map<Object?, Object?>.from(call.arguments as Map));
        return null;
      });
  });

  testWidgets('ignores stale page tokens and disables after unregister', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    var calls = 0;
    await tester.pumpWidget(target(() async { calls++; return true; }));
    final token = updates.last['token'];
    expect(await request(tester, -1), {'handled': false});
    expect(calls, 0);
    expect(await request(tester, token), {'handled': true});
    expect(calls, 1);
    await tester.pumpWidget(const SizedBox());
    expect(updates.last['enabled'], false);
    expect(await request(tester, token), {'handled': false});
  }, variant: TargetPlatformVariant({TargetPlatform.android}));

  testWidgets('rejects concurrent duplicate and late completion after dispose', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final completion = Completer<bool>();
    await tester.pumpWidget(target(() => completion.future));
    final token = updates.last['token'];
    final first = request(tester, token);
    await tester.pump();
    expect(await request(tester, token), {'handled': false});
    await tester.pumpWidget(const SizedBox());
    completion.complete(true);
    expect(await first, {'handled': false});
  }, variant: TargetPlatformVariant({TargetPlatform.android}));

  testWidgets('pausing disables native target and resuming re-enables it', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(target(() async => true));
    final token = updates.last['token'];
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(updates.last['enabled'], false);
    expect(await request(tester, token), {'handled': false});
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(updates.last['enabled'], true);
    await tester.pumpWidget(const SizedBox());
  }, variant: TargetPlatformVariant({TargetPlatform.android}));

  testWidgets('disabled page never receives a request', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    var calls = 0;
    await tester.pumpWidget(target(() async { calls++; return true; }, enabled: false));
    expect(updates.last['enabled'], false);
    expect(await request(tester, updates.last['token']), {'handled': false});
    expect(calls, 0);
    await tester.pumpWidget(const SizedBox());
  }, variant: TargetPlatformVariant({TargetPlatform.android}));

  testWidgets('new page can handle requests while old completion is pending', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final oldCompletion = Completer<bool>();
    await tester.pumpWidget(target(() => oldCompletion.future, key: const ValueKey('old')));
    final oldToken = updates.last['token'];
    final oldRequest = request(tester, oldToken);
    await tester.pump();
    await tester.pumpWidget(target(() async => true, key: const ValueKey('new')));
    final newToken = updates.last['token'];
    expect(newToken, isNot(oldToken));
    expect(await request(tester, newToken), {'handled': true});
    oldCompletion.complete(true);
    expect(await oldRequest, {'handled': false});
    await tester.pumpWidget(const SizedBox());
  }, variant: TargetPlatformVariant({TargetPlatform.android}));

  testWidgets('covering route disables old page until popped', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(Directionality(textDirection: TextDirection.ltr,
      child: Navigator(key: navigator, onGenerateRoute: (_) => PageRouteBuilder<void>(
        pageBuilder: (context, animation, secondary) => target(() async => true)))));
    final oldToken = updates.last['token'];
    unawaited(navigator.currentState!.push(PageRouteBuilder<void>(
      pageBuilder: (context, animation, secondary) => const SizedBox())));
    await tester.pumpAndSettle();
    expect(updates.last['enabled'], false);
    expect(await request(tester, oldToken), {'handled': false});
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(updates.last['enabled'], true);
    expect(updates.last['token'], oldToken);
    await tester.pumpWidget(const SizedBox());
  }, variant: TargetPlatformVariant({TargetPlatform.android}));
}
