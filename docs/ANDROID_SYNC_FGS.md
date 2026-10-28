# Android 手动同步前台服务

音乐源管理的「同步所有来源」「同步此来源」以及 WebDAV「只补全 WebDAV 标签（前台通知）」在用户点击后启动 dataSync 前台通知，索引与标签阶段分别显示进度，通知支持暂停。自动恢复 / 过期刷新仍是机会式任务，不从普通后台状态主动启动新 FGS。

引擎由 audio_service 0.18.19 创建、缓存和销毁；SylphyApplication 通过插件的 getFlutterEngine 获取同一个实例，按引擎实例注册生命周期 Channel，不单独执行 Dart main，也不拦截 destroy 或异步恢复缓存。Activity 只持有图标及通知权限请求，移除时清理其 handler。

EngineLeaseManager 为同步、缓存分别记录服务实例的租约，共享一个到 AudioService 的显式绑定。必须收到 onServiceConnected 且缓存身份 / Dart 执行状态一致才确认任务可用；失败、断开和空绑定会通知 Dart 取消，并有停止兜底。只释放对应实例的租约，最后一个任务退出才解绑。AudioService 仍由插件正常管理：没有 Activity、播放或任务租约后允许销毁引擎。

普通通知暂停进入 STOPPING：先通知 Dart，取消索引和标签请求，等待索引 / 标签遍历 / 可见行读取或缓存 worker、SQLite 状态写入结束，再以 MethodChannel 回执确认停服。清理过程中 Dart 自己的 stop 调用可返回，但不会提前释放租约，避免互相等待。无回执时最多保留 60 秒。系统 onTimeout 例外：立即移除前台通知并 stopSelf，不等待 Dart；进程和引擎消失后依靠已提交的数据恢复。

同步开始等待原生服务确认，失败不降级为无通知长任务。退出先等待任务再关闭 SQLite。完整索引仍原子切换；标签按文件版本保留，下次手动补全跳过成功记录。标签进度区分成功写入、失败和已缓存跳过，已缓存行不再逐首等待 250 毫秒。

诊断仅记录数字和任务类型：引擎身份、缓存一致性、绑定 / 租约数量、每引擎 Dart 启动次数、Dart 定时心跳年龄，以及实际处理数量。原生心跳本身不代表 Dart 存活，测试同时检查 Dart 心跳与 SQLite 新增记录。日志不包含来源地址、凭据或曲目信息。

Android 13+ 通知权限拒绝不阻断前台服务；Android 12+ 后台启动限制、Android 15+ dataSync 累计时限与用户停止应用仍生效。进程死亡、系统停止或强停后不承诺继续运行。不同厂商电源策略需要真机验证。

验证入口：test/sync_foreground_test.dart；test/webdav_metadata_test.dart；integration_test/sync_foreground_test.dart。专用 SylphyTest_API35 AVD 运行：

```powershell
python tool/check_android_fgs.py --scenario timeout --device emulator-5580
python tool/check_android_fgs.py --scenario overlap --device emulator-5580
```

工具使用合成音频 / 本地 HTTP 服务，临时设置 dataSync 时限并在 finally 恢复，不修改 compat 覆盖。timeout 场景 Home 后等待真实系统回调，保留 Activity 以便测试 isolate 检查数据并恢复；overlap 场景覆盖播放 / 暂停、同步与慢速缓存并行、Home / 熄屏 / 移除最近任务、双方分别暂停后保留另一租约、重新打开 Activity 后同引擎 / 单次 Dart 启动，以及最终释放全部租约。工具拒绝其他 AVD / 真机。移除任务后最后一个租约释放可能正常销毁测试 isolate，因此恢复 Activity 后才释放最后租约。

参考：[Android FGS 超时](https://developer.android.com/develop/background-work/services/fgs/timeout)、[Flutter 缓存引擎](https://docs.flutter.dev/add-to-app/android/add-flutter-screen)。
