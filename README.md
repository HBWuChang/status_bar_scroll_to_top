# status_bar_scroll_to_top

实验性的 Android Flutter 插件，通过原生 ScrollView 代理将厂商系统的
状态栏回顶行为转发给当前 Flutter 页面。FVM 固定为 Flutter 3.41.9。
目前以本地 path 包使用，不发布 pub.dev。

插件版诊断已在小米 23127PN0CC / Android 16 / HyperOS OS3.0 上
通过 ActivityAware 自动接入，SurfaceView 和 TextureView 均连续三轮
成功回顶，无重复请求。见 VALIDATION.md。

## 接入

在 listen1_xuan 的 pubspec.yaml 中添加：

```yaml
dependencies:
  status_bar_scroll_to_top:
    path: ../status_bar_scroll_to_top
```

无需自定义 Activity、修改 Manifest、申请额外权限或注册厂商广播。
插件通过 ActivityAware 在宿主的 FlutterView 下安装同尺寸可见代理，
禁用代理触摸、焦点及无障碍子树。当前版本要求宿主 Activity 的
android.R.id.content 下能找到 FlutterView，支持单宿主/单前台目标。
AudioServiceActivity 已在 listen1_xuan 主项目实测，歌单连续三轮回顶成功。

页面滚动变化时更新 canScrollToTop；onScrollToTop 返回 true 表示
应用确认已完成回顶。例如监听 ScrollController 触发组件重建：

```dart
AnimatedBuilder(
  animation: scrollController,
  builder: (context, child) => StatusBarScrollToTop(
    enabled: isCurrentTab,
    canScrollToTop: scrollController.hasClients &&
        scrollController.offset > 0.5,
    onScrollToTop: () async {
      if (!scrollController.hasClients) return false;
      await scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut,
      );
      return scrollController.hasClients &&
          scrollController.offset.abs() < 0.5;
    },
    child: child!,
  ),
  child: list,
)
```

插件自动检查所在 ModalRoute.isCurrent、TickerMode 和应用生命周期。
复杂标签页、嵌套导航、非路由 Overlay 仍需应用通过 enabled 指定前台目标。
若多个目标同时符合条件，最后注册的目标优先。页面标识用于拒绝旧页面
请求和过期完成结果。插件无法取消应用已经开始的滚动回调，应用应当
在回调内检查自身生命周期，并及时返回。

歌单内外两个 ScrollController 的联动由应用的回调处理，插件不绑定
单一 ScrollController。可选 onDebugEvent 用于观察 installed、state、
systemQuery、request、complete、timeout；不传时不进行调用栈诊断。
系统调用栈仅用于统计，不作为功能依赖。

原生代理使用 100px 非零哨兵表示“可回顶”，不镜像真实列表偏移。
应用主动状态同步、系统终点重复通知、等待 Dart 完成期间的状态更新均
有保护。原生等待回调最多 10 秒，超时解除等待并忽略迟到的原生结果；
应用回调本身应在 10 秒内完成。

不支持的平台组件照常展示 child，不调用 Android 桥接。
其他厂商/系统版本、多个 Flutter 引擎共享 Activity、特殊 add-to-app 宿主
尚未验证。代理需要非零尺寸与真实滚动范围，不能直接改为 GONE/零尺寸。

## 验证

```sh
fvm use 3.41.9 --skip-pub-get
fvm flutter pub get
fvm flutter analyze --no-pub
fvm flutter test --no-pub
```

集成实验使用 ../listen1_xuan/tools/flutter_status_bar_probe，通过 path
依赖加载插件。该诊断的 MainActivity 仅保留日志与渲染模式切换，
原生代理全部由插件管理。
