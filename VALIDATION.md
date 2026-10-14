# 验证记录

日期：2026-10-14。Flutter/FVM 3.41.9，Android 16 / HyperOS OS3.0，
小米 23127PN0CC。诊断 compileSdk/targetSdk 36。

插件通过本地 path 加载于 ../listen1_xuan/tools/flutter_status_bar_probe。
诊断宿主仅保留日志、渲染模式切换，没有原生代理安装或回顶桥接实现。
插件自动注册并通过 ActivityAware 在宿主 FlutterView 下安装代理。

用户手动点击状态栏：SurfaceView、TextureView 各三轮成功。
每个模式 requests=3、Dart received=3、Dart completed=3、native acks=3。
每次 Flutter 列表从 logical offset=3200 回到零，原生使用 100px 状态哨兵。
顶部再次点击没有增加回顶请求；TextureView 日志明确查询 result=false。

SurfaceView 三次完成约为会话 10.319、13.581、15.774 秒；
TextureView 三次完成约为会话 4.088、6.236、8.309 秒。
完整记录见诊断工程 evidence/2026-10-14-plugin.log，包含历史会话，
以 SESSION PLUGIN HOST 分段。

检查：插件与诊断工程 flutter analyze 通过，插件六项测试通过：

- 旧页面标识请求拒绝、移除注册后禁用。
- 并发重复请求拒绝、销毁后的迟到结果拒绝。
- 暂停禁用与恢复启用。
- enabled=false 时不执行回调。
- 旧页面回调仍等待时，新页面可独立处理请求。
- 覆盖路由时禁用底层页面，返回后重新启用。

Android 插件模块随诊断 APK 编译成功并安装运行。
未运行格式化，未修改主应用入口，未发布 pub.dev。

补充主项目验证：listen1_xuan 本地 pub 依赖接入歌单详情页，插件自动安装
于 com.ryanheise.audioservice.AudioServiceActivity（1200×2670）。用户三轮
状态栏回顶均 handled=true、requests=3、acks=3。歌单回调并行处理内外
控制器，回顶期间暂停原有联动。主项目三个专项测试通过，Android 构建通过。
事件日志见 ../listen1_xuan/tools/flutter_status_bar_probe/evidence/2026-10-14-main-app.log。

边界：其他主项目页面、特殊 add-to-app
宿主、多 Flutter 引擎共享 Activity，以及其他厂商/系统版本仍需验证。
不把旧版自定义 Activity 实验当作这些场景的验证。
