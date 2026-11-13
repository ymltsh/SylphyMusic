# 在线封面兜底

原音源的歌曲 / 专辑封面或艺术家图片缺失时自动在线补充。默认启用，当前没有设置页开关；开发注入可用 ArtworkStore(enableOnlineFallback: false) 关闭。

原音源优先：本地提取图片、WebDAV 内嵌及旁置图片、服务器图片均先读取。图片不存在（404 / 无图片 URL）时再查询在线服务，认证失败和服务器错误不通过在线图片掩盖。艺术家元数据接口返回 404 也按缺失处理。

艺术家图片来自 TheAudioDB；专辑封面先查询 TheAudioDB，再按艺术家 / 专辑名称匹配 MusicBrainz release-group，从 Cover Art Archive 获取图片。只发送艺术家和专辑名称，不发送歌曲文件、服务器地址或音源凭据。独立 HttpClient 不使用音乐源的认证头和 Cookie，图片限定 HTTPS 可信域名，CAA 重定向逐跳校验。公开服务的命中率与网络可用性不保证，无匹配时保留默认图。

同来源相同查询合并，最多两个并发任务，未命中 / 网络失败在内存中退避 30 分钟；MusicBrainz 请求间隔至少约 1.1 秒。来源停用按代次取消其在途请求及等待任务，退出关闭生产任务后再关闭共享缓存。JSON 上限 1 MiB、图片上限 8 MiB；图片通过 MediaAssetStore 解码、长度 / 摘要检查并原子提交，沿用来源隔离、配额、租约与默认 24 小时有效期 / 后台刷新。已有有效缓存直接读取，不把音频残片当成完整缓存。

接口参考：[TheAudioDB](https://www.theaudiodb.com/free_music_api)、[MusicBrainz 速率限制](https://musicbrainz.org/doc/MusicBrainz_API/Rate_Limiting)、[Cover Art Archive API](https://musicbrainz.org/doc/Cover_Art_Archive/API)。不改变媒体身份、队列、播放及音源同步协议。
