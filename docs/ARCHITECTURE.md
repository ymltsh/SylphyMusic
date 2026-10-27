# 架构说明

```text
Flutter Material 3 UI
  │
  ▼
SylphyApp  ⇄ AppDb (SQLite)
  ├── EmbyAdapter / SubsonicAdapter ⇄ remote music server
  ├── LibrarySync ⇄ adapter pages → SQLite index_tracks → atomic live index
  ├── LibraryCatalog ⇄ SQL filters / groups / bounded pages → library UI
  ├── PlaylistSyncService ⇄ remote playlists (read / conservative 3-way merge / write)
  ├── CacheJobs ⇄ CacheManager ⇄ SQLite jobs + READY audio
  └── PlaybackCoordinator ⇄ media_kit / libmpv + audio_service(Android)
                              │
                              ▼
                    MediaProxy (127.0.0.1)
                              │
                    HTTP origin / READY files
```

## 一致性与故障边界

1. `TrackRef = (SourceProfileId, RemoteTrackId)` 是精确媒体身份，不通过名称跨源合并。
2. 歌单有独立条目 ID，允许重复歌曲；播放队列也独立于来源歌单。
3. 云歌单保存已同步基线、当前本地版本与最新服务器版本。可安全追加自动合并；其他情况提示冲突并备份。
4. 缓存仅提交完整文件，写入 TEMP、读完确认完整、计算摘要、同卷 rename、SQLite READY。崩溃后对账与清理 TEMP。
5. 下一首预缓存不进入 READY，也不跨重启保留；P2 只有有限预取资源。
6. 不同账户的凭据与内容隔离；不会替用户写远程收藏或做自动转码。
7. 真实 Android 前台服务和独立用户发起缓存调度是两项不同工作，不可用媒体播放服务伪装下载任务。
8. 远程全量扫描逐页写隔离暂存表，成功后在单个事务中软删除旧快照、合入新快照并更新时间。失败或取消不发布半份索引；异常退出留下的运行标记促使下次启动重新扫描，残缺元数据页本身不续接。
9. 启动不读取全库 Track 列表。歌曲、专辑、艺术家、选曲与黑名单列表由 SQLite 过滤 / 聚合后每页读取 100 条；播放全部只读 TrackRef 身份，当前曲目与队列可见行单独查询元数据。
