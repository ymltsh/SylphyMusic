import 'dart:convert';

enum SourceKind { emby, subsonic, local, webdav, fnMusic }

extension SourceCapabilities on SourceKind {
  bool get cloudFavorites =>
      this == SourceKind.emby || this == SourceKind.subsonic;

  bool get cloudPlaylists =>
      this == SourceKind.emby ||
      this == SourceKind.subsonic ||
      this == SourceKind.fnMusic;

  bool get cloudPlaylistWritable =>
      this == SourceKind.emby || this == SourceKind.subsonic;
}

enum PlaylistKind { favorites, local, cloud }

enum SyncStatus { synced, pending, syncing, conflict, failed, readonly }

enum RepeatKind { off, all, one }

enum PlaybackMode {
  listLoop('列表循环'),
  singleLoop('单曲循环'),
  shuffle('随机播放');

  const PlaybackMode(this.label);
  final String label;
  PlaybackMode get next => values[(index + 1) % values.length];
}

class TrackRef {
  const TrackRef(this.sourceId, this.id);
  final String sourceId;
  final String id;
  String get key => jsonEncode([sourceId, id]);
  static TrackRef parse(String key) {
    final raw = jsonDecode(key) as List;
    return TrackRef(raw[0] as String, raw[1] as String);
  }

  @override
  bool operator ==(Object other) =>
      other is TrackRef && sourceId == other.sourceId && id == other.id;
  @override
  int get hashCode => Object.hash(sourceId, id);
}

class SourceProfile {
  const SourceProfile({
    required this.id,
    required this.name,
    required this.kind,
    required this.url,
    required this.username,
    this.remoteUserId = '',
    this.enabled = true,
    this.lastSync = 0,
    this.webdavBasePath = '',
    this.webdavMaxDepth = -1,
  });
  final String id, name, url, username, remoteUserId;
  final SourceKind kind;
  final bool enabled;
  final int lastSync;

  /// Path relative to the configured WebDAV URL (not part of track IDs).
  final String webdavBasePath;

  /// -1: unlimited; 0: current folder only; N: N descendant levels.
  final int webdavMaxDepth;
  Map<String, Object?> toRow() => {
    'id': id,
    'name': name,
    'kind': kind.name,
    'url': url,
    'username': username,
    'remote_user_id': remoteUserId,
    'enabled': enabled ? 1 : 0,
    'last_sync': lastSync,
    'webdav_base_path': webdavBasePath,
    'webdav_max_depth': webdavMaxDepth,
  };
  factory SourceProfile.fromRow(Map<String, Object?> row) => SourceProfile(
    id: row['id'] as String,
    name: row['name'] as String,
    kind: SourceKind.values.byName(row['kind'] as String),
    url: row['url'] as String,
    username: row['username'] as String,
    remoteUserId: row['remote_user_id'] as String? ?? '',
    enabled: row['enabled'] == 1,
    lastSync: row['last_sync'] as int? ?? 0,
    webdavBasePath: row['webdav_base_path'] as String? ?? '',
    webdavMaxDepth: row['webdav_max_depth'] as int? ?? -1,
  );
}

class Track {
  const Track({
    required this.ref,
    required this.title,
    required this.artist,
    required this.album,
    this.albumArtist = '',
    this.durationMs = 0,
    this.coverId = '',
    this.year = 0,
    this.disc = 0,
    this.number = 0,
    this.remote = const {},
    this.missing = false,
  });
  final TrackRef ref;
  final String title, artist, album, albumArtist, coverId;
  final int durationMs, year, disc, number;
  final Map<String, dynamic> remote;
  final bool missing;
  ({String id, String? tag}) get primaryArtwork {
    final own = (remote['ImageTags'] as Map?)?['Primary']?.toString();
    if (own?.isNotEmpty == true) return (id: ref.id, tag: own);
    final album = remote['AlbumPrimaryImageTag']?.toString();
    if (album?.isNotEmpty == true && remote['AlbumId'] != null) {
      return (id: remote['AlbumId'].toString(), tag: album);
    }
    final parent = remote['ParentPrimaryImageTag']?.toString();
    if (parent?.isNotEmpty == true &&
        remote['ParentPrimaryImageItemId'] != null) {
      return (id: remote['ParentPrimaryImageItemId'].toString(), tag: parent);
    }
    return (
      id: remote.containsKey('AlbumId') || coverId.isEmpty ? ref.id : coverId,
      tag: null,
    );
  }

  String get artworkIdentity => primaryArtwork.id;
  String get artworkVersion => jsonEncode([
    primaryArtwork.id,
    primaryArtwork.tag ??
        [remote['etag'], remote['DateModified'], remote['modified']],
    remote['coverPath'],
  ]);
  String get resourceVersion {
    final media = (remote['MediaSources'] as List?)
        ?.whereType<Map>()
        .firstOrNull;
    return jsonEncode([
      remote['size'] ?? media?['Size'],
      remote['DateModified'] ?? remote['changed'],
      if (remote['etag'] != null) remote['etag'],
      remote['contentType'] ?? remote['Container'] ?? media?['Container'],
    ]);
  }

  String get artistGroup => artist.trim().toLowerCase();
  String get albumGroup =>
      '${albumArtist.isEmpty ? artist : albumArtist}|$album'
          .trim()
          .toLowerCase();
  Map<String, Object?> toRow() => {
    'source_id': ref.sourceId,
    'id': ref.id,
    'title': title,
    'artist': artist,
    'album': album,
    'album_artist': albumArtist,
    'duration_ms': durationMs,
    'cover_id': coverId,
    'year': year,
    'disc': disc,
    'number': number,
    'remote_json': jsonEncode(remote),
    'missing': missing ? 1 : 0,
  };
  factory Track.fromRow(Map<String, Object?> row) => Track(
    ref: TrackRef(row['source_id'] as String, row['id'] as String),
    title: row['title'] as String? ?? '',
    artist: row['artist'] as String? ?? '',
    album: row['album'] as String? ?? '',
    albumArtist: row['album_artist'] as String? ?? '',
    durationMs: row['duration_ms'] as int? ?? 0,
    coverId: row['cover_id'] as String? ?? '',
    year: row['year'] as int? ?? 0,
    disc: row['disc'] as int? ?? 0,
    number: row['number'] as int? ?? 0,
    remote: jsonDecode(
      row['remote_json'] as String? ?? '{}',
    ) as Map<String, dynamic>,
    missing: row['missing'] == 1,
  );
}

class PlaylistModel {
  const PlaylistModel({
    required this.id,
    required this.name,
    required this.kind,
    this.sourceId,
    this.remoteId,
    this.status = SyncStatus.synced,
    this.base = const [],
    this.message = '',
    this.baseName = '',
  });
  final String id, name;
  final PlaylistKind kind;
  final String? sourceId, remoteId;
  final SyncStatus status;
  final List<String> base;
  final String message;
  final String baseName;
  Map<String, Object?> toRow() => {
    'id': id,
    'name': name,
    'kind': kind.name,
    'source_id': sourceId,
    'remote_id': remoteId,
    'status': status.name,
    'base_json': jsonEncode(base),
    'message': message,
    'base_name': baseName.isEmpty ? name : baseName,
  };
  factory PlaylistModel.fromRow(Map<String, Object?> row) => PlaylistModel(
    id: row['id'] as String,
    name: row['name'] as String,
    kind: PlaylistKind.values.byName(row['kind'] as String),
    sourceId: row['source_id'] as String?,
    remoteId: row['remote_id'] as String?,
    status: SyncStatus.values.byName(row['status'] as String? ?? 'synced'),
    base: List<String>.from(
      jsonDecode(row['base_json'] as String? ?? '[]') as List,
    ),
    message: row['message'] as String? ?? '',
    baseName: row['base_name'] as String? ?? row['name'] as String,
  );
  PlaylistModel copyWith({
    String? remoteId,
    SyncStatus? status,
    List<String>? base,
    String? message,
    String? name,
    String? baseName,
  }) => PlaylistModel(
    id: id,
    name: name ?? this.name,
    kind: kind,
    sourceId: sourceId,
    remoteId: remoteId ?? this.remoteId,
    status: status ?? this.status,
    base: base ?? this.base,
    message: message ?? this.message,
    baseName: baseName ?? this.baseName,
  );
}

class QueueSnapshot {
  const QueueSnapshot({
    this.tracks = const [],
    this.index = 0,
    this.positionMs = 0,
    this.repeat = RepeatKind.all,
    this.shuffle = false,
    this.order = const [],
    this.history = const [],
  });
  final List<String> tracks;
  final int index, positionMs;
  final RepeatKind repeat;
  final bool shuffle;
  final List<int> order, history;
  PlaybackMode get playbackMode => repeat == RepeatKind.one
      ? PlaybackMode.singleLoop
      : shuffle
      ? PlaybackMode.shuffle
      : PlaybackMode.listLoop;
  Map<String, dynamic> toJson() => {
    'tracks': tracks,
    'index': index,
    'positionMs': positionMs,
    'repeat': repeat.name,
    'shuffle': shuffle,
    'order': order,
    'history': history,
  };
  factory QueueSnapshot.fromJson(Map<String, dynamic> json) {
    final tracks = List<String>.from(json['tracks'] as List? ?? []);
    final order = List<int>.from(json['order'] as List? ?? []);
    final valid =
        order.length == tracks.length &&
        order.toSet().length == tracks.length &&
        order.every((index) => index >= 0 && index < tracks.length);
    final position = json['positionMs'] as int? ?? 0;
    final savedRepeat =
        RepeatKind.values
            .where((kind) => kind.name == json['repeat'])
            .firstOrNull ??
        RepeatKind.all;
    // Old sequential queues become list loops; single-repeat takes precedence
    // over an old combined shuffle + repeat-one configuration.
    final shuffle = json['shuffle'] == true && savedRepeat != RepeatKind.one;
    return QueueSnapshot(
      tracks: tracks,
      index: tracks.isEmpty
          ? 0
          : (json['index'] as int? ?? 0).clamp(0, tracks.length - 1),
      positionMs: position < 0 ? 0 : position,
      repeat: savedRepeat == RepeatKind.off ? RepeatKind.all : savedRepeat,
      shuffle: shuffle,
      order: valid && shuffle ? order : List.generate(tracks.length, (i) => i),
      history: List<int>.from(json['history'] as List? ?? [])
          .where((i) => i >= 0 && i < tracks.length)
          .toList(),
    );
  }
}
