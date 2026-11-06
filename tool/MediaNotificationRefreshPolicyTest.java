import com.ryanheise.audioservice.MediaNotificationRefreshPolicy;

/** Offline JVM regression checks: javac + java, no Android runtime needed. */
public final class MediaNotificationRefreshPolicyTest {
    private static final int PLAYING = 3;
    private static final int BUFFERING = 6;

    private static void check(boolean expected, boolean actual, String caseName) {
        if (expected != actual) throw new AssertionError(caseName);
    }

    public static void main(String[] args) {
        check(true, MediaNotificationRefreshPolicy.requiresRefresh(
                BUFFERING, PLAYING, PLAYING, true, 0f, 1f,
                0, 1000, 700, 1700), "buffering to real playback");
        check(true, MediaNotificationRefreshPolicy.requiresRefresh(
                PLAYING, PLAYING, PLAYING, true, 0f, 1f,
                0, 1000, 500, 1500), "clock starts after confirmation");
        check(false, MediaNotificationRefreshPolicy.requiresRefresh(
                PLAYING, PLAYING, PLAYING, true, 1f, 1f,
                1000, 1000, 3000, 3000), "ordinary progress is extrapolated");
        check(true, MediaNotificationRefreshPolicy.requiresRefresh(
                PLAYING, PLAYING, PLAYING, true, 1f, 0f,
                1000, 1000, 2000, 2000), "clock freezes");
        check(true, MediaNotificationRefreshPolicy.requiresRefresh(
                PLAYING, PLAYING, PLAYING, true, 1f, 1f,
                1000, 1000, 6500, 2000), "seek discontinuity");
        check(true, MediaNotificationRefreshPolicy.requiresRefresh(
                PLAYING, PLAYING, PLAYING, true, 1f, 1.25f,
                1000, 1000, 2000, 2000), "rate change");
        check(false, MediaNotificationRefreshPolicy.requiresRefresh(
                BUFFERING, BUFFERING, PLAYING, true, 0f, 0f,
                0, 1000, 0, 3000), "loading never advances");
        System.out.println("MediaNotificationRefreshPolicyTest: PASS");
    }
}
