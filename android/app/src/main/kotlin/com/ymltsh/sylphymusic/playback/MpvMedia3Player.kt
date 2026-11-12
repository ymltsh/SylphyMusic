package com.ymltsh.sylphymusic.playback

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.os.Looper
import android.os.Handler
import android.os.SystemClock
import android.os.PowerManager
import androidx.media3.common.*
import androidx.media3.common.util.UnstableApi
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture
import com.google.common.util.concurrent.SettableFuture
import com.ymltsh.sylphymusic.SylphyApplication
import com.ymltsh.sylphymusic.playbackcore.*
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.UUID

/** The service is the sole queue, focus and mpv owner. Flutter only resolves sources. */
@UnstableApi
class MpvMedia3Player(private val app: SylphyApplication) : SimpleBasePlayer(Looper.getMainLooper()) {
    private val main = Handler(Looper.getMainLooper())
    private var core = PlaybackSnapshot()
    private var queue = mutableListOf<JSONObject>()
    private var playlist = listOf<MediaItemData>()
    private var index = 0
    private var repeat = Player.REPEAT_MODE_ALL
    private var shuffled = false
    private var order = mutableListOf<Int>()
    private var history = mutableListOf<Int>()
    private var revision = 0L
    private var sequence = 0L
    private val sessionId = UUID.randomUUID().toString()
    private var transition = 0L
    private var boundary = "replaced"
    private var discontinuity: Int? = null
    private var nativeEpoch = 0L
    private var sourceEpoch = 0L
    private var rate = 1f
    private var level = 1f
    private var ducked = false
    private var gain = "no"
    private var loaded = false
    private var openPending = false
    private var pendingSeek: Long? = null
    private var seekCompletion: SettableFuture<Void>? = null
    private var seekTimeout: Runnable? = null
    private var seekObserved = false
    private var notificationAwake = false
    private var seekRequestedAt = 0L
    var onFocusPending: ((Long) -> Unit)? = null
    private var closed = false
    private var lastProgress = SystemClock.elapsedRealtime()
    private var lastCheckpoint = 0L
    private var lastPosition = -1L
    private var pausedAt = SystemClock.elapsedRealtime()
    private var currentLease: File? = null
    private var currentLeaseKey: String? = null
    private val checkpoint = File(app.noBackupFilesDir, "media3-queue.json")
    private val stream = NativeStreamAdapter()
    private val audio = app.getSystemService(AudioManager::class.java)
    private val wakeLock = app.getSystemService(PowerManager::class.java)
        .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Sylphy:NativePlayback").apply { setReferenceCounted(false) }
    private var wakeRenewedAt = 0L
    private var focusRequest: AudioFocusRequest? = null
    private var focusListener: AudioManager.OnAudioFocusChangeListener? = null
    private val noisy = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) { setIntent(false) }
    }
    private val engine = NativeMpvEngine(::sample, { epoch -> if (epoch == nativeEpoch && !closed) fail("native_audio") })
    init {
        if (Build.VERSION.SDK_INT >= 33) app.registerReceiver(noisy, IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY), Context.RECEIVER_NOT_EXPORTED)
        else @Suppress("DEPRECATION") app.registerReceiver(noisy, IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY))
        // A service recreation restores metadata and position, never autoplay or credentials.
        try {
            if (checkpoint.exists()) {
                val saved = JSONObject(checkpoint.readText())
                queue = (0 until saved.getJSONArray("items").length()).map { saved.getJSONArray("items").getJSONObject(it) }.toMutableList()
                index = saved.optInt("index").coerceIn(0, (queue.size - 1).coerceAtLeast(0))
                repeat = saved.optInt("repeat", Player.REPEAT_MODE_ALL)
                shuffled = saved.optBoolean("shuffle")
                rate = saved.optDouble("rate", 1.0).toFloat().coerceIn(0.5f, 2f)
                level = saved.optDouble("volume", 1.0).toFloat().coerceIn(0f, 1f)
                gain = saved.optString("gain", "no")
                order = (queue.indices).toMutableList()
                if (shuffled && order.isNotEmpty()) { order.remove(index); order.shuffle(); order.add(0, index) }
                if (queue.isNotEmpty()) core = PlaybackReducer.reduce(core, PlaybackEvent.SetMedia(queue[index].getString("key"), saved.optLong("position").coerceAtLeast(0), false)).copy(phase = PlaybackPhase.IDLE)
                rebuildPlaylist()
            }
        } catch (_: Exception) { queue.clear(); core = PlaybackSnapshot(); rebuildPlaylist() }
    }
    private fun event(event: PlaybackEvent) { core = PlaybackReducer.reduce(core, event) }
    private fun releaseLease(file: File?, key: String?) {
        file?.delete()
        if (key != null) app.playbackLeaseReleased(key)
    }
    private fun remember(index: Int) {
        history.add(index)
        if (history.size > 300) history.removeAt(0)
    }
    private fun notifyState() {
        if (closed) return
        val now = SystemClock.elapsedRealtime()
        if (core.desiredPlay && core.focus == FocusPhase.HELD && core.phase != PlaybackPhase.FAILED && core.phase != PlaybackPhase.ENDED) {
            if (!wakeLock.isHeld || now - wakeRenewedAt > 20000) { wakeLock.acquire(35000); wakeRenewedAt = now }
        } else if (wakeLock.isHeld) wakeLock.release()
        invalidateState(); discontinuity = null
        app.playbackStateChanged(core.desiredPlay)
        pendingFocusIntent?.let { onFocusPending?.invoke(it) }
    }
    private fun rebuildPlaylist() {
        playlist = queue.map { entry ->
            val metadata = MediaMetadata.Builder().setTitle(entry.optString("title"))
                .setArtist(entry.optString("artist")).setAlbumTitle(entry.optString("album"))
                .setIsPlayable(true).setIsBrowsable(false)
            entry.optString("art").takeIf { it.startsWith("content://") }?.let { metadata.setArtworkUri(Uri.parse(it)) }
            MediaItemData.Builder(entry.getString("entryId"))
                .setMediaItem(MediaItem.Builder().setMediaId(entry.getString("key")).setMediaMetadata(metadata.build()).build())
                .setDurationUs(entry.optLong("duration").let { if (it > 0) it * 1000 else C.TIME_UNSET })
                .setIsSeekable(true).build()
        }
    }
    override fun getState(): State {
        val view = PlaybackReducer.project(core)
        val commands = Player.Commands.Builder().addAll(
            Player.COMMAND_PLAY_PAUSE, Player.COMMAND_PREPARE, Player.COMMAND_STOP,
            Player.COMMAND_SET_MEDIA_ITEM,
            Player.COMMAND_RELEASE, Player.COMMAND_GET_CURRENT_MEDIA_ITEM, Player.COMMAND_GET_TIMELINE,
            Player.COMMAND_GET_METADATA, Player.COMMAND_GET_VOLUME, Player.COMMAND_SET_VOLUME,
            Player.COMMAND_SET_SPEED_AND_PITCH, Player.COMMAND_SET_REPEAT_MODE, Player.COMMAND_SET_SHUFFLE_MODE)
        if (queue.isNotEmpty()) commands.addAll(Player.COMMAND_SEEK_IN_CURRENT_MEDIA_ITEM,
            Player.COMMAND_SEEK_TO_MEDIA_ITEM, Player.COMMAND_SEEK_TO_NEXT_MEDIA_ITEM,
            Player.COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM, Player.COMMAND_SEEK_TO_NEXT, Player.COMMAND_SEEK_TO_PREVIOUS)
        return State.Builder().setAvailableCommands(commands.build())
            .setPlaylist(playlist).setCurrentMediaItemIndex(if (queue.isEmpty()) C.INDEX_UNSET else index)
            .setContentPositionMs(core.positionMs)
            .setPlaybackState(if (!core.desiredPlay && !loaded) {
                if (notificationAwake && queue.isNotEmpty() && core.errorCode == null) Player.STATE_READY else Player.STATE_IDLE
            } else when (view.phase) {
                MediaPlaybackPhase.IDLE -> Player.STATE_IDLE
                MediaPlaybackPhase.BUFFERING -> if (!core.desiredPlay && loaded) Player.STATE_READY else Player.STATE_BUFFERING
                MediaPlaybackPhase.READY -> Player.STATE_READY
                MediaPlaybackPhase.ENDED -> Player.STATE_ENDED
            })
            .setPlayWhenReady(core.desiredPlay, Player.PLAY_WHEN_READY_CHANGE_REASON_USER_REQUEST)
            .setPlaybackSuppressionReason(if (view.suppression == MediaSuppression.AUDIO_FOCUS) Player.PLAYBACK_SUPPRESSION_REASON_TRANSIENT_AUDIO_FOCUS_LOSS else Player.PLAYBACK_SUPPRESSION_REASON_NONE)
            .setPlayerError(core.errorCode?.let { PlaybackException("音频播放失败，请重试", null, PlaybackException.ERROR_CODE_IO_UNSPECIFIED) })
            .setRepeatMode(repeat).setShuffleModeEnabled(shuffled)
            .setPlaybackParameters(PlaybackParameters(rate)).setVolume(level).apply {
                discontinuity?.let { setPositionDiscontinuity(it, core.positionMs) }
            }.build()
    }
    fun wakeNotification() {
        // Metadata-only READY while paused: never open audio, request focus or
        // manufacture a play intent just to restore the system media card.
        notificationAwake = true
        notifyState()
    }
    fun awaitSeek(): ListenableFuture<Void> = seekCompletion ?: Futures.immediateVoidFuture()
    private fun cancelSeek() {
        seekTimeout?.let { main.removeCallbacks(it) }; seekTimeout = null
        val completion = seekCompletion; seekCompletion = null
        pendingSeek = null; seekObserved = false
        completion?.setException(IllegalStateException("Seek interrupted"))
    }
    private fun beginSeek(position: Long, opening: Boolean) {
        cancelSeek()
        pendingSeek = position; seekObserved = opening
        seekRequestedAt = SystemClock.elapsedRealtime()
        val completion = SettableFuture.create<Void>()
        seekCompletion = completion
        val timeout = Runnable { if (seekCompletion === completion) fail("seek_timeout") }
        seekTimeout = timeout
        main.postDelayed(timeout, 8000)
    }
    fun libraryItems(): List<MediaItem> = playlist.map { it.mediaItem }
    fun snapshotJson(knownRevision: Long = -1): String = JSONObject().put("revision", revision).apply {
        if (knownRevision != revision) {
            put("items", JSONArray(queue)); put("order", JSONArray(order)); put("history", JSONArray(history))
        }
    }.put("sessionId", sessionId).put("sequence", ++sequence).put("transition", transition).put("boundary", boundary)
        .put("index", index).put("position", core.positionMs).put("repeat", repeat).put("shuffle", shuffled)
        .put("playWhenReady", core.desiredPlay).put("playing", core.desiredPlay && core.focus == FocusPhase.HELD && core.output == OutputPhase.ADVANCING)
        .put("buffering", core.desiredPlay && (core.phase == PlaybackPhase.OPENING || core.phase == PlaybackPhase.BUFFERING || core.output != OutputPhase.ADVANCING))
        .put("loaded", loaded).put("duration", queue.getOrNull(index)?.optLong("duration") ?: 0)
        .put("error", core.errorCode ?: JSONObject.NULL).put("rate", rate).put("volume", level * 100).put("gain", gain).toString()

    fun custom(action: String, data: JSONObject) {
        when (action) {
            "queue" -> {
                val array = data.getJSONArray("items")
                val next = (0 until array.length()).map { array.getJSONObject(it) }.toMutableList()
                require(next.all { it.optString("entryId").isNotEmpty() && it.optString("key").isNotEmpty() })
                require(next.map { it.getString("entryId") }.toSet().size == next.size)
                val sameEntry = queue.getOrNull(index)?.optString("entryId")
                val target = data.optInt("index").coerceIn(0, (next.size - 1).coerceAtLeast(0))
                val keepOutput = data.optBoolean("keepOutput") && next.getOrNull(target)?.optString("entryId") == sameEntry
                queue = next; index = target; revision++
                order = queue.indices.toMutableList()
                if (shuffled && order.isNotEmpty()) { order.remove(index); order.shuffle(); order.add(0, index) }
                history.clear(); rebuildPlaylist()
                if (queue.isEmpty()) stopOutput(clear = true)
                else if (!keepOutput) { boundary = "replaced"; open(index, data.optLong("position").coerceAtLeast(0), data.optBoolean("play")) }
                notifyState(); saveCheckpoint()
            }
            "gain" -> { gain = data.getString("value").takeIf { it in listOf("no", "track", "album") } ?: "no"; engine.execute(nativeEpoch) { property("replaygain", gain) } }
            "art" -> {
                val key = data.getString("key"); val uri = data.optString("uri")
                if (uri.isEmpty() || uri.startsWith("content://${app.packageName}.mediaartwork/")) {
                    queue.filter { it.optString("key") == key }.forEach { it.put("art", uri) }
                    revision++; rebuildPlaylist(); notifyState()
                }
            }
            "invalidate" -> {
                val id = data.getString("sourceId")
                queue.filter { it.optString("sourceId") == id }.forEach { it.remove("local") }
                if (queue.getOrNull(index)?.optString("sourceId") == id) { stopOutput(); saveCheckpoint() }
            }
            "retry" -> if (queue.isNotEmpty()) open(index, core.positionMs, true)
            else -> error("Unsupported playback command")
        }
    }
    private fun requestFocus(): Boolean {
        abandonFocus()
        val intent = core.intentEpoch
        val listener = AudioManager.OnAudioFocusChangeListener { change ->
            main.post {
                if (closed || intent != core.intentEpoch || !core.desiredPlay) return@post
                when (change) {
                    AudioManager.AUDIOFOCUS_GAIN -> {
                        ducked = false
                        event(PlaybackEvent.FocusGranted(intent)); lastProgress = SystemClock.elapsedRealtime()
                        val epoch = ++nativeEpoch
                        engine.execute(epoch) { property("volume", (level * 100).toString()); property("pause", "no") }
                    }
                    AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> {
                        ducked = true
                        engine.execute(nativeEpoch) { property("volume", (level * 25).toString()) }
                    }
                    AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
                        // Preserve the listener's intent epoch for the eventual GAIN.
                        core = core.copy(focus = FocusPhase.TRANSIENT_LOSS, output = OutputPhase.UNVERIFIED, nativePositionBaselineMs = null)
                        val epoch = ++nativeEpoch; engine.execute(epoch) { property("pause", "yes") }
                        main.postDelayed({
                            if (!closed && core.intentEpoch == intent && core.focus == FocusPhase.TRANSIENT_LOSS) setIntent(false)
                        }, 5 * 60 * 1000L)
                    }
                    AudioManager.AUDIOFOCUS_LOSS -> setIntent(false)
                }
                notifyState()
            }
        }
        focusListener = listener
        val result = if (Build.VERSION.SDK_INT >= 26) {
            focusRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                .setAudioAttributes(android.media.AudioAttributes.Builder().setUsage(android.media.AudioAttributes.USAGE_MEDIA).setContentType(android.media.AudioAttributes.CONTENT_TYPE_MUSIC).build())
                .setWillPauseWhenDucked(false).setAcceptsDelayedFocusGain(false).setOnAudioFocusChangeListener(listener, main).build()
            audio.requestAudioFocus(focusRequest!!)
        } else @Suppress("DEPRECATION") audio.requestAudioFocus(listener, AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN)
        event(if (result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED) PlaybackEvent.FocusGranted(intent) else PlaybackEvent.FocusDenied(intent))
        return result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
    }
    private fun abandonFocus() {
        if (Build.VERSION.SDK_INT >= 26) focusRequest?.let { audio.abandonAudioFocusRequest(it) }
        else @Suppress("DEPRECATION") focusListener?.let { audio.abandonAudioFocus(it) }
        focusRequest = null; focusListener = null; ducked = false
    }
    val pendingFocusIntent: Long? get() = if (core.desiredPlay && core.focus == FocusPhase.REQUESTED) core.intentEpoch else null
    fun foregroundReady(intent: Long) {
        if (closed || pendingFocusIntent != intent) return
        if (requestFocus()) {
            lastProgress = SystemClock.elapsedRealtime(); lastPosition = -1
            val epoch = ++nativeEpoch
            engine.execute(epoch) { property("pause", "no") }
        } else fail("focus_denied")
        notifyState()
    }
    fun foregroundFailed(intent: Long) { if (!closed && pendingFocusIntent == intent) fail("foreground_unavailable") }
    private fun setIntent(play: Boolean) {
        if (queue.isEmpty()) return
        if (play && core.desiredPlay && core.focus == FocusPhase.HELD && core.output == OutputPhase.ADVANCING) return
        val reopen = play && ((!core.desiredPlay && queue[index].optJSONObject("local") == null) ||
            SystemClock.elapsedRealtime() - pausedAt > 15 * 60 * 1000L)
        if (!play) pausedAt = SystemClock.elapsedRealtime()
        event(if (play) PlaybackEvent.Play else PlaybackEvent.Pause)
        abandonFocus()
        lastProgress = SystemClock.elapsedRealtime(); lastPosition = -1
        if (play && !openPending && (reopen || !loaded || core.phase == PlaybackPhase.ENDED || core.phase == PlaybackPhase.FAILED)) {
            open(index, core.positionMs, core.desiredPlay)
        } else {
            val epoch = ++nativeEpoch
            val paused = !core.desiredPlay || core.focus != FocusPhase.HELD
            engine.execute(epoch) { property("pause", if (paused) "yes" else "no") }
        }
        notifyState(); saveCheckpoint()
    }
    private fun open(target: Int, position: Long, play: Boolean) {
        if (target !in queue.indices) return
        cancelSeek()
        transition++; revision++
        index = target; loaded = false; openPending = true; pendingSeek = null
        lastPosition = -1; lastProgress = SystemClock.elapsedRealtime()
        event(PlaybackEvent.SetMedia(queue[index].getString("key"), position, play))
        abandonFocus()
        val load = ++sourceEpoch
        val epoch = ++nativeEpoch
        // Stop the previous decoder before releasing its native cache lease.
        val retired = currentLease; val retiredKey = currentLeaseKey
        currentLease = null; currentLeaseKey = null
        stream.cancel()
        engine.execute(epoch) { stopAndDrain(); main.post { releaseLease(retired, retiredKey) } }
        val entry = queue[index]
        val key = entry.getString("key")
        val resolved: (JSONObject?) -> Unit = resolved@ { descriptor ->
            val lease = descriptor?.optString("lease")?.takeIf { it.isNotEmpty() }?.let(::File)
            if (closed || load != sourceEpoch) { releaseLease(lease, key); return@resolved }
            if (descriptor == null) { fail("source_unavailable"); return@resolved }
            try {
                val path = descriptor.optString("file")
                val uri = if (path.isNotEmpty()) {
                    val file = File(path)
                    require(file.isFile && file.canRead() && file.length() == descriptor.getLong("bytes"))
                    entry.put("local", JSONObject().put("file", path).put("bytes", file.length()).put("modified", file.lastModified())
                        .put("leaseRoot", descriptor.optString("leaseRoot")).put("leaseKey", descriptor.optString("leaseKey")))
                    file.absolutePath
                } else {
                    entry.remove("local")
                    val headers = descriptor.optJSONObject("headers") ?: JSONObject()
                    stream.open(descriptor.getString("uri"), headers.keys().asSequence().associateWith { headers.getString(it) })
                }
                currentLease = lease; currentLeaseKey = key
                val start = core.positionMs
                val paused = !core.desiredPlay || core.focus != FocusPhase.HELD
                val commandEpoch = ++nativeEpoch
                engine.execute(commandEpoch) {
                    property("pause", "yes"); property("speed", rate.toString()); property("volume", (level * 100).toString())
                    property("replaygain", gain)
                    // Bundled mpv 0.35 predates loadfile's playlist-index argument.
                    property("start", (start / 1000.0).toString())
                    command("loadfile", uri, "replace")
                    property("pause", if (paused) "yes" else "no")
                }
                saveCheckpoint()
            } catch (_: Exception) { releaseLease(lease, key); fail("source_unavailable") }
            notifyState()
        }
        val local = entry.optJSONObject("local")
        val localFile = local?.optString("file")?.let(::File)
        if (local != null && localFile != null && localFile.isFile && localFile.length() == local.optLong("bytes") && localFile.lastModified() == local.optLong("modified") && local.optString("leaseRoot").isNotEmpty()) {
            val directory = File(local.getString("leaseRoot"), "${android.os.Process.myPid()}/${local.getString("leaseKey")}")
            directory.mkdirs()
            val marker = File(directory, UUID.randomUUID().toString())
            try {
                marker.writeText("")
                resolved(JSONObject(local.toString()).put("lease", marker.absolutePath))
            } catch (_: Exception) { marker.delete(); app.resolvePlaybackSource(key, resolved) }
        } else app.resolvePlaybackSource(key, resolved)
        notifyState()
    }
    private fun sample(epoch: Long, values: DoubleArray) {
        if (closed || epoch != nativeEpoch || queue.isEmpty()) return
        val now = SystemClock.elapsedRealtime()
        if (pendingSeek != null) seekObserved = seekObserved || values[7] != 0.0 || values.getOrElse(8) { 0.0 } != 0.0
        if (values[5] != 0.0) { fail("native_stream"); return }
        if (values[4] != 0.0) {
            if (repeat == Player.REPEAT_MODE_ONE) {
                boundary = "repeatOne"
                discontinuity = Player.DISCONTINUITY_REASON_AUTO_TRANSITION
                open(index, 0, core.desiredPlay)
            } else {
                val next = nextIndex(1)
                if (next == null) { event(PlaybackEvent.NativeEnded(core.loadEpoch, core.intentEpoch)); abandonFocus(); notifyState(); saveCheckpoint() }
                else { boundary = "completed"; remember(index); open(next, 0, core.desiredPlay) }
            }
            return
        }
        if (values[6] != 0.0 && !loaded) { loaded = true; openPending = false; event(PlaybackEvent.NativeReady(core.loadEpoch)) }
        val duration = values[1].toLong()
        if (duration > 0 && kotlin.math.abs(queue[index].optLong("duration") - duration) > 500) {
            queue[index].put("duration", duration); revision++; rebuildPlaylist()
        }
        if (loaded && values[0] >= 0) {
            val pos = values[0].toLong()
            val target = pendingSeek
            if (target != null) {
                seekObserved = seekObserved || values[7] != 0.0 || values.getOrElse(8) { 0.0 } != 0.0
                val tolerance = maxOf(350L, (rate * 400).toLong())
                if (!seekObserved || pos - target !in -100L..tolerance) {
                    if (now - seekRequestedAt > 8000) fail("seek_timeout")
                    else notifyState()
                    return
                }
                pendingSeek = null
                event(PlaybackEvent.NativeSeekCompleted(core.loadEpoch, core.intentEpoch, pos))
            }
            if (values[7] != 0.0) event(PlaybackEvent.NativeSeekCompleted(core.loadEpoch, core.intentEpoch, pos))
            if (values[3] != 0.0) event(PlaybackEvent.NativeBuffering(core.loadEpoch, core.intentEpoch))
            else if (values[2] == 0.0) {
                event(PlaybackEvent.NativePosition(core.loadEpoch, core.intentEpoch, pos))
                if (lastPosition >= 0 && pos - lastPosition in 50..5000) lastProgress = now
            } else core = core.copy(positionMs = pos)
            lastPosition = pos
        }
        if (core.desiredPlay && core.focus == FocusPhase.HELD) {
            if (now - lastProgress > 3000) event(PlaybackEvent.NativeStalled(core.loadEpoch, core.intentEpoch))
            if (now - lastProgress > 30000) { fail("progress_timeout"); return }
        }
        if (now - lastCheckpoint > 5000) { lastCheckpoint = now; saveCheckpoint() }
        notifyState()
        // The UI's seek Future resolves only after the confirmed position is
        // reflected in the session snapshot, not when mpv accepts the command.
        if (pendingSeek == null && seekCompletion != null) {
            seekTimeout?.let { main.removeCallbacks(it) }; seekTimeout = null
            val completion = seekCompletion; seekCompletion = null
            completion?.set(null)
        }
    }
    private fun fail(code: String) {
        cancelSeek()
        event(PlaybackEvent.NativeFailure(core.loadEpoch, core.intentEpoch, code))
        val epoch = ++nativeEpoch
        stream.cancel(); abandonFocus()
        engine.execute(epoch) { stopAndDrain() }
        loaded = false; openPending = false; pendingSeek = null; notifyState(); saveCheckpoint()
    }
    private fun nextIndex(direction: Int): Int? {
        if (queue.isEmpty()) return null
        if (direction < 0 && history.isNotEmpty()) return history.removeAt(history.lastIndex)
        val at = order.indexOf(index).coerceAtLeast(0)
        val next = at + direction
        return if (next in order.indices) order[next] else if (repeat == Player.REPEAT_MODE_OFF) null else order[(next + order.size) % order.size]
    }
    override fun handleSetPlayWhenReady(playWhenReady: Boolean): ListenableFuture<*> { setIntent(playWhenReady); return Futures.immediateVoidFuture() }
    override fun handleSetMediaItems(mediaItems: List<MediaItem>, startIndex: Int, startPositionMs: Long): ListenableFuture<*> {
        // External browsers can select an existing, exact media identity. They
        // cannot introduce URLs, credentials or arbitrary local files.
        val selected = mediaItems.map { item ->
            JSONObject((queue.firstOrNull { it.optString("key") == item.mediaId }
                ?: throw IllegalArgumentException("Unknown media identity")).toString())
                .put("entryId", UUID.randomUUID().toString())
        }
        custom("queue", JSONObject().put("items", JSONArray(selected))
            .put("index", if (startIndex == C.INDEX_UNSET) 0 else startIndex)
            .put("position", if (startPositionMs == C.TIME_UNSET) 0 else startPositionMs).put("play", core.desiredPlay))
        return Futures.immediateVoidFuture()
    }
    override fun handlePrepare(): ListenableFuture<*> { if (queue.isNotEmpty() && !loaded && !openPending) open(index, core.positionMs, core.desiredPlay); return Futures.immediateVoidFuture() }
    override fun handleSeek(mediaItemIndex: Int, positionMs: Long, seekCommand: Int): ListenableFuture<*> {
        if (queue.isEmpty()) return Futures.immediateVoidFuture()
        val target = when (seekCommand) {
            Player.COMMAND_SEEK_TO_NEXT, Player.COMMAND_SEEK_TO_NEXT_MEDIA_ITEM -> nextIndex(1)
            Player.COMMAND_SEEK_TO_PREVIOUS, Player.COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM -> if (core.positionMs > 3000) index else nextIndex(-1)
            else -> mediaItemIndex
        }
        if (target != null && target in queue.indices) {
            val position = if (positionMs == C.TIME_UNSET) 0 else positionMs.coerceAtLeast(0)
            if (target != index || !loaded) {
                boundary = "manualSkip"
                if (seekCommand != Player.COMMAND_SEEK_TO_PREVIOUS && seekCommand != Player.COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM) remember(index)
                open(target, position, core.desiredPlay)
                if (seekCommand == Player.COMMAND_SEEK_IN_CURRENT_MEDIA_ITEM) beginSeek(position, opening = true)
            }
            else {
                event(PlaybackEvent.NativeSeekCompleted(core.loadEpoch, core.intentEpoch, position))
                beginSeek(position, opening = false)
                lastProgress = SystemClock.elapsedRealtime(); lastPosition = -1
                val epoch = ++nativeEpoch
                engine.execute(epoch) { command("seek", (position / 1000.0).toString(), "absolute+exact") }
                notifyState(); saveCheckpoint()
            }
        }
        return Futures.immediateVoidFuture()
    }
    override fun handleSetRepeatMode(repeatMode: Int): ListenableFuture<*> { repeat = repeatMode; revision++; notifyState(); saveCheckpoint(); return Futures.immediateVoidFuture() }
    override fun handleSetShuffleModeEnabled(shuffleModeEnabled: Boolean): ListenableFuture<*> {
        shuffled = shuffleModeEnabled; revision++; order = queue.indices.toMutableList()
        if (shuffled && order.isNotEmpty()) { order.remove(index); order.shuffle(); order.add(0, index) }
        notifyState(); saveCheckpoint(); return Futures.immediateVoidFuture()
    }
    override fun handleSetPlaybackParameters(playbackParameters: PlaybackParameters): ListenableFuture<*> {
        rate = playbackParameters.speed.coerceIn(0.5f, 2f)
        engine.execute(nativeEpoch) { property("speed", rate.toString()) }; notifyState(); return Futures.immediateVoidFuture()
    }
    override fun handleSetVolume(volume: Float): ListenableFuture<*> {
        level = volume.coerceIn(0f, 1f); engine.execute(nativeEpoch) { property("volume", (level * if (ducked) 25 else 100).toString()) }
        notifyState(); return Futures.immediateVoidFuture()
    }
    private fun stopOutput(clear: Boolean = false) {
        cancelSeek()
        ++sourceEpoch; val epoch = ++nativeEpoch; event(PlaybackEvent.Pause)
        core = if (clear) PlaybackSnapshot() else core.copy(phase = PlaybackPhase.IDLE)
        loaded = false; openPending = false; pendingSeek = null; stream.cancel(); abandonFocus()
        val lease = currentLease; val key = currentLeaseKey
        currentLease = null; currentLeaseKey = null
        engine.execute(epoch) { stopAndDrain(); main.post { releaseLease(lease, key) } }
        notifyState()
    }
    override fun handleStop(): ListenableFuture<*> { stopOutput(); saveCheckpoint(); return Futures.immediateVoidFuture() }
    override fun handleRelease(): ListenableFuture<*> {
        cancelSeek()
        saveCheckpoint(); closed = true; ++sourceEpoch; abandonFocus(); app.unregisterReceiver(noisy); stream.close()
        if (wakeLock.isHeld) wakeLock.release()
        val lease = currentLease; val key = currentLeaseKey
        currentLease = null; currentLeaseKey = null
        engine.close { releaseLease(lease, key) }
        return Futures.immediateVoidFuture()
    }
    private fun saveCheckpoint() {
        // Metadata and verified local paths only. Never persist remote URLs or headers.
        val copy = queue.map { JSONObject(it.toString()) }
        val json = JSONObject().put("items", JSONArray(copy)).put("index", index).put("position", core.positionMs).put("repeat", repeat).put("shuffle", shuffled)
            .put("rate", rate).put("volume", level).put("gain", gain)
        val value = json.toString()
        // The queue file is small; I/O stays off the MediaSession application thread.
        app.savePlaybackCheckpoint(checkpoint, value)
    }
}
