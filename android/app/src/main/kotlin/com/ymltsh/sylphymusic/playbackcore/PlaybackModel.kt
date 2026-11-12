package com.ymltsh.sylphymusic.playbackcore

/** Pure Android-independent playback state. No Dart isolate, Media3 or JNI dependencies. */
enum class PlaybackPhase { IDLE, OPENING, BUFFERING, READY, ENDED, FAILED }
enum class FocusPhase { NONE, REQUESTED, HELD, TRANSIENT_LOSS, DENIED }
enum class OutputPhase { UNVERIFIED, ADVANCING, STALLED }

/** Core owns the intent, load and logical position; UI and Media3 consume projections. */
data class PlaybackSnapshot(
    val intentEpoch: Long = 0,
    val loadEpoch: Long = 0,
    val queueRevision: Long = 0,
    val mediaId: String? = null,
    val desiredPlay: Boolean = false,
    val phase: PlaybackPhase = PlaybackPhase.IDLE,
    val focus: FocusPhase = FocusPhase.NONE,
    val output: OutputPhase = OutputPhase.UNVERIFIED,
    val positionMs: Long = 0,
    val nativePositionBaselineMs: Long? = null,
    val errorCode: String? = null,
)

/** Events are processed serially on the playback service application looper. */
sealed interface PlaybackEvent {
    data class SetMedia(val id: String, val positionMs: Long = 0, val autoplay: Boolean = false) : PlaybackEvent
    data object Play : PlaybackEvent
    data object Pause : PlaybackEvent
    data class FocusGranted(val intentEpoch: Long) : PlaybackEvent
    data class FocusDenied(val intentEpoch: Long) : PlaybackEvent
    data class FocusLost(val permanent: Boolean) : PlaybackEvent
    data class NativeOpening(val loadEpoch: Long) : PlaybackEvent
    data class NativeReady(val loadEpoch: Long) : PlaybackEvent
    data class NativeBuffering(val loadEpoch: Long, val intentEpoch: Long) : PlaybackEvent
    data class NativePosition(val loadEpoch: Long, val intentEpoch: Long, val positionMs: Long) : PlaybackEvent
    data class NativeSeekCompleted(val loadEpoch: Long, val intentEpoch: Long, val positionMs: Long) : PlaybackEvent
    data class NativeStalled(val loadEpoch: Long, val intentEpoch: Long) : PlaybackEvent
    data class NativeEnded(val loadEpoch: Long, val intentEpoch: Long) : PlaybackEvent
    data class NativeFailure(val loadEpoch: Long, val intentEpoch: Long, val code: String) : PlaybackEvent
}

enum class MediaPlaybackPhase { IDLE, BUFFERING, READY, ENDED }
enum class MediaSuppression { NONE, AUDIO_FOCUS }

/** Adapter maps these values to Media3 Player.State in a single place. */
data class MediaSessionView(
    val phase: MediaPlaybackPhase,
    val playWhenReady: Boolean,
    val suppression: MediaSuppression,
    val positionMs: Long,
    val mediaId: String?,
    val errorCode: String?,
)
