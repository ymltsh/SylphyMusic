package com.ymltsh.sylphymusic.playbackcore

/** Never retry a startup buffer, seek, paused output or an already retried item. */
object PlaybackRecoveryPolicy {
    const val REOPEN_AFTER_MS = 20_000L
    fun shouldReopen(
        gapMs: Long,
        loaded: Boolean,
        opening: Boolean,
        seeking: Boolean,
        buffering: Boolean,
        observedProgress: Boolean,
        reopenCount: Int,
    ): Boolean = gapMs >= REOPEN_AFTER_MS && loaded && !opening && !seeking && !buffering &&
        observedProgress && reopenCount == 0
}
