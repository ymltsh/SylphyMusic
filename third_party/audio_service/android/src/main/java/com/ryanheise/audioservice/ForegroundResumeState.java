package com.ryanheise.audioservice;

/** Logical foreground bookkeeping, deliberately independent of Android SDK. */
public final class ForegroundResumeState {
    private boolean started;
    private boolean foreground;
    private boolean provisional;

    public boolean needsStart() { return !started; }
    public void markStarted() { started = true; }
    public void markStopped() { started = false; }
    public boolean isForeground() { return foreground; }
    public boolean isProvisional() { return provisional; }
    public void markPromoted(boolean early) {
        foreground = true;
        provisional = early;
    }
    public void markProvisional() {
        if (foreground) provisional = true;
    }
    public void confirmPlaying() { provisional = false; }
    public void cancelProvisional() { provisional = false; }
    public boolean shouldExitOnPausedState() {
        return foreground && !provisional;
    }
    public void markDemoted() {
        foreground = false;
        provisional = false;
    }
}
