package com.xiebian.statusbar_scroll_to_top;

import android.app.Activity;
import android.app.Application;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewGroup;
import android.widget.ScrollView;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.embedding.android.FlutterView;
import io.flutter.plugin.common.MethodChannel;
import java.util.HashMap;
import java.util.Map;

/** A native scroll target behind Flutter; no custom Activity required. */
public final class StatusBarScrollToTopPlugin implements FlutterPlugin, ActivityAware {
    private final Handler handler = new Handler(Looper.getMainLooper());
    private MethodChannel channel;
    private Activity activity;
    private Proxy proxy;
    private boolean enabled, canTop, debug, resumed, syncing, pending;
    private Integer token, pendingToken;
    private int requests, acks, queries, attachment;
    private long requestId;
    private Runnable timeout;

    private final Application.ActivityLifecycleCallbacks lifecycle = new Application.ActivityLifecycleCallbacks() {
        @Override public void onActivityResumed(Activity a) { if (a == activity) { resumed = true; apply(); } }
        @Override public void onActivityPaused(Activity a) {
            if (a == activity) {
                resumed = false;
                if (proxy != null && !pending) {
                    ((ViewGroup) proxy.getParent()).removeView(proxy);
                    proxy = null;
                    install(attachment, 0);
                }
                apply();
            }
        }
        @Override public void onActivityCreated(Activity a, Bundle b) {}
        @Override public void onActivityStarted(Activity a) {}
        @Override public void onActivityStopped(Activity a) {}
        @Override public void onActivitySaveInstanceState(Activity a, Bundle b) {}
        @Override public void onActivityDestroyed(Activity a) {}
    };

    @Override public void onAttachedToEngine(FlutterPluginBinding binding) {
        channel = new MethodChannel(binding.getBinaryMessenger(), "status_bar_scroll_to_top");
        channel.setMethodCallHandler((call, result) -> {
            if (!"update".equals(call.method)) { result.notImplemented(); return; }
            Number newToken = call.argument("token");
            Integer previousToken = token;
            boolean previousEnabled = enabled;
            boolean previousCanTop = canTop;
            token = newToken == null ? null : newToken.intValue();
            enabled = Boolean.TRUE.equals(call.argument("enabled"));
            canTop = Boolean.TRUE.equals(call.argument("canScrollToTop"));
            debug = Boolean.TRUE.equals(call.argument("debug"));
            if (proxy != null && !pending && (!java.util.Objects.equals(previousToken, token) ||
                previousEnabled != enabled || previousCanTop != canTop)) {
                ((ViewGroup) proxy.getParent()).removeView(proxy);
                proxy = null;
                install(attachment, 0);
            }
            apply();
            emit("state", "enabled=" + enabled + " canTop=" + canTop);
            result.success(null);
        });
    }

    @Override public void onDetachedFromEngine(FlutterPluginBinding binding) {
        detach();
        channel.setMethodCallHandler(null);
        channel = null;
    }

    @Override public void onAttachedToActivity(ActivityPluginBinding binding) {
        activity = binding.getActivity();
        resumed = true;
        activity.getApplication().registerActivityLifecycleCallbacks(lifecycle);
        final int generation = ++attachment;
        activity.getWindow().getDecorView().post(() -> install(generation, 0));
    }

    private void install(int generation, int attempt) {
        if (activity == null || generation != attachment || proxy != null) return;
        ViewGroup content = activity.findViewById(android.R.id.content);
        if (content == null || !containsFlutter(content)) {
            if (attempt < 50) handler.postDelayed(() -> install(generation, attempt + 1), 100);
            else emit("unsupportedHost", "No FlutterView found in Activity content");
            return;
        }
        proxy = new Proxy(activity);
        View spacer = new View(activity);
        spacer.setMinimumHeight(activity.getResources().getDisplayMetrics().heightPixels * 3);
        proxy.addView(spacer, new ScrollView.LayoutParams(-1, -2));
        content.addView(proxy, 0, new ViewGroup.LayoutParams(-1, -1));
        final Proxy installed = proxy;
        proxy.post(() -> {
            if (generation != attachment || proxy != installed) return;
            apply();
            emit("installed", "host=" + activity.getClass().getName() + " size=" + proxy.getWidth() + "x" + proxy.getHeight());
        });
    }

    private boolean containsFlutter(View view) {
        if (view instanceof FlutterView) return true;
        if (view instanceof ViewGroup) {
            ViewGroup group = (ViewGroup) view;
            for (int i = 0; i < group.getChildCount(); i++) if (containsFlutter(group.getChildAt(i))) return true;
        }
        return false;
    }

    private void apply() {
        if (proxy == null || pending) return;
        syncing = true;
        try {
            // A bounded non-zero sentinel represents eligibility, not the page's real offset.
            proxy.scrollTo(0, enabled && canTop && resumed && token != null ? 100 : 0);
        } finally { syncing = false; }
    }

    private Map<String, Object> stats() {
        Map<String, Object> data = new HashMap<>();
        data.put("token", token);
        data.put("queries", queries);
        data.put("requests", requests);
        data.put("acks", acks);
        data.put("proxyY", proxy == null ? 0 : proxy.getScrollY());
        return data;
    }

    private void emit(String event, String message) {
        if (!debug || channel == null) return;
        Map<String, Object> data = stats();
        data.put("event", event);
        data.put("message", message);
        channel.invokeMethod("debug", data);
    }

    private void finish(long id, boolean handled, String event) {
        if (!pending || id != requestId) return;
        pending = false;
        if (timeout != null) handler.removeCallbacks(timeout);
        timeout = null;
        handled = handled && java.util.Objects.equals(token, pendingToken);
        if (handled) {
            acks++;
            // Dart may not have rebuilt its canTop state yet after jumpTo(0).
            // Keep the proxy at zero so duplicate native animation endpoints
            // cannot re-arm and forward the same system tap again.
            canTop = false;
        }
        apply();
        emit(event, "handled=" + handled);
    }

    private void detach() {
        attachment++;
        requestId++;
        pending = false;
        if (timeout != null) handler.removeCallbacks(timeout);
        timeout = null;
        if (activity != null) activity.getApplication().unregisterActivityLifecycleCallbacks(lifecycle);
        if (proxy != null && proxy.getParent() instanceof ViewGroup) ((ViewGroup) proxy.getParent()).removeView(proxy);
        proxy = null;
        activity = null;
        resumed = false;
    }

    @Override public void onDetachedFromActivity() { detach(); }
    @Override public void onDetachedFromActivityForConfigChanges() { detach(); }
    @Override public void onReattachedToActivityForConfigChanges(ActivityPluginBinding binding) { onAttachedToActivity(binding); }

    private final class Proxy extends ScrollView {
        private boolean topNotified = true;
        Proxy(Activity host) {
            super(host);
            setFocusable(false);
            setVerticalScrollBarEnabled(false);
            setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS);
        }
        @Override public boolean onTouchEvent(MotionEvent event) { return false; }
        @Override public boolean onInterceptTouchEvent(MotionEvent event) { return false; }
        @Override public boolean canScrollVertically(int direction) {
            boolean result = enabled && canTop && resumed && !pending && token != null && super.canScrollVertically(direction);
            if (debug) {
                for (StackTraceElement frame : new Throwable().getStackTrace()) {
                    if (frame.getClassName().contains("ScrollToTopListener")) {
                        queries++;
                        emit("systemQuery", "dir=" + direction + " result=" + result);
                        break;
                    }
                }
            }
            return result;
        }
        @Override protected void onScrollChanged(int x, int y, int oldX, int oldY) {
            super.onScrollChanged(x, y, oldX, oldY);
            if (this != proxy) return;
            if (y > 0) topNotified = false;
            else if (syncing) topNotified = true;
            if (syncing || topNotified || y != 0 || oldY <= 0 || pending ||
                !enabled || !canTop || !resumed || token == null || channel == null) return;
            topNotified = true;
            pending = true;
            pendingToken = token;
            requests++;
            final long id = ++requestId;
            emit("request", "id=" + id);
            timeout = () -> finish(id, false, "timeout");
            handler.postDelayed(timeout, 10000);
            channel.invokeMethod("scrollToTop", stats(), new MethodChannel.Result() {
                @Override public void success(Object response) {
                    boolean handled = response instanceof Map && Boolean.TRUE.equals(((Map<?, ?>) response).get("handled"));
                    finish(id, handled, "complete");
                }
                @Override public void error(String code, String message, Object details) { finish(id, false, "error"); }
                @Override public void notImplemented() { finish(id, false, "notImplemented"); }
            });
        }
    }
}
