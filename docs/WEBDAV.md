# WebDAV 来源

在「来源 → 添加服务器连接」中选择 WebDAV，填写音乐目录 URL、用户名和密码，然后连接并同步。URL 可包含反向代理路径，末尾斜杠可省略；密码存于系统安全存储，不写入曲库或媒体 URL。

当前支持 HTTP Basic 认证；按 WebDAV [RFC 4918](https://www.rfc-editor.org/rfc/rfc4918.html) 的 `PROPFIND Depth: 1` 递归读取目录。扫描只读取目录属性，不下载整首音乐。中文、空格、#、%、& 等文件名会编码处理。服务器返回的资源须属于配置的同一站点和目录，未经验证的跳转会被拒绝。

- 支持与本地导入相同的音乐扩展名；首次索引用文件名作标题、上级目录作专辑、再上一级目录作艺术家。当前不通过远程扫描解析音频内嵌标签。
- 播放和拖动进度复用应用的音频代理与 Range 读取；完整缓存、自动缓存、缓存任务、来源停用和重新启用复用现有流程。
- 歌词读取同目录同名 `.lrc` 或 `.txt`（同步时识别实际大小写）。已有完整缓存时也可读取内嵌歌词；不会为了歌词自动下载整首音频。
- 封面读取同名 jpg/png，或目录中的 cover/folder/front 的 jpg/png，以及 cover.webp。
- 曲目可加入收藏、本地歌单和播放队列；WebDAV 不提供云歌单编辑，不会对服务器执行 PUT、DELETE、MOVE、MKCOL 等写入操作。
- 认证失败、损坏的目录响应或子目录权限错误会中止本次同步并保留旧索引。修改地址请添加新来源以隔离旧缓存。

建议服务器支持音频 GET/HEAD 与 HTTP Range，以便流畅拖动和缓存。HTTP 地址会在来源列表标注「未加密」。

本地回归测试：`flutter test test/webdav_test.dart`；原生端到端测试：`flutter test integration_test/webdav_test.dart -d windows`（或 Android 设备）。真实服务器只读测试通过环境变量 `SYLPHY_WEBDAV_CREDENTIAL_FILE` 指向私密的三行 URL / 用户名 / 密码文件；测试不会输出地址、密码、曲目名称或歌词。
