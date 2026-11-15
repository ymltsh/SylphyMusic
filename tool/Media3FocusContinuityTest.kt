// No Android SDK needed: pure reducer contract for continuous background playback.
import com.ymltsh.sylphymusic.playbackcore.*

fun main() {
    fun start(): PlaybackSnapshot {
        var state = PlaybackReducer.reduce(PlaybackSnapshot(), PlaybackEvent.SetMedia("a", 0, true))
        check(state.focus == FocusPhase.REQUESTED)
        state = PlaybackReducer.reduce(state, PlaybackEvent.FocusGranted(state.intentEpoch))
        check(state.focus == FocusPhase.HELD)
        return state
    }
    val held = start()
    val next = PlaybackReducer.reduce(held, PlaybackEvent.SetMedia("b", 0, true))
    check(next.desiredPlay && next.focus == FocusPhase.HELD)
    check(next.intentEpoch == held.intentEpoch + 1)
    check(next.loadEpoch == held.loadEpoch + 1)
    check(next.output == OutputPhase.UNVERIFIED)
    check(next.phase == PlaybackPhase.OPENING)

    val paused = PlaybackReducer.reduce(held, PlaybackEvent.Pause)
    check(PlaybackReducer.reduce(paused, PlaybackEvent.SetMedia("b", 0, false)).focus == FocusPhase.NONE)
    check(PlaybackReducer.reduce(paused, PlaybackEvent.SetMedia("b", 0, true)).focus == FocusPhase.REQUESTED)

    val transient = PlaybackReducer.reduce(held, PlaybackEvent.FocusLost(permanent = false))
    check(PlaybackReducer.reduce(transient, PlaybackEvent.SetMedia("b", 0, true)).focus == FocusPhase.REQUESTED)
    val denied = PlaybackReducer.reduce(held, PlaybackEvent.FocusLost(permanent = true))
    check(!denied.desiredPlay)
    check(PlaybackReducer.reduce(denied, PlaybackEvent.SetMedia("b", 0, false)).focus == FocusPhase.NONE)
    val interrupted = PlaybackReducer.reduce(next, PlaybackEvent.FocusLost(permanent = false))
    check(interrupted.focus == FocusPhase.TRANSIENT_LOSS)
    val resumed = PlaybackReducer.reduce(interrupted, PlaybackEvent.FocusGranted(interrupted.intentEpoch))
    check(resumed.focus == FocusPhase.HELD && resumed.desiredPlay)
    println("Media3 focus continuity tests passed")
}
