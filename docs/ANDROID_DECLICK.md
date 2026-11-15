# Android De-click 与输出诊断

Android 的唯一播放器仍由 MediaLibraryService / Media3 Session 管理。2026-09-17 固定版本的上游 mpv 原生库替换旧精简库，以获得 afade / ashowinfo；完整来源与逐 ABI 校验记录见 NATIVE_DEPENDENCIES.md 及 tool/prepare_android_mpv.py。应用权限和 UI 不从上游 APK 导入，VM 通过 FFmpeg 公开接口注册。

设置 → 播放器设置提供 De-click 平滑跳转（实验）开关，默认关闭，持久保存；开关对下一次开始 / 跳转生效。用户音量、ReplayGain、duck 音量不作为包络控制通道。

JNI 在 mpv 音频滤镜链中使用半余弦 afade：正常速度下跳转前约 12ms 淡出，新位置约 20ms 淡入。fix-pts=no 保留媒体 PTS，精确 Seek 的前滚帧在目标时间之前为静音，避免前滚裁剪掉淡入。滤镜按照 PCM 样本计算增益；原生线程轮询只用于等到淡出时间线结束再 Seek，最多等待一秒，并响应暂停意图；已有输出队列较多时会引入可感知的跳转延迟，因此默认关闭供用户实机 A/B 后选择。没有使用 Dart / Kotlin 音量阶梯，也不修改 audio-buffer 或 audio-stream-silence。已有切歌 300ms 间隔保留。

滤镜输出的数值 PTS / 帧长用于安排淡出；FFmpeg INFO 在 mpv 中映射为 verbose，客户端以 v 订阅，模块级别限定在 ffmpeg / lavfi。不同日志模块前缀不参与匹配。原始 FFmpeg 文本不离开 JNI，不记录 URL、路径或元数据。记录有界（最多 128 项），仅在用户打开诊断日志时转发到原有轮转日志，关闭立即清空。事件包括 seek_requested、mpv_seek、mpv_playback_restart、mpv_audio_reconfig、淡入 / 淡出安排、完成、时钟缺失及超时。数值字段包含原生单调时间、请求 / 观察位置、采样率、通道数、AO 类型与格式和重配计数。Audio Reconfig 只能证明音频链重配，不能单独证明 Java AudioTrack 对象重建或确定啪声成因。

自动检查使用合成音频；PCM 滤镜检查与 Android 原生播放 / 跳转检查分开记录，不将它们表述为扬声器、耳机或特定 ROM 的实听 A/B。用户可以在同一音量、同一文件与相同跳转位置下，分别关闭 / 开启开关，比较首次播放、暂停恢复、向前 / 向后 Seek；覆盖扬声器、有线 / 蓝牙耳机及 WAV / FLAC / MP3 / AAC / Opus，并导出开启的诊断日志。实际输出设备的瞬态噪声仍需实机确认。
