package com.ymltsh.sylphymusic.playbackcore

/** Deterministic, side-effect-free reducer. Commands are dispatched by the service. */
object PlaybackReducer {
    fun reduce(s: PlaybackSnapshot, e: PlaybackEvent): PlaybackSnapshot = when (e) {
        is PlaybackEvent.SetMedia -> {
            require(e.id.isNotBlank()) { "empty media id" }
            require(e.positionMs >= 0) { "negative position" }
            s.copy(
                intentEpoch = s.intentEpoch + 1,
                loadEpoch = s.loadEpoch + 1,
                queueRevision = s.queueRevision + 1,
                mediaId = e.id,
                desiredPlay = e.autoplay,
                phase = PlaybackPhase.OPENING,
                focus = if (e.autoplay) FocusPhase.REQUESTED else FocusPhase.NONE,
                output = OutputPhase.UNVERIFIED,
                positionMs = e.positionMs,
                nativePositionBaselineMs = null,
                errorCode = null,
            )
        }
        PlaybackEvent.Play -> {
            if (s.mediaId == null || (s.desiredPlay && s.output == OutputPhase.ADVANCING && s.focus == FocusPhase.HELD)) s
            else s.copy(
                intentEpoch = s.intentEpoch + 1,
                desiredPlay = true,
                focus = FocusPhase.REQUESTED,
                output = OutputPhase.UNVERIFIED,
                nativePositionBaselineMs = null,
                errorCode = null,
            )
        }
        PlaybackEvent.Pause -> s.copy(
            intentEpoch = s.intentEpoch + 1,
            desiredPlay = false,
            focus = FocusPhase.NONE,
            output = OutputPhase.UNVERIFIED,
            nativePositionBaselineMs = null,
        )
        is PlaybackEvent.FocusGranted -> if (e.intentEpoch != s.intentEpoch || !s.desiredPlay) s
            else s.copy(focus = FocusPhase.HELD)
        is PlaybackEvent.FocusDenied -> if (e.intentEpoch != s.intentEpoch || !s.desiredPlay) s
            else s.copy(focus = FocusPhase.DENIED, desiredPlay = false, output = OutputPhase.UNVERIFIED)
        is PlaybackEvent.FocusLost -> s.copy(
            intentEpoch = s.intentEpoch + 1,
            desiredPlay = if (e.permanent) false else s.desiredPlay,
            focus = if (e.permanent) FocusPhase.DENIED else FocusPhase.TRANSIENT_LOSS,
            output = OutputPhase.UNVERIFIED,
            nativePositionBaselineMs = null,
        )
        is PlaybackEvent.NativeOpening -> if (e.loadEpoch != s.loadEpoch) s
            else s.copy(phase = PlaybackPhase.OPENING, output = OutputPhase.UNVERIFIED, nativePositionBaselineMs = null)
        is PlaybackEvent.NativeReady -> if (e.loadEpoch != s.loadEpoch) s
            else s.copy(phase = PlaybackPhase.READY, output = OutputPhase.UNVERIFIED, nativePositionBaselineMs = null)
        is PlaybackEvent.NativeBuffering -> if (e.loadEpoch != s.loadEpoch || e.intentEpoch != s.intentEpoch) s
            else s.copy(phase = PlaybackPhase.BUFFERING, output = OutputPhase.UNVERIFIED, nativePositionBaselineMs = null)
        is PlaybackEvent.NativePosition -> {
            if (e.loadEpoch != s.loadEpoch || e.intentEpoch != s.intentEpoch || e.positionMs < 0) s
            else {
                val previous = s.nativePositionBaselineMs
                // A meaningful, bounded forward native increment is evidence, but not a
                // guarantee of audible PCM. Large seeks are discontinuities, not progress.
                val delta = if (previous == null) 0 else e.positionMs - previous
                val progressing = delta in 100..5000 && s.desiredPlay && s.focus == FocusPhase.HELD &&
                    (s.phase == PlaybackPhase.READY || s.phase == PlaybackPhase.BUFFERING)
                s.copy(
                    positionMs = e.positionMs,
                    nativePositionBaselineMs = e.positionMs,
                    output = if (progressing) OutputPhase.ADVANCING else s.output,
                    phase = if (progressing) PlaybackPhase.READY else s.phase,
                )
            }
        }
        is PlaybackEvent.NativeSeekCompleted -> if (e.loadEpoch != s.loadEpoch || e.intentEpoch != s.intentEpoch || e.positionMs < 0) s
            else s.copy(positionMs = e.positionMs, nativePositionBaselineMs = null, output = OutputPhase.UNVERIFIED)
        is PlaybackEvent.NativeStalled -> if (e.loadEpoch != s.loadEpoch || e.intentEpoch != s.intentEpoch || !s.desiredPlay) s
            else s.copy(phase = PlaybackPhase.BUFFERING, output = OutputPhase.STALLED)
        is PlaybackEvent.NativeEnded -> if (e.loadEpoch != s.loadEpoch || e.intentEpoch != s.intentEpoch) s
            else s.copy(phase = PlaybackPhase.ENDED, output = OutputPhase.UNVERIFIED, desiredPlay = false, nativePositionBaselineMs = null)
        is PlaybackEvent.NativeFailure -> if (e.loadEpoch != s.loadEpoch || e.intentEpoch != s.intentEpoch) s
            else s.copy(phase = PlaybackPhase.FAILED, output = OutputPhase.UNVERIFIED, desiredPlay = false, errorCode = e.code)
    }

    fun project(s: PlaybackSnapshot): MediaSessionView {
        val phase = when {
            s.mediaId == null || s.phase == PlaybackPhase.IDLE || s.phase == PlaybackPhase.FAILED -> MediaPlaybackPhase.IDLE
            s.phase == PlaybackPhase.ENDED -> MediaPlaybackPhase.ENDED
            s.phase == PlaybackPhase.OPENING || s.phase == PlaybackPhase.BUFFERING -> MediaPlaybackPhase.BUFFERING
            s.desiredPlay && s.focus == FocusPhase.HELD && s.output != OutputPhase.ADVANCING -> MediaPlaybackPhase.BUFFERING
            else -> MediaPlaybackPhase.READY
        }
        return MediaSessionView(
            phase = phase,
            playWhenReady = s.desiredPlay,
            suppression = if (s.desiredPlay && s.focus != FocusPhase.HELD) MediaSuppression.AUDIO_FOCUS else MediaSuppression.NONE,
            positionMs = s.positionMs,
            mediaId = s.mediaId,
            errorCode = s.errorCode,
        )
    }
}
