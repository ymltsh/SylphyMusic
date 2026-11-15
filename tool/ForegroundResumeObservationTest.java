import com.ryanheise.audioservice.ForegroundResumeState;

/** Run with javac/java without Android or Flutter. */
public final class ForegroundResumeObservationTest {
    public static void main(String[] args) {
        ForegroundResumeState state = new ForegroundResumeState();
        if (!state.needsStart() || state.isOsConfirmed()) throw new AssertionError();
        state.markStarted();
        state.markPromoted(true);
        if (!state.isForeground() || state.isOsConfirmed()) throw new AssertionError();
        state.markOsConfirmed();
        if (!state.isOsConfirmed()) throw new AssertionError();
        state.markDemoted();
        if (state.isForeground() || state.isOsConfirmed()) throw new AssertionError();
        // A provisional request is not an OS confirmation either.
        state.markPromoted(true);
        if (state.isOsConfirmed()) throw new AssertionError();
        System.out.println("FGS requested/observed distinction: PASS");
    }
}
