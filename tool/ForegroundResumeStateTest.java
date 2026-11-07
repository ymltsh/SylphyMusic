import com.ryanheise.audioservice.ForegroundResumeState;

/** Offline JVM checks for media-button FGS bookkeeping (no Android SDK). */
public final class ForegroundResumeStateTest {
    private static void check(boolean value, String message) {
        if (!value) throw new AssertionError(message);
    }

    public static void main(String[] args) {
        ForegroundResumeState state = new ForegroundResumeState();
        check(state.needsStart(), "new service must be started");
        state.markStarted();
        check(!state.needsStart(), "resume must not start an existing service again");
        // A denied promotion must not masquerade as foreground success.
        check(!state.isForeground(), "denied promotion stays retryable");
        state.markPromoted(true);
        check(state.isProvisional(), "native media play is provisional");
        check(!state.shouldExitOnPausedState(), "old paused state must not immediately undo a media-key promotion");
        state.confirmPlaying();
        check(!state.isProvisional(), "Dart play confirms promotion");
        check(state.shouldExitOnPausedState(), "later pause demotes service");
        state.markDemoted();
        check(!state.isForeground(), "foreground state is cleared on pause");
        state.markStopped();
        check(state.needsStart(), "after stopSelf a bound service must be started again");
        state.markPromoted(true);
        state.cancelProvisional();
        check(state.shouldExitOnPausedState(), "unconfirmed play releases provisional FGS");
        System.out.println("ForegroundResumeStateTest: PASS");
    }
}
