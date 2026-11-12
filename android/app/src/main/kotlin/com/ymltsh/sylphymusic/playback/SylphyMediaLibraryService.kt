package com.ymltsh.sylphymusic.playback

import android.app.PendingIntent
import android.content.Intent
import android.os.Bundle
import androidx.core.content.ContextCompat
import androidx.media3.common.util.UnstableApi
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import com.google.common.collect.ImmutableList
import androidx.media3.session.*
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture
import com.ymltsh.sylphymusic.MainActivity
import com.ymltsh.sylphymusic.SylphyApplication
import com.ymltsh.sylphymusic.R
import org.json.JSONObject

@UnstableApi
class SylphyMediaLibraryService : MediaLibraryService() {
    private lateinit var player: MpvMedia3Player
    private var session: MediaLibrarySession? = null
    override fun onCreate() {
        super.onCreate()
        setMediaNotificationProvider(DefaultMediaNotificationProvider.Builder(this)
            .setChannelId("music.sylphy.playback").setChannelName(R.string.app_name).build()
            .apply { setSmallIcon(R.drawable.ic_stat_sylphy) })
        player = MpvMedia3Player(application as SylphyApplication).also { native ->
            native.onFocusPending = { intent ->
                // A second skip/seek while already buffering may not trigger
                // another notification event. Existing Media3 foreground
                // ownership still permits the new intent's focus request.
                if (isPlaybackOngoing) android.os.Handler(mainLooper).post {
                    if (isPlaybackOngoing) native.foregroundReady(intent)
                }
            }
        }
        val activity = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        session = MediaLibrarySession.Builder(this, player, object : MediaLibrarySession.Callback {
            override fun onAddMediaItems(session: MediaSession, controller: MediaSession.ControllerInfo,
                                         mediaItems: List<MediaItem>): ListenableFuture<List<MediaItem>> {
                val known = player.libraryItems().associateBy { it.mediaId }
                val items = mediaItems.map { known[it.mediaId] ?: return Futures.immediateFailedFuture(IllegalArgumentException("Unknown media identity")) }
                return Futures.immediateFuture(items)
            }
            override fun onGetLibraryRoot(session: MediaLibrarySession, browser: MediaSession.ControllerInfo,
                                          params: LibraryParams?): ListenableFuture<LibraryResult<MediaItem>> =
                Futures.immediateFuture(LibraryResult.ofItem(MediaItem.Builder().setMediaId("sylphy.queue")
                    .setMediaMetadata(MediaMetadata.Builder().setTitle("当前播放队列").setIsBrowsable(true).setIsPlayable(false).build()).build(), params))
            override fun onGetChildren(session: MediaLibrarySession, browser: MediaSession.ControllerInfo,
                                       parentId: String, page: Int, pageSize: Int, params: LibraryParams?): ListenableFuture<LibraryResult<ImmutableList<MediaItem>>> {
                if (parentId != "sylphy.queue" || page < 0 || pageSize <= 0) return Futures.immediateFuture(LibraryResult.ofError(LibraryResult.RESULT_ERROR_BAD_VALUE))
                val entries = player.libraryItems()
                val start = (page.toLong() * pageSize).coerceAtMost(entries.size.toLong()).toInt()
                return Futures.immediateFuture(LibraryResult.ofItemList(entries.subList(start, (start.toLong() + pageSize).coerceAtMost(entries.size.toLong()).toInt()), params))
            }
            override fun onGetItem(session: MediaLibrarySession, browser: MediaSession.ControllerInfo,
                                   mediaId: String): ListenableFuture<LibraryResult<MediaItem>> {
                val item = player.libraryItems().firstOrNull { it.mediaId == mediaId }
                return Futures.immediateFuture(if (item == null) LibraryResult.ofError(LibraryResult.RESULT_ERROR_BAD_VALUE) else LibraryResult.ofItem(item, null))
            }
            override fun onConnectAsync(session: MediaSession, controller: MediaSession.ControllerInfo): ListenableFuture<MediaSession.ConnectionResult> {
                // Media3 1.11's deprecated Callback.onConnect returns an EMPTY
                // sentinel, not the default controller permissions. Copying it
                // strips GET_TIMELINE, PLAY_PAUSE, SEEK and all other commands
                // from both Flutter and Media3's own notification controller.
                val accepted = MediaSession.ConnectionResult.AcceptedResultBuilder(session, controller)
                if (controller.packageName == packageName) {
                    accepted.setAvailableSessionCommands(
                        MediaSession.ConnectionResult.DEFAULT_SESSION_AND_LIBRARY_COMMANDS.buildUpon()
                            .add(SessionCommand("sylphy.control", Bundle.EMPTY)).build())
                    accepted.setAvailablePlayerCommands(MediaSession.ConnectionResult.DEFAULT_PLAYER_COMMANDS)
                }
                return Futures.immediateFuture(accepted.build())
            }
            override fun onCustomCommand(session: MediaSession, controller: MediaSession.ControllerInfo,
                                         command: SessionCommand, args: Bundle): ListenableFuture<SessionResult> {
                if (controller.packageName != packageName || command.customAction != "sylphy.control")
                    return Futures.immediateFuture(SessionResult(SessionResult.RESULT_ERROR_PERMISSION_DENIED))
                return try {
                    val action = args.getString("action") ?: "snapshot"
                    val data = JSONObject(args.getString("data") ?: "{}")
                    fun response() = SessionResult(SessionResult.RESULT_SUCCESS, Bundle().apply {
                        putString("snapshot", player.snapshotJson(data.optLong("revision", -1)))
                    })
                    if (action == "seek") {
                        if (!player.isCommandAvailable(Player.COMMAND_SEEK_IN_CURRENT_MEDIA_ITEM))
                            return Futures.immediateFuture(SessionResult(SessionResult.RESULT_ERROR_INVALID_STATE))
                        player.seekTo(data.getLong("position"))
                        val executor = ContextCompat.getMainExecutor(this@SylphyMediaLibraryService)
                        return Futures.catching(
                            Futures.transform(player.awaitSeek(), { response() }, executor),
                            Exception::class.java,
                            { SessionResult(SessionResult.RESULT_ERROR_INVALID_STATE) }, executor)
                    }
                    if (action == "wake") {
                        player.wakeNotification()
                        // Entering the app is an explicit external refresh;
                        // paused playback stays paused and has no focus request.
                        triggerNotificationUpdate()
                    }
                    else if (action == "shutdown") { player.stop(); stopSelf() }
                    else if (action != "snapshot") player.custom(action, data)
                    Futures.immediateFuture(response())
                } catch (_: Exception) { Futures.immediateFuture(SessionResult(SessionResult.RESULT_ERROR_BAD_VALUE)) }
            }
        }).setSessionActivity(activity).build()
    }
    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaLibrarySession? = session
    override fun onUpdateNotificationAsync(session: MediaSession, startInForegroundRequired: Boolean): ListenableFuture<Void> {
        val intent = if (startInForegroundRequired) player.pendingFocusIntent else null
        val updated = super.onUpdateNotificationAsync(session, startInForegroundRequired)
        if (intent != null) updated.addListener({
            try {
                updated.get()
                if (isPlaybackOngoing) player.pendingFocusIntent?.let { player.foregroundReady(it) }
            }
            catch (_: Exception) { player.foregroundFailed(intent) }
        }, ContextCompat.getMainExecutor(this))
        return updated
    }
    override fun onDestroy() {
        session?.release(); session = null
        player.release()
        super.onDestroy()
    }
}
