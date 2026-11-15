import com.ymltsh.sylphymusic.playbackcore.PlaybackRecoveryPolicy

fun main() {
    val policy = PlaybackRecoveryPolicy
    fun eligible(gap: Long, loaded: Boolean = true, opening: Boolean = false,
                 seeking: Boolean = false, buffering: Boolean = false, progressed: Boolean = true,
                 tries: Int = 0): Boolean =
        policy.shouldReopen(gap, loaded, opening, seeking, buffering, progressed, tries)
    check(!eligible(19_999L))
    check(eligible(20_000L))
    check(!eligible(30_001L, loaded = false))
    check(!eligible(30_001L, opening = true))
    check(!eligible(30_001L, seeking = true))
    check(!eligible(30_001L, buffering = true))
    check(!eligible(30_001L, progressed = false))
    check(!eligible(30_001L, tries = 1))
    println("PlaybackRecoveryPolicyTest PASS")
}
